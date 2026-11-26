#!/usr/bin/env python3
"""Extrae geometrías públicas para generar los datos locales de Map."""
import argparse
import concurrent.futures
import json
from pathlib import Path
import re
import subprocess
import time
from urllib.parse import urlencode
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
DATOS = ROOT / "public" / "data"
HOST = "https://services.arcgis.com/8Pc9XBTAsYuxx9Ny/arcgis/rest/services/"
COUNTY = "https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/State_County/MapServer/1"
PAGE = 2000
BUILDING_SERVICE = "BuildingFootprintUBIDFolio_gdb"
BUILDING_FIELDS = "BLDG_HEIGHT,ADDRESS"
ZONES = {
    "brickell": {"name": "Downtown y Brickell", "bounds": [-80.217, 25.747, -80.175, 25.801],
                 "center": [-80.196, 25.770], "zoom": 15.45, "bearing": -20},
    "miami-beach": {"name": "Miami Beach", "bounds": [-80.158, 25.756, -80.115, 25.813],
                    "center": [-80.137, 25.783], "zoom": 15.25, "bearing": -25},
    "miami-lakes": {"name": "Miami Lakes", "bounds": [-80.348, 25.879, -80.280, 25.949],
                    "center": [-80.320, 25.914], "zoom": 14.85, "bearing": -21},
}


def service(name):
    return f"{HOST}{name}/FeatureServer/0"


def request(url, **params):
    query = url + "?" + urlencode(params)
    for attempt in range(3):
        try:
            req = Request(query, headers={"User-Agent": "Map geographic-data prototype/1.0"})
            with urlopen(req, timeout=45) as response:
                result = json.load(response)
            if "error" in result:
                raise RuntimeError(f"{url}: {result['error']}")
            return result
        except (OSError, ValueError, RuntimeError):
            if attempt == 2:
                raise
            time.sleep(1.5 * (attempt + 1))


def fetch(layer, fields, bounds=None, where="1=1", precision=6, simplify=None):
    endpoint = layer + "/query"
    filters = {"where": where}
    if bounds:
        filters.update(geometry=",".join(map(str, bounds)), geometryType="esriGeometryEnvelope",
                       inSR=4326, spatialRel="esriSpatialRelIntersects")
    count = request(endpoint, **filters, f="json", returnCountOnly="true")["count"]

    def page(offset):
        args = dict(filters, f="geojson", outSR=4326, outFields=fields, returnGeometry="true",
                    orderByFields="OBJECTID ASC", resultOffset=offset, resultRecordCount=PAGE,
                    geometryPrecision=precision)
        if simplify:
            args["maxAllowableOffset"] = simplify
        data = request(endpoint, **args)
        return data["features"]

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        features = [feature for batch in pool.map(page, range(0, count, PAGE)) for feature in batch]
    if len(features) != count:
        raise RuntimeError(f"{layer}: se esperaban {count} entidades; llegaron {len(features)}")
    return [feature for feature in features if feature.get("geometry")]


def write(filename, data):
    path = DATOS / filename
    staging = path.with_suffix(".tmp")
    staging.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    staging.replace(path)


def collection(features):
    return {"type": "FeatureCollection", "features": features}


def feature(geometry, **properties):
    return {"type": "Feature", "geometry": geometry, "properties": properties}


def layer_meta(file, features):
    return {"file": file, "count": len(features), "bytes": (DATOS / file).stat().st_size}


def build(name, layer, fields, transform, refresh, **options):
    filename = f"{name}.geojson"
    path = DATOS / filename
    needs_street_schema = name == "calles" and path.exists() and any(
        "clase" not in row.get("properties", {}) for row in json.loads(path.read_text()).get("features", [])[:1]
    )
    if refresh or not path.exists() or needs_street_schema:
        rows = [transform(row) for row in fetch(layer, fields, **options)]
        write(filename, collection(rows))
    else:
        rows = json.loads(path.read_text())["features"]
    print(f"{name}: {len(rows):,} figuras ({path.stat().st_size / 1_000_000:.2f} MB)", flush=True)
    return rows


