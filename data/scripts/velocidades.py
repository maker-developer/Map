#!/usr/bin/env python3
"""Descarga y valida límites de velocidad publicados por FDOT para el sur de Florida."""
import argparse
import json
import math
from pathlib import Path
import re
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
LOCAL_NAME_SERVICE = "https://services1.arcgis.com/O1JpcwDW8sjYuddV/ArcGIS/rest/services/Roadways_With_Local_Name_TDA/FeatureServer/0"
PUBLIC_URL = "https://pub-031a310ad68042d59e4273a0b01a7dc1.r2.dev/limites-velocidad/v1/limites-velocidad.pmtiles"
COUNTIES = ("Miami-Dade", "Broward", "Monroe")
FIELDS = "FID,ROADWAY,ROAD_SIDE,OFFSET_DIR,COUNTY,BEGIN_POST,END_POST,SPEED"
PAGE_SIZE = 1500
LEGAL_MPH = {5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70}
MATCH_MAX_METERS = 5
MATCH_MIN_COVERAGE = 0.95
MATCH_MAX_ANGLE_DEGREES = 15


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


def _road_aliases(value):
    """Normaliza abreviaturas del RCI y del Street Network para unir nombres exactos."""
    replacements = {
        "AVENUE": "AVE", "AV": "AVE", "STREET": "ST", "STR": "ST",
        "BOULEVARD": "BLVD", "HIGHWAY": "HWY", "HWAY": "HWY", "ROAD": "RD",
        "DRIVE": "DR", "COURT": "CT", "TERRACE": "TER", "PARKWAY": "PKWY",
        "EXPRESSWAY": "EXPY", "CAUSEWAY": "CSWY", "TRAIL": "TRL",
        "PLACE": "PL", "CIRCLE": "CIR", "LANE": "LN", "SQUARE": "SQ",
        "NORTH": "N", "SOUTH": "S", "EAST": "E", "WEST": "W",
    }
    aliases = set()
    for alternative in re.split(r"[/&]", value or ""):
        text = re.sub(r"(\d+)(ST|ND|RD|TH)\b", r"\1", alternative.upper())
        tokens = re.sub(r"[^A-Z0-9 ]+", " ", text).split()
        if tokens:
            aliases.add(" ".join(replacements.get(token, token) for token in tokens))
    return aliases


def _fetch_local_names(speed_rows):
    """Nombres FDOT por ROADWAY y millaje; descarta coincidencias por geometría sola."""
    by_county = {}
    for row in speed_rows:
        props = row["properties"]
        by_county.setdefault(props["condado"], set()).add(props["roadway"])
    result = []
    for county, roadways in by_county.items():
        identifiers = sorted(roadways)
        for offset in range(0, len(identifiers), 50):
            values = ",".join("'" + value.replace("'", "''") + "'" for value in identifiers[offset:offset + 50])
            where = f"COUNTY='{county}' AND ROADWAY IN ({values})"
            expected = request(LOCAL_NAME_SERVICE + "/query", {
                "where": where, "returnCountOnly": "true",
            }).get("count")
            if expected is None:
                raise RuntimeError(f"FDOT no informó los nombres asociados a ROADWAY en {county}")
            rows = []
            for page in range(0, expected, PAGE_SIZE):
                rows.extend(request(LOCAL_NAME_SERVICE + "/query", {
                    "where": where,
                    "outFields": "ROADWAY,NAME,BEGIN_POST,END_POST,COUNTY",
                    "returnGeometry": "false",
                    "orderByFields": "ROADWAY ASC,BEGIN_POST ASC",
                    "resultOffset": page,
                    "resultRecordCount": PAGE_SIZE,
                }).get("features", []))
            if len(rows) != expected:
                raise RuntimeError(f"FDOT no devolvió todos los nombres de carretera de {county}")
            result.extend(row["attributes"] for row in rows)
    return result


