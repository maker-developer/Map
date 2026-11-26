#!/usr/bin/env python3
"""Build source-preserving place databases for South Florida.

Outputs separate SQLite/FTS5 files per source so that each dataset keeps its
own provenance and license. Optional details remain NULL when unavailable.
Requires duckdb, shapely, osmium-tool; Commons photos are retained only when
the file has a reusable public-domain, CC0, CC BY or CC BY-SA license.
"""
from __future__ import annotations

import hashlib
import gzip
import html
import json
import re
import shutil
import sqlite3
import subprocess
import time
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple
from urllib.parse import urlencode
from urllib.request import Request, urlopen

import duckdb
from shapely.geometry import Point, box, shape
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / "data/.cache/places"
OUT = ROOT / "public/data/places"
PBF = CACHE / "florida.osm.pbf"
PBF_URL = "https://download.geofabrik.de/north-america/us/florida-latest.osm.pbf"
COUNTY_URL = (
    "https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/State_County/"
    "MapServer/1/query?where=STATE%3D%2712%27%20AND%20COUNTY%20IN%20"
    "(%27011%27%2C%27086%27%2C%27087%27)&outFields=NAME%2CSTATE%2CCOUNTY%2C"
    "GEOID&outSR=4326&f=geojson"
)
OVERTURE_RELEASE = "2026-11-18.0"
OVERTURE_GLOB = (
    "s3://overturemaps-us-west-2/release/" + OVERTURE_RELEASE +
    "/theme=places/type=place/*"
)
UA = "Map place-data builder/1.0 (data provenance and license preserved)"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"
SCHEMA = """
PRAGMA journal_mode=OFF;
PRAGMA synchronous=OFF;
CREATE TABLE lugares (
  id INTEGER PRIMARY KEY,
  source_id TEXT NOT NULL,
  entity_key TEXT NOT NULL,
  source TEXT NOT NULL,
  license TEXT,
  attribution TEXT NOT NULL,
  source_url TEXT,
  source_updated TEXT,
  captured_at TEXT NOT NULL,
  name TEXT NOT NULL,
  aliases_json TEXT,
  brand TEXT,
  kind TEXT NOT NULL,
  category TEXT,
  subcategory TEXT,
  description TEXT,
  lon REAL,
  lat REAL,
  address TEXT,
  locality TEXT,
  region TEXT,
  postal_code TEXT,
  phone TEXT,
  phones_json TEXT,
  email TEXT,
  website TEXT,
  websites_json TEXT,
  socials_json TEXT,
  opening_hours TEXT,
  payment_json TEXT,
  services_json TEXT,
  operating_status TEXT,
  confidence REAL,
  photos_json TEXT,
  details_json TEXT NOT NULL
);
CREATE INDEX lugares_kind_category ON lugares(kind, category);
CREATE INDEX lugares_point ON lugares(lat, lon);
CREATE INDEX lugares_entity_key ON lugares(entity_key);
CREATE VIRTUAL TABLE lugares_fts USING fts5(
  name, brand, aliases, address, locality, category, description,
  tokenize='unicode61 remove_diacritics 2', prefix='1 2 3'
);
"""


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def request_json(url: str, params: Optional[dict] = None, timeout: int = 90) -> dict:
    if params:
        url += ("&" if "?" in url else "?") + urlencode(params)
    req = Request(url, headers={"User-Agent": UA, "Accept-Language": "en-US,en;q=0.8"})
    with urlopen(req, timeout=timeout) as response:
        return json.load(response)


def download(url: str, path: Path) -> str:
    if path.exists() and path.stat().st_size:
        return url
    path.parent.mkdir(parents=True, exist_ok=True)
    req = Request(url, headers={"User-Agent": UA})
    with urlopen(req, timeout=180) as response, path.open("wb") as out:
        final_url = response.geturl()
        shutil.copyfileobj(response, out)
    return final_url


def run(*args: str) -> None:
    print("$", " ".join(args), flush=True)
    subprocess.run(args, check=True, cwd=ROOT)


def json_text(value) -> Optional[str]:
    if value is None:
        return None
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
            return json.dumps(parsed, ensure_ascii=False, separators=(",", ":"))
        except ValueError:
            return value
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def val(value) -> Optional[str]:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def first(value) -> Optional[str]:
    if isinstance(value, list):
        for item in value:
            if item is not None and str(item).strip():
                return str(item).strip()
        return None
    return val(value)