def county_building_tiles(tippecanoe, refresh):
    """Descarga el inventario de edificios y genera teselas para el condado."""
    cache = ROOT / "data" / ".cache"
    cache.mkdir(parents=True, exist_ok=True)
    source = cache / "edificios.ndjson"
    if refresh or not source.exists():
        url = service(BUILDING_SERVICE) + "/query"
        ids = sorted(request(url, f="json", where="1=1", returnIdsOnly="true")["objectIds"])
        print(f"Inventario del condado: {len(ids):,} registros", flush=True)

        def batch(offset):
            group = ids[offset:offset + PAGE]
            result = request(url, f="geojson", where=f"OBJECTID BETWEEN {group[0]} AND {group[-1]}",
                             outSR=4326, outFields=BUILDING_FIELDS, returnGeometry="true",
                             resultRecordCount=PAGE, geometryPrecision=6, maxAllowableOffset=0.000003)
            rows = result["features"]
            if len(rows) != len(group) or result.get("exceededTransferLimit"):
                raise RuntimeError(f"Inventario a partir del objeto {group[0]}: {len(rows)} de {len(group)} registros")
            return [building(row) for row in rows if row.get("geometry")]

        staging = source.with_suffix(".tmp")
        with staging.open("w", encoding="utf-8") as output:
            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                for index, rows in enumerate(pool.map(batch, range(0, len(ids), PAGE)), start=1):
                    for row in rows:
                        output.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
                    if index % 25 == 0:
                        print(f"  {min(index * PAGE, len(ids)):,} registros descargados", flush=True)
        staging.replace(source)

    path = DATOS / "edificios.pmtiles"
    if not path.exists() or source.stat().st_mtime_ns > path.stat().st_mtime_ns:
        tile_archive(tippecanoe, path, ["-Z13", "-z16", "-l", "edificios", str(source)])
    rows = measured = 0
    with source.open(encoding="utf-8") as data:
        for line in data:
            rows += 1
            measured += json.loads(line)["properties"]["height"] is not None
    print(f"edificios: {rows:,} huellas, {measured:,} con altura, {path.stat().st_size / 1_000_000:.1f} MB", flush=True)
    return {"file": path.name, "count": rows, "withHeight": measured, "bytes": path.stat().st_size}


def tile_archive(tippecanoe, path, inputs):
    staging = path.with_name(path.stem + "-temporal.pmtiles")
    subprocess.run([tippecanoe, "-f", "-q", "--drop-densest-as-needed", "--extend-zooms-if-still-dropping",
                    "-o", str(staging), *inputs], check=True)
    staging.replace(path)


def base_tiles(tippecanoe):
    zooms = {"condado": 7, "calles": 8, "agua": 7, "parques": 9, "paradas": 13, "rutas": 10}
    sources = {name: ROOT / "data" / ".cache" / f"{name}.ndjson" for name in ("base", "transit")}
    output_files = {"base": DATOS / "base.pmtiles", "transit": DATOS / "transit.pmtiles"}
    for source in sources.values():
        source.write_text("", encoding="utf-8")
    for name, zoom in zooms.items():
        layer = "transit" if name in {"paradas", "rutas"} else "base"
        raw = json.loads((DATOS / f"{name}.geojson").read_text())
        with sources[layer].open("a", encoding="utf-8") as output:
            for row in raw["features"]:
                row["tippecanoe"] = {"layer": name, "minzoom": zoom}
                output.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
    result = {}
    for name, path in output_files.items():
        tile_archive(tippecanoe, path, ["-Z7", "-z16", str(sources[name])])
        result[name] = {"file": path.name, "bytes": path.stat().st_size}
        print(f"{name}: {path.stat().st_size / 1_000_000:.1f} MB", flush=True)
    return result


def street(row):
    props = row["properties"]
    name = (props.get("SNAME") or props.get("ST_NAME") or "").strip()
    kind = str(props.get("CLASS") or "")
    classes = {
        "0": "rampa", "1": "autopista", "2": "avenida", "3": "avenida",
        "4": "colectora", "5": "local", "6": "servicio", "7": "servicio",
        "8": "servicio", "9": "servicio",
    }
    ramp = truthy(props.get("RAMP")) or kind == "0" or " RAMP" in name.upper()
    bridge = truthy(props.get("BRIDGE")) or any(
        str(props.get(key) or "0") not in {"", "0", "None"} for key in ("F_ZLEV", "T_ZLEV")
    )
    return feature(row["geometry"], name=name, kind=kind, clase="rampa" if ramp else classes.get(kind, "local"),
                   puente=bridge, tunel=truthy(props.get("TUNNEL")), ref=street_ref(name))


def street_ref(name):
    upper = re.sub(r"\s+", " ", name.upper()).strip()
    if "FLORIDA TPKE" in upper or "FLORIDA TURNPIKE" in upper:
        return "FL Turnpike"
    for pattern, prefix in ((r"\bI\s*[- ]?\s*(\d+)\b", "I-"),
                            (r"\bUS\s*[- ]?\s*(\d+)\b", "US-"),
                            (r"\bSR\s*[- ]?\s*(\d+[A-Z]?)\b", "SR-")):
        match = re.search(pattern, upper)
        if match:
            return prefix + match.group(1)
    aliases = {
        "BISCAYNE BLVD": "US-1", "S BISCAYNE BLVD": "US-1",
        "S DIXIE HWY": "US-1", "S FEDERAL HWY": "US-1",
        "W OKEECHOBEE RD": "US-27", "E OKEECHOBEE RD": "US-27",
        "KROME AVE": "SR-997", "N KROME AVE": "SR-997", "S KROME AVE": "SR-997",
    }
    return aliases.get(upper, "")