def enrich_base_ndjson(path, speed_rows=None):
    """Añade `vmax` a `calles` solo con coincidencia de nombre RCI, millaje y geometría."""
    from pyproj import Transformer
    from shapely.geometry import shape
    from shapely.ops import nearest_points, transform
    from shapely.strtree import STRtree

    if speed_rows is None:
        speed_rows, _, _ = download()
    local_names = _fetch_local_names(speed_rows)
    names_by_route = {}
    for row in local_names:
        names_by_route.setdefault((row["COUNTY"], row["ROADWAY"]), []).append(row)

    base_rows = [json.loads(line) for line in Path(path).read_text(encoding="utf-8").splitlines() if line]
    street_rows, street_geometries = [], []
    project = Transformer.from_crs("EPSG:4326", "EPSG:26917", always_xy=True).transform
    for row in base_rows:
        if row.get("tippecanoe", {}).get("layer") != "calles":
            continue
        props = row.setdefault("properties", {})
        props.pop("vmax", None)
        geom = row.get("geometry")
        if geom:
            street_rows.append(row)
            street_geometries.append(transform(project, shape(geom)))
    if not street_geometries:
        raise RuntimeError("No se encontró la capa calles en base.ndjson")
    index = STRtree(street_geometries)
    assignments = {}
    matched_fids = set()
    matched_by_county = {county: set() for county in COUNTIES}

    def tangent(line, point):
        measure = line.project(point)
        before = line.interpolate(max(0, measure - 5))
        after = line.interpolate(min(line.length, measure + 5))
        if before.distance(after) < 0.2:
            before = line.interpolate(max(0, measure - 20))
            after = line.interpolate(min(line.length, measure + 20))
        return math.atan2(after.y - before.y, after.x - before.x)

    for speed in speed_rows:
        props = speed["properties"]
        route_names = names_by_route.get((props["condado"], props["roadway"]), [])
        speed_start, speed_end = props["inicio_milla"], props["fin_milla"]
        aliases = set()
        for name_row in route_names:
            if name_row["END_POST"] >= speed_start and name_row["BEGIN_POST"] <= speed_end:
                aliases.update(_road_aliases(name_row["NAME"]))
        if not aliases:
            continue
        geometry = transform(project, shape(speed["geometry"]))
        nearby = index.query(geometry.buffer(MATCH_MAX_METERS))
        matched_this = False
        for raw_index in nearby:
            i = int(raw_index)
            street = street_rows[i]
            road = street_geometries[i]
            if road.length < 12 or not (_road_aliases(street.get("properties", {}).get("name")) & aliases):
                continue
            distance = road.distance(geometry)
            if (distance > MATCH_MAX_METERS or
                    road.intersection(geometry.buffer(MATCH_MAX_METERS)).length / road.length < MATCH_MIN_COVERAGE):
                continue
            road_point, speed_point = nearest_points(road, geometry)
            angle = abs((tangent(road, road_point) - tangent(geometry, speed_point) + math.pi / 2) % math.pi - math.pi / 2)
            if angle > math.radians(MATCH_MAX_ANGLE_DEGREES):
                continue
            assignments.setdefault(i, set()).add(props["limite_mph"])
            matched_this = True
        if matched_this:
            matched_fids.add(props["fid"])
            matched_by_county[props["condado"]].add(props["fid"])

    for i, speeds in assignments.items():
        # Los tramos de distinto sentido pueden diferir; el contrato de navegación
        # pide usar el menor cuando no se parte la geometría por sentido.
        street_rows[i]["properties"]["vmax"] = min(speeds)

    target = Path(path)
    staging = target.with_suffix(".tmp")
    with staging.open("w", encoding="utf-8") as output:
        for row in base_rows:
            output.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
    staging.replace(target)
    distribution = {}
    for row in street_rows:
        vmax = row["properties"].get("vmax")
        if vmax is not None:
            distribution[str(vmax)] = distribution.get(str(vmax), 0) + 1
    service_date = time.strftime(
        "%Y-%m-%d", time.gmtime(request(SERVICE, {}).get("editingInfo", {}).get("dataLastEditDate", 0) / 1000)
    )
    return {
        "source": "FDOT RCI Feature 311 MAXSPEED; ROADWAY/POST range joined to LOCALNAM and Street Network by name and geometry",
        "sourceUrl": SERVICE,
        "sourceItem": "https://www.arcgis.com/home/item.html?id=4a61f17ab4784202ae10d7d5fb3bf9de",
        "sourceUpdated": service_date,
        "attribution": "Fuente: Florida Department of Transportation (FDOT), RCI Feature 311 MAXSPEED",
        "terms": "FDOT GIS is provided as is, without warranties; published inventory may not reflect current conditions.",
        "termsUrl": "https://www.fdot.gov/statistics/gis/default.shtm",
        "coverageScope": "FDOT designated State Highway System roads and HPMS samples; not all local streets",
        "file": "base.pmtiles",
        "vectorLayer": "calles",
        "property": "vmax",
        "units": "mph",
        "count": len(speed_rows),
        "speedRecordsMatched": len(matched_fids),
        "streetFeaturesWithVmax": len(assignments),
        "streetFeatures": len(street_rows),
        "matching": {"maxDistanceM": MATCH_MAX_METERS, "minStreetCoverage": MATCH_MIN_COVERAGE,
                     "maxAngleDegrees": MATCH_MAX_ANGLE_DEGREES, "requiresRoadwayAndMileRangeName": True},
        "byCounty": {county: len(matched_by_county[county]) for county in COUNTIES},
        "byMph": dict(sorted(distribution.items(), key=lambda item: int(item[0]))),
        "onlyExplicitValues": True,
        "url": "https://pub-031a310ad68042d59e4273a0b01a7dc1.r2.dev/v6/base.pmtiles",
        "sidecarUrl": PUBLIC_URL,
    }


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
