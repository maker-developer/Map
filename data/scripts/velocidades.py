#!/usr/bin/env python3
"""Descarga y valida límites de velocidad publicados por FDOT para el sur de Florida."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "data" / ".cache" / "limites-velocidad.geojson"
MANIFEST = ROOT / "public" / "data" / "manifest.json"
RELEASE_MANIFEST = ROOT / "public" / "data" / "limites-velocidad-manifest.json"
SERVICE = "https://services1.arcgis.com/O1JpcwDW8sjYuddV/ArcGIS/rest/services/Maximum_Speed_Limit_TDA/FeatureServer/0"
PUBLIC_URL = "https://pub-031a310ad68042d59e4273a0b01a7dc1.r2.dev/limites-velocidad/v1/limites-velocidad.pmtiles"
COUNTIES = ("Miami-Dade", "Broward", "Monroe")
FIELDS = "FID,ROADWAY,ROAD_SIDE,OFFSET_DIR,COUNTY,BEGIN_POST,END_POST,SPEED"
PAGE_SIZE = 1500
LEGAL_MPH = {5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70}


def request(url, params):
    query = url + "?" + urlencode({**params, "f": "json"})
    for attempt in range(3):
        try:
            req = Request(query, headers={"User-Agent": "Map South Florida speed data/1.0"})
            with urlopen(req, timeout=60) as response:
                result = json.load(response)
            if "error" in result:
                raise RuntimeError(f"FDOT ArcGIS: {result['error']}")
            return result
        except (OSError, ValueError, RuntimeError, HTTPError, URLError):
            if attempt == 2:
                raise
            time.sleep(attempt + 1)


def as_number(value):
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def clean_text(value):
    value = value.strip() if isinstance(value, str) else value
    return value or None


def feature(row):
    attrs = row["attributes"]
    speed = as_number(attrs.get("SPEED"))
    if speed is None or int(speed) != speed or int(speed) not in LEGAL_MPH:
        return None
    paths = (row.get("geometry") or {}).get("paths") or []
    if not paths or any(len(path) < 2 for path in paths):
        raise RuntimeError(f"FDOT FID {attrs.get('FID')} no contiene geometría")
    return {
        "type": "Feature",
        "geometry": {"type": "MultiLineString", "coordinates": paths},
        "properties": {
            "fid": attrs.get("FID"),
            "limite_mph": int(speed),
            "condado": attrs.get("COUNTY"),
            "roadway": (attrs.get("ROADWAY") or "").strip(),
            "lado": clean_text(attrs.get("ROAD_SIDE")),
            "direccion_offset": clean_text(attrs.get("OFFSET_DIR")),
            "inicio_milla": as_number(attrs.get("BEGIN_POST")),
            "fin_milla": as_number(attrs.get("END_POST")),
            "fuente": "FDOT RCI MAXSPEED",
        },
    }


def download():
    metadata = request(SERVICE, {})
    edit = metadata.get("editingInfo", {}).get("dataLastEditDate")
    service_updated = time.strftime("%Y-%m-%d", time.gmtime(edit / 1000)) if edit else None
    rows, report = [], {}
    for county in COUNTIES:
        where = f"COUNTY='{county}'"
        expected = request(SERVICE + "/query", {"where": where, "returnCountOnly": "true"}).get("count")
        if expected is None:
            raise RuntimeError(f"FDOT no informó el total de tramos para {county}")
        features = []
        for offset in range(0, expected, PAGE_SIZE):
            page = request(SERVICE + "/query", {
                "where": where,
                "outFields": FIELDS,
                "returnGeometry": "true",
                "outSR": 4326,
                "geometryPrecision": 6,
                "orderByFields": "FID ASC",
                "resultOffset": offset,
                "resultRecordCount": PAGE_SIZE,
            }).get("features", [])
            features.extend(page)
        if len(features) != expected:
            raise RuntimeError(f"{county}: FDOT reportó {expected:,} tramos; se recibieron {len(features):,}")
        converted = [feature(row) for row in features]
        missing = sum(row is None for row in converted)
        converted = [row for row in converted if row]
        if missing:
            raise RuntimeError(f"{county}: {missing} tramos sin velocidad válida; no se publicará una capa incompleta")
        if any(row["properties"]["condado"] != county for row in converted):
            raise RuntimeError(f"{county}: la respuesta contiene registros de otro condado")
        rows.extend(converted)
        by_speed = {}
        for row in converted:
            mph = str(row["properties"]["limite_mph"])
            by_speed[mph] = by_speed.get(mph, 0) + 1
        report[county] = {"count": len(converted), "byMph": dict(sorted(by_speed.items(), key=lambda x: int(x[0])))}

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    staging = OUTPUT.with_suffix(".tmp")
    staging.write_text(json.dumps({"type": "FeatureCollection", "features": rows},
                                  ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    staging.replace(OUTPUT)
    return rows, report, service_updated


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tippecanoe", default="tippecanoe", help="Ruta al ejecutable Tippecanoe.")
    args = parser.parse_args()
    rows, counties, service_updated = download()
    archive = ROOT / "public" / "data" / "limites-velocidad.pmtiles"
    staging = archive.with_name("limites-velocidad-temporal.pmtiles")
    subprocess.run([args.tippecanoe, "-f", "-q", "-o", str(staging), "-Z7", "-z16",
                    "-l", "limites-velocidad", str(OUTPUT)], check=True)
    staging.replace(archive)
    metadata = {
        "source": "Florida Department of Transportation, Roadway Characteristics Inventory (RCI), Feature 311 MAXSPEED",
        "sourceUrl": SERVICE,
        "sourceItem": "https://www.arcgis.com/home/item.html?id=4a61f17ab4784202ae10d7d5fb3bf9de",
        "url": PUBLIC_URL,
        "attribution": "Fuente: Florida Department of Transportation (FDOT), RCI Feature 311 MAXSPEED",
        "terms": "FDOT GIS is provided as is, without warranties; published inventory may not reflect current conditions.",
        "termsUrl": "https://www.fdot.gov/statistics/gis/default.shtm",
        "sourceUpdated": service_updated,
        "coverageScope": "FDOT designated State Highway System roads and HPMS samples; not all local streets",
        "captured": time.strftime("%Y-%m-%d", time.gmtime()),
        "count": len(rows),
        "counties": counties,
        "verifiedSpeedsOnly": True,
        "units": "mph",
        "file": archive.name,
        "bytes": archive.stat().st_size,
        "minzoom": 7,
        "maxzoom": 16,
        "vectorLayer": "limites-velocidad",
        "properties": ["limite_mph", "condado", "roadway", "lado", "direccion_offset",
                       "inicio_milla", "fin_milla", "fuente"],
    }
    if MANIFEST.exists():
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    else:
        manifest = {"layers": {}}
    manifest.setdefault("layers", {})["limites-velocidad"] = metadata
    staging = MANIFEST.with_suffix(".tmp")
    staging.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    staging.replace(MANIFEST)
    RELEASE_MANIFEST.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"FDOT RCI: {len(rows):,} tramos verificados; datos del servicio {service_updated}")
    for county, item in counties.items():
        print(f"  {county}: {item['count']:,} | " + ", ".join(f"{mph} mph: {count:,}" for mph, count in item["byMph"].items()))
    print(f"PMTiles: {archive.stat().st_size:,} bytes; capa limites-velocidad, zoom 7–16")


if __name__ == "__main__":
    main()