def truthy(value):
    return str(value or "").strip().lower() in {"1", "true", "yes", "y", "t"}


def named(row):
    props = row["properties"]
    return feature(row["geometry"], name=(props.get("NAME") or "").strip())


def building(row):
    props = row["properties"]
    feet = props.get("BLDG_HEIGHT")
    # El inventario publica pies. Una altura desconocida se dibuja en planta.
    height = round(feet * (1200 / 3937), 1) if isinstance(feet, (int, float)) and 2 <= feet <= 1200 else None
    return feature(row["geometry"], height=height, address=(props.get("ADDRESS") or "").strip())


def read_bundle(path):
    stops = json.loads((path / "paradas.json").read_text())
    routes = {r["id"]: r for r in json.loads((path / "rutas.json").read_text())}
    shapes = json.loads((path / "recorridos.json").read_text())
    point_layers = []
    for stop in stops:
        available = [routes[r] for r in stop["rutas"] if r in routes]
        codes = list(dict.fromkeys(r["corto"] for r in available))
        point_layers.append(feature({"type": "Point", "coordinates": [stop["lon"], stop["lat"]]},
                                    id=stop["id"], name=stop["nombre"], routes=" · ".join(codes),
                                    routeFilter="|" + "|".join(codes) + "|",
                                    rail=any(r["tipo"] in (0, 1, 2) for r in available)))
    line_layers = []
    for rid, directions in shapes.items():
        route = routes.get(rid)
        if route is None:
            continue
        color = (route.get("color") or "").lstrip("#")
        if len(color) != 6 or any(c not in "0123456789abcdefABCDEF" for c in color):
            color = "167a77"
        for direction in directions:
            coords = [[round(lon, 6), round(lat, 6)] for lat, lon in direction["trazado"]]
            if len(coords) >= 2:
                line_layers.append(feature({"type": "LineString", "coordinates": coords},
                                           route=route["corto"], name=route["largo"], color=f"#{color}",
                                           rail=route["tipo"] in (0, 1, 2)))
    return point_layers, line_layers


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gtfs-datos", type=Path, default=ROOT / "data" / "gtfs")
    parser.add_argument("--actualizar", action="store_true", help="Repetir las descargas de las capas geográficas.")
    parser.add_argument("--todo-condado", action="store_true", help="Generar teselas de edificios de todo el inventario.")
    parser.add_argument("--tippecanoe", default="tippecanoe", help="Ruta al ejecutable Tippecanoe.")
    args = parser.parse_args()
    DATOS.mkdir(parents=True, exist_ok=True)
    bundle = read_bundle(args.gtfs_datos)
    build_jobs = [
        ("condado", COUNTY, "NAME", named, {"where": "GEOID='12086'", "simplify": 0.00004}),
        ("calles", service("StreetNetwork_gdb"),
         "SNAME,ST_NAME,CLASS,RAMP,BRIDGE,TUNNEL,F_ZLEV,T_ZLEV", street, {"simplify": 0.000008}),
        ("agua", service("Water_gdb"), "NAME", named, {"simplify": 0.000014}),
        ("parques", service("MunicipalParkBoundary_gdb"), "NAME", named, {"simplify": 0.00001}),
    ]
    for key, zone in ZONES.items():
        build_jobs.append((key, service(BUILDING_SERVICE), BUILDING_FIELDS, building,
                           {"bounds": zone["bounds"], "simplify": 0.000003}))
    def job(spec):
        name, layer, fields, transform, options = spec
        rows = build(name, layer, fields, transform, args.actualizar, **options)
        result = layer_meta(f"{name}.geojson", rows)
        if name in ZONES:
            result["withHeight"] = sum(row["properties"]["height"] is not None for row in rows)
            result["maxHeight"] = max((row["properties"]["height"] or 0 for row in rows), default=0)
        return name, result
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        layers = dict(pool.map(job, build_jobs))
    for name, rows in zip(("paradas", "rutas"), bundle):
        write(f"{name}.geojson", collection(rows))
        layers[name] = layer_meta(f"{name}.geojson", rows)
    if args.todo_condado:
        layers["edificios"] = county_building_tiles(args.tippecanoe, args.actualizar)
        layers.update(base_tiles(args.tippecanoe))
    write("manifest.json", {"layers": layers, "zones": ZONES, "generated": time.strftime("%Y-%m-%d")})


if __name__ == "__main__":
    main()