def make_entity_key(name: str, address: Optional[str], lon: Optional[float], lat: Optional[float]) -> str:
    norm = re.sub(r"[^a-z0-9]+", " ", name.casefold()).strip()
    addr = re.sub(r"[^a-z0-9]+", " ", (address or "").casefold()).strip()
    point = "" if lon is None or lat is None else f"{lon:.4f},{lat:.4f}"
    return hashlib.sha1(f"{norm}|{addr}|{point}".encode("utf-8")).hexdigest()


class PlainHTML(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []

    def handle_data(self, data):
        if data.strip():
            self.parts.append(data.strip())


def plain_html(raw: Optional[str]) -> Optional[str]:
    if not raw:
        return None
    parser = PlainHTML()
    parser.feed(raw)
    text = html.unescape(" ".join(parser.parts))
    return text or None


def create_db(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        path.unlink()
    db = sqlite3.connect(path)
    db.executescript(SCHEMA)
    return db


def gzip_file(path: Path) -> Tuple[str, int]:
    target = path.with_suffix(path.suffix + ".gz")
    with path.open("rb") as src, target.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, compresslevel=6, mtime=0) as dst:
            shutil.copyfileobj(src, dst, length=1024 * 1024)
    return target.name, target.stat().st_size


INSERT = """INSERT INTO lugares (
  source_id,entity_key,source,license,attribution,source_url,source_updated,captured_at,
  name,aliases_json,brand,kind,category,subcategory,description,lon,lat,address,locality,
  region,postal_code,phone,phones_json,email,website,websites_json,socials_json,opening_hours,
  payment_json,services_json,operating_status,confidence,photos_json,details_json
) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"""


def insert_place(db: sqlite3.Connection, row: dict) -> int:
    name = val(row.get("name"))
    if not name:
        return 0
    values = (
        str(row["source_id"]), row["entity_key"], row["source"], row.get("license"),
        row["attribution"], row.get("source_url"), row.get("source_updated"), row["captured_at"],
        name, row.get("aliases_json"), row.get("brand"), row["kind"], row.get("category"),
        row.get("subcategory"), row.get("description"), row.get("lon"), row.get("lat"),
        row.get("address"), row.get("locality"), row.get("region"), row.get("postal_code"),
        row.get("phone"), row.get("phones_json"), row.get("email"), row.get("website"),
        row.get("websites_json"), row.get("socials_json"), row.get("opening_hours"),
        row.get("payment_json"), row.get("services_json"), row.get("operating_status"),
        row.get("confidence"), row.get("photos_json"), row.get("details_json") or "{}",
    )
    cur = db.execute(INSERT, values)
    rowid = cur.lastrowid
    aliases = row.get("aliases") or []
    db.execute("INSERT INTO lugares_fts(rowid,name,brand,aliases,address,locality,category,description) VALUES(?,?,?,?,?,?,?,?)",
               (rowid, name, row.get("brand") or "", " ".join(map(str, aliases)),
                row.get("address") or "", row.get("locality") or "", row.get("category") or "",
                row.get("description") or ""))
    return rowid


def profile_database(db: sqlite3.Connection) -> dict:
    total = db.execute("SELECT COUNT(*) FROM lugares").fetchone()[0]
    optional = ("phone", "email", "website", "opening_hours", "description",
                "payment_json", "services_json", "photos_json")
    counts = {field: db.execute(
        "SELECT COUNT(*) FROM lugares WHERE " + field + " IS NOT NULL AND " + field + " != ''"
    ).fetchone()[0] for field in optional}
    return {"rows": total, "fields_populated": counts}


def load_counties() -> Tuple[list, object, Tuple[float, float, float, float]]:
    path = CACHE / "counties.geojson"
    if not path.exists():
        download(COUNTY_URL, path)
    fc = json.loads(path.read_text(encoding="utf-8"))
    wanted = {"12011", "12086", "12087"}
    features = [f for f in fc["features"] if f["properties"].get("GEOID") in wanted]
    if len(features) != 3:
        raise RuntimeError(f"El Censo devolvió {len(features)} de los 3 condados esperados")
    union = unary_union([shape(f["geometry"]) for f in features])
    return features, union, union.bounds


def build_overture(bounds: Tuple[float, float, float, float], county_union, captured: str) -> dict:
    path = OUT / "overture.sqlite"
    cache = CACHE / "overture.jsonl"
    if not cache.exists():
        left, bottom, right, top = bounds
        con = duckdb.connect()
        con.execute("INSTALL httpfs")
        con.execute("LOAD httpfs")
        con.execute("SET s3_region='us-west-2'")
        sql = f"""
            SELECT id::VARCHAR AS source_id,
                   names.primary AS primary_name,
                   to_json(names) AS names_json,
                   taxonomy.primary AS category,
                   to_json(taxonomy) AS taxonomy_json,
                   basic_category,
                   operating_status,
                   confidence,
                   to_json(brand) AS brand_json,
                   to_json(addresses) AS addresses_json,
                   to_json(phones) AS phones_json,
                   to_json(websites) AS websites_json,
                   to_json(socials) AS socials_json,
                   to_json(emails) AS emails_json,
                   to_json(sources) AS sources_json,
                   (bbox.xmin + bbox.xmax) / 2 AS lon,
                   (bbox.ymin + bbox.ymax) / 2 AS lat,
                   bbox.xmin AS west, bbox.ymin AS south,
                   bbox.xmax AS east, bbox.ymax AS north
            FROM read_parquet('{OVERTURE_GLOB}')
            WHERE bbox.xmax >= {left} AND bbox.xmin <= {right}
              AND bbox.ymax >= {bottom} AND bbox.ymin <= {top}
        """
        cur = con.execute(sql)
        columns = [c[0] for c in cur.description]
        with cache.open("w", encoding="utf-8") as out:
            while True:
                rows = cur.fetchmany(5000)
                if not rows:
                    break
                for tup in rows:
                    out.write(json.dumps(dict(zip(columns, tup)), ensure_ascii=False, default=str) + "\n")
        con.close()

    db = create_db(path)
    count = 0
    for line in cache.open(encoding="utf-8"):
        rec = json.loads(line)
        names = json.loads(rec.get("names_json") or "{}")
        addresses = json.loads(rec.get("addresses_json") or "[]") or []
        addr = addresses[0] if addresses else {}
        brand_obj = json.loads(rec.get("brand_json") or "{}")
        brand = first((brand_obj.get("names") or {}).get("primary")) if isinstance(brand_obj, dict) else None
        phones = json.loads(rec.get("phones_json") or "null")
        websites = json.loads(rec.get("websites_json") or "null")
        socials = json.loads(rec.get("socials_json") or "null")
        emails = json.loads(rec.get("emails_json") or "null")
        sources = json.loads(rec.get("sources_json") or "null")
        licenses = sorted({s.get("license") for s in (sources or []) if isinstance(s, dict) and s.get("license")})
        name = rec.get("primary_name") or names.get("primary")
        if not name:
            continue
        lat, lon = rec.get("lat"), rec.get("lon")
        if lon is None or lat is None or not county_union.covers(Point(lon, lat)):
            continue
        address = addr.get("freeform") if isinstance(addr, dict) else None
        aliases = names.get("common") or []
        if isinstance(aliases, str):
            aliases = [aliases]
        provenance = []
        for source in sources or []:
            if isinstance(source, dict):
                provenance.append({k: source.get(k) for k in
                                   ("provider", "dataset", "license", "record_id", "update_time", "property")
                                   if source.get(k) is not None})
        tax = json.loads(rec.get("taxonomy_json") or "{}")
        details = {"taxonomy_hierarchy": tax.get("hierarchy", []),
                   "sources": provenance,
                   "basic_category": rec.get("basic_category")}
        row = {
            "source_id": rec["source_id"], "entity_key": make_entity_key(name, address, lon, lat),
            "source": "overture", "license": json_text(licenses),
            "attribution": "Overture Maps Foundation; source-specific licenses in details_json.sources",
            "source_url": "https://docs.overturemaps.org/guides/places/",
            "source_updated": OVERTURE_RELEASE, "captured_at": captured,
            "name": name, "aliases": aliases, "aliases_json": json_text(aliases), "brand": brand,
            "kind": "place", "category": rec.get("category") or rec.get("basic_category"),
            "subcategory": rec.get("basic_category"), "description": None,
            "lon": lon, "lat": lat, "address": address,
            "locality": addr.get("locality") if isinstance(addr, dict) else None,
            "region": addr.get("region") if isinstance(addr, dict) else None,
            "postal_code": addr.get("postcode") if isinstance(addr, dict) else None,
            "phone": first(phones), "phones_json": json_text(phones) if len(phones or []) > 1 else None,
            "email": first(emails),
            "website": first(websites), "websites_json": json_text(websites) if len(websites or []) > 1 else None,
            "socials_json": json_text(socials), "opening_hours": None,
            "payment_json": None, "services_json": None,
            "operating_status": rec.get("operating_status"), "confidence": rec.get("confidence"),
            "photos_json": None, "details_json": json_text(details),
        }
        insert_place(db, row)
        count += 1
        if count % 10000 == 0:
            db.commit()
            print(f"Overture: {count:,}", flush=True)
    db.commit()
    profile = profile_database(db)
    db.execute("ANALYZE")
    db.close()
    return {"file": path.name, "rows": count, "bytes": path.stat().st_size, **profile,
            "license": "Per-record source licenses preserved in details_json.sources"}


def osm_extract(bounds: Tuple[float, float, float, float]) -> Path:
    if not PBF.exists():
        final_url = download(PBF_URL, PBF)
        (CACHE / "pbf-final-url.txt").write_text(final_url + "\n", encoding="utf-8")
    left, bottom, right, top = bounds
    ext = CACHE / "places-extract.pbf"
    selected = CACHE / "places-selected.pbf"
    seq = CACHE / "places.geojsonseq"
    if not seq.exists():
        run("osmium", "extract", f"--bbox={left},{bottom},{right},{top}",
            "--strategy=complete_ways", "--set-bounds", "--overwrite", "-o", str(ext), str(PBF))
        expressions = [f"nwr/{key}=*" for key in
                       ("shop", "amenity", "office", "craft", "tourism", "healthcare", "leisure")]
        run("osmium", "tags-filter", "--overwrite", "-o", str(selected), str(ext), *expressions)
        run("osmium", "export", "--overwrite", "--add-unique-id=type_id", "-o", str(seq), str(selected))
    return seq


def reusable_license(label: Optional[str]) -> bool:
    if not label:
        return False
    s = re.sub(r"\s+", " ", label.strip().upper())
    if "PUBLIC DOMAIN" in s or s == "CC0" or "CC0 1.0" in s:
        return True
    if re.search(r"CC BY(?:-SA)?(?:\s|$)", s):
        return "-NC" not in s and "-ND" not in s
    return False


def commons_metadata(titles: List[str]) -> Dict[str, dict]:
    result = {}
    unique = sorted(set(titles))
    for i in range(0, len(unique), 30):
        batch = unique[i:i + 30]
        try:
            data = request_json(COMMONS_API, {
                "action": "query", "titles": "|".join(batch), "prop": "imageinfo",
                "iiprop": "url|extmetadata", "iiurlwidth": "900", "format": "json",
            })
            for page in data.get("query", {}).get("pages", {}).values():
                ii = (page.get("imageinfo") or [{}])[0]
                meta = ii.get("extmetadata") or {}
                lic = plain_html((meta.get("LicenseShortName") or {}).get("value"))
                if not reusable_license(lic):
                    continue
                title = page.get("title")
                result[title] = {
                    "url": ii.get("thumburl") or ii.get("url"),
                    "page_url": ii.get("descriptionurl"),
                    "title": title,
                    "author": plain_html((meta.get("Artist") or {}).get("value")),
                    "credit": plain_html((meta.get("Credit") or {}).get("value")),
                    "attribution": plain_html((meta.get("Attribution") or {}).get("value")),
                    "license": lic,
                    "license_url": (meta.get("LicenseUrl") or {}).get("value"),
                    "description": plain_html((meta.get("ImageDescription") or {}).get("value")),
                    "source": "Wikimedia Commons",
                }
        except Exception as exc:
            print(f"Commons metadata batch skipped: {exc}", flush=True)
        time.sleep(0.15)
    return result


def build_osm(bounds, county_union, captured: str, pbf_url: str) -> dict:
    path = OUT / "openstreetmap.sqlite"
    seq = osm_extract(bounds)
    records = []
    commons_titles = []
    region_box = box(*bounds)
    with seq.open(encoding="utf-8") as src:
        for line in src:
            feature = json.loads(line.lstrip("\x1e"))
            tags = feature.get("properties") or {}
            if not any(tags.get(k) for k in ("shop", "amenity", "office", "craft", "tourism", "healthcare", "leisure")):
                continue
            name = val(tags.get("name") or tags.get("brand"))
            if not name:
                continue
            geometry = feature.get("geometry")
            if not geometry:
                continue
            geom = shape(geometry)
            if not geom.is_valid:
                geom = geom.buffer(0)
            if not geom.intersects(region_box):
                continue
            inside = geom.intersection(county_union)
            if inside.is_empty:
                continue
            point = inside if inside.geom_type == "Point" else inside.representative_point()
            lon, lat = point.x, point.y
            category = next((val(tags.get(k)) for k in ("shop", "amenity", "office", "craft", "tourism", "healthcare", "leisure") if val(tags.get(k))), None)
            phone = val(tags.get("contact:phone") or tags.get("phone"))
            website = val(tags.get("contact:website") or tags.get("website") or tags.get("contact:URL"))
            email = val(tags.get("contact:email") or tags.get("email"))
            socials = {k: v for k, v in tags.items()
                       if k in {"facebook", "instagram", "twitter", "x", "tiktok", "youtube", "mastodon"}
                       or (k.startswith("contact:") and k.split(":", 1)[1] in
                           {"facebook", "instagram", "twitter", "x", "tiktok", "youtube", "mastodon"})}
            hours = val(tags.get("opening_hours"))
            description = val(tags.get("description:en") or tags.get("description") or tags.get("description:es"))
            payment = {k: v for k, v in tags.items() if k.startswith("payment:")}
            services = {k: v for k, v in tags.items() if k.startswith(("service:", "delivery:", "wheelchair:", "diet:"))
                        or k in {"takeaway", "delivery", "dine_in", "drive_through", "reservation", "wheelchair", "internet_access", "outdoor_seating"}}
            alt = [tags[k] for k in ("alt_name", "official_name", "short_name", "name:en", "name:es") if val(tags.get(k))]
            commons = val(tags.get("wikimedia_commons"))
            commons_title = commons if commons and commons.startswith("File:") else ("File:" + commons if commons and ":" not in commons else None)
            if commons_title:
                commons_titles.append(commons_title)
            direct_image = val(tags.get("image"))
            source_id = str(feature.get("id", ""))
            records.append({
                "source_id": source_id, "name": name, "brand": val(tags.get("brand")),
                "category": category, "subcategory": next((val(tags.get(k)) for k in ("cuisine", "clothes", "healthcare:speciality") if val(tags.get(k))), None),
                "description": description, "lon": lon, "lat": lat,
                "address": " ".join(filter(None, [val(tags.get("addr:housenumber")), val(tags.get("addr:street"))])) or None,
                "locality": val(tags.get("addr:city")), "postal_code": val(tags.get("addr:postcode")),
                "phone": phone, "email": email, "website": website, "opening_hours": hours,
                "socials": socials,
                "payment": payment, "services": services, "aliases": alt,
                "commons_title": commons_title, "direct_image": direct_image, "tags": tags,
            })
    photos = commons_metadata(commons_titles)
    db = create_db(path)
    attached_photos = 0
    for rec in records:
        photo = photos.get(rec["commons_title"]) if rec.get("commons_title") else None
        if photo:
            attached_photos += 1
        photo_list = [photo] if photo else None
        details = {"tags": rec["tags"], "image_reference_unverified": rec.get("direct_image")}
        row = {
            "source_id": rec["source_id"], "entity_key": make_entity_key(rec["name"], rec["address"], rec["lon"], rec["lat"]),
            "source": "openstreetmap", "license": "ODbL-1.0",
            "attribution": "© OpenStreetMap contributors",
            "source_url": "https://www.openstreetmap.org/copyright",
            "source_updated": None, "captured_at": captured,
            "name": rec["name"], "aliases": rec["aliases"], "aliases_json": json_text(rec["aliases"]),
            "brand": rec["brand"], "kind": "business" if "shop" in rec["tags"] else "poi",
            "category": rec["category"], "subcategory": rec["subcategory"], "description": rec["description"],
            "lon": rec["lon"], "lat": rec["lat"], "address": rec["address"],
            "locality": rec["locality"], "region": "FL", "postal_code": rec["postal_code"],
            "phone": rec["phone"], "phones_json": json_text([rec["phone"]] if rec["phone"] else None),
            "email": rec["email"], "website": rec["website"],
            "websites_json": json_text([rec["website"]] if rec["website"] else None),
            "socials_json": json_text(rec["socials"]) if rec["socials"] else None,
            "opening_hours": rec["opening_hours"],
            "payment_json": json_text(rec["payment"]) if rec["payment"] else None,
            "services_json": json_text(rec["services"]) if rec["services"] else None,
            "operating_status": val(rec["tags"].get("disused")) or val(rec["tags"].get("abandoned")),
            "confidence": None, "photos_json": json_text(photo_list), "details_json": json_text(details),
        }
        insert_place(db, row)
    db.commit()
    profile = profile_database(db)
    db.execute("ANALYZE")
    db.close()
    info = subprocess.check_output(["osmium", "fileinfo", "-e", str(PBF)], text=True)
    match = re.search(r"osmosis_replication_timestamp=([^\s]+)", info)
    snapshot = match.group(1) if match else None
    return {"file": path.name, "rows": len(records), "bytes": path.stat().st_size, **profile,
            "photos_with_verified_reusable_license": attached_photos, "commons_candidates": len(set(commons_titles)),
            "pbf_url": pbf_url, "pbf_snapshot": snapshot,
            "license": "ODbL-1.0; visible attribution required"}


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    captured = now_iso()
    counties, county_union, bounds = load_counties()
    # Record the source URL after redirects (Geofabrik publishes dated daily snapshots).
    final_pbf_url = PBF_URL
    if not PBF.exists():
        final_pbf_url = download(PBF_URL, PBF)
    elif (CACHE / "pbf-final-url.txt").exists():
        final_pbf_url = (CACHE / "pbf-final-url.txt").read_text().strip()

    results = {
        "schema_version": 1,
        "captured_at": captured,
        "coverage": {"counties": [f["properties"]["NAME"] for f in counties], "bounds": list(bounds)},
        "sources": {
            "overture": {"release": OVERTURE_RELEASE, "url": "https://docs.overturemaps.org/guides/places/"},
            "openstreetmap": {"url": final_pbf_url, "attribution": "© OpenStreetMap contributors", "license": "ODbL-1.0"},
            "images": {"source": "Wikimedia Commons references explicitly attached to OSM features", "policy": "Only Public Domain, CC0, CC BY, CC BY-SA; preserve creator, credit, page and license links"},
        },
        "databases": {},
        "notes": [
            "Each provider is kept in its own SQLite file to preserve provenance and license boundaries.",
            "Phone, website, hours, descriptions, payment/services and images remain empty when the source does not provide them.",
            "The Miami-Dade LocalBusinessTax layer was excluded after its official metadata marked it restricted for internal use and its phone information non-public.",
            "Overture Places does not provide per-place photos or opening hours in its current schema; OSM tags and Commons references may provide some of those fields.",
        ],
    }
    results["databases"]["overture"] = build_overture(bounds, county_union, captured)
    results["databases"]["openstreetmap"] = build_osm(bounds, county_union, captured, final_pbf_url)
    results["sources"]["openstreetmap"]["snapshot"] = results["databases"]["openstreetmap"]["pbf_snapshot"]
    for key in ("overture", "openstreetmap"):
        path = OUT / results["databases"][key]["file"]
        compressed_name, compressed_size = gzip_file(path)
        results["databases"][key]["compressed_file"] = compressed_name
        results["databases"][key]["compressed_bytes"] = compressed_size
        results["databases"][key]["object_key"] = "places/v1/" + compressed_name
    manifest_path = OUT / "manifest.json"
    manifest_path.write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(results, ensure_ascii=False, indent=2), flush=True)


if __name__ == "__main__":
    main()
