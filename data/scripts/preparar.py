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
from urllib.error import HTTPError, URLError
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


def write_manifest(data):
    path = DATOS / "manifest.json"
    staging = path.with_suffix(".tmp")
    staging.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
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


def base_tiles(tippecanoe, base_only=False):
    zooms = {"condado": 7, "calles": 8, "agua": 7, "parques": 9, "playas": 9,
             "profundidad": 7, "agua-nombres": 10, "agua-ejes": 10,
             "paradas": 13, "rutas": 10}
    if base_only:
        zooms = {name: zoom for name, zoom in zooms.items()
                 if name not in {"paradas", "rutas"}}
        sources = {"base": ROOT / "data" / ".cache" / "base.ndjson"}
        output_files = {"base": DATOS / "base.pmtiles"}
    else:
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
    speed_info = None
    if "base" in sources:
        from velocidades import enrich_base_ndjson
        speed_info = enrich_base_ndjson(sources["base"])
    result = {}
    for name, path in output_files.items():
        tile_archive(tippecanoe, path, ["-Z7", "-z16", str(sources[name])])
        result[name] = {"file": path.name, "bytes": path.stat().st_size}
        print(f"{name}: {path.stat().st_size / 1_000_000:.1f} MB", flush=True)
    if speed_info:
        result["limites-velocidad"] = speed_info
        print(f"calles.vmax: {speed_info['streetFeaturesWithVmax']:,} tramos con límite explícito", flush=True)
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


def bathymetry(refresh):
    """Vectoriza bandas marinas del NOAA Florida Coastal Relief Model."""
    import numpy as np
    import contourpy
    from netCDF4 import Dataset
    from shapely.geometry import Polygon, MultiPolygon, mapping
    from scipy.ndimage import gaussian_filter

    path = DATOS / "profundidad.geojson"
    if not refresh and path.exists():
        return json.loads(path.read_text())["features"]

    # CRM Vol. 3 ocupa 24–32 N y -84–-76 W, con celdas de 1 segundo de arco.
    # Recorte Miami-Dade y la plataforma continental inmediata.
    url = "https://www.ngdc.noaa.gov/thredds/dodsC/crm/cudem/crm_vol3_2023.nc"
    lat0, lat1 = 4248, 7380  # 25.18–26.05 N
    lon0, lon1 = 10800, 15660  # -81.00–-79.65 W
    with Dataset(url) as dataset:
        lat = np.asarray(dataset.variables["lat"][lat0:lat1], dtype="float64")
        lon = np.asarray(dataset.variables["lon"][lon0:lon1], dtype="float64")
        elevation = np.asarray(dataset.variables["z"][lat0:lat1, lon0:lon1], dtype="float32")
    elevation[elevation <= -99990] = np.nan
    wet = np.isfinite(elevation) & (elevation < 0)
    weights = gaussian_filter(wet.astype("float32"), sigma=1.25, mode="nearest")
    smooth = gaussian_filter(np.where(wet, elevation, 0).astype("float32"), sigma=1.25, mode="nearest")
    smooth = np.divide(smooth, weights, out=np.full_like(smooth, np.nan), where=weights >= 0.2)
    smooth[~wet] = np.nan
    generator = contourpy.contour_generator(x=lon, y=lat, z=smooth, fill_type="OuterOffset")
    bands = [("0-1", -1, 0), ("1-2", -2, -1), ("2-5", -5, -2),
             ("5-10", -10, -5), ("10+", float(np.nanmin(smooth)), -10)]
    rows = []
    for label, low, high in bands:
        if low >= high:
            continue
        for points, offsets in zip(*generator.filled(low, high)):
            rings = [Polygon(points[a:b]).buffer(0) for a, b in zip(offsets[:-1], offsets[1:])]
            rings = [part for ring in rings if not ring.is_empty
                     for part in (ring.geoms if isinstance(ring, MultiPolygon) else [ring])
                     if part.area > 0]
            # Anillo de mayor nivel de inclusión = exterior; anillos hijos impares = huecos.
            parents = []
            for ring in rings:
                candidates = [i for i, other in enumerate(rings)
                              if other.area > ring.area and other.contains(ring.representative_point())]
                parents.append(min(candidates, key=lambda i: rings[i].area) if candidates else None)
            depths = []
            for i in range(len(rings)):
                depth, parent, seen = 0, parents[i], {i}
                while parent is not None and parent not in seen:
                    depth += 1
                    seen.add(parent)
                    parent = parents[parent]
                depths.append(depth)
            for i, ring in enumerate(rings):
                if depths[i] % 2:
                    continue
                holes = [list(rings[j].exterior.coords) for j, parent in enumerate(parents)
                         if parent == i and depths[j] == depths[i] + 1]
                polygon = Polygon(ring.exterior.coords, holes).simplify(0.0004, preserve_topology=True)
                if polygon.is_empty or polygon.area < 0.00000015:
                    continue
                rows.append(feature(mapping(polygon), banda=label))
    write("profundidad.geojson", collection(rows))
    print(f"profundidad: {len(rows):,} polígonos NOAA", flush=True)
    return rows


def clip_depth_to_water(depth_rows, water_rows):
    """Recorta las bandas NOAA al agua del condado y conserva la costa como límite."""
    from shapely.geometry import shape, mapping, Polygon, MultiPolygon, GeometryCollection
    from shapely.strtree import STRtree
    from shapely.ops import unary_union
    from shapely import make_valid

    water_geometries = [make_valid(shape(row["geometry"])) for row in water_rows if row.get("geometry")]
    if not water_geometries:
        raise RuntimeError("La capa agua no contiene polígonos para recortar profundidad")
    tree = STRtree(water_geometries)
    result, before_area, after_area = [], 0.0, 0.0
    for row in depth_rows:
        source = make_valid(shape(row["geometry"]))
        before_area += source.area
        nearby = tree.query(source, predicate="intersects")
        if len(nearby) == 0:
            continue
        water_piece = make_valid(unary_union([water_geometries[int(index)] for index in nearby]))
        clipped = source.intersection(water_piece)
        if clipped.is_empty:
            continue
        # Simplificar para quitar vértices residuales y volver a recortar para que
        # el borde resultante nunca se extienda sobre tierra ni muelles.
        clipped = make_valid(clipped.simplify(0.00015, preserve_topology=True))
        clipped = make_valid(clipped.intersection(water_piece)).buffer(0)
        if isinstance(clipped, Polygon):
            polygons = [clipped]
        elif isinstance(clipped, MultiPolygon):
            polygons = list(clipped.geoms)
        elif isinstance(clipped, GeometryCollection):
            polygons = [part for part in clipped.geoms if isinstance(part, Polygon)]
        else:
            polygons = []
        polygons = [polygon for polygon in polygons if polygon.area >= 0.00000001]
        if not polygons:
            continue
        geometry = polygons[0] if len(polygons) == 1 else MultiPolygon(polygons)
        after_area += geometry.area
        result.append(feature(mapping(geometry), banda=row["properties"]["banda"]))
    if not result:
        raise RuntimeError("El recorte con la capa agua eliminó todas las bandas de profundidad")
    write("profundidad.geojson", collection(result))
    pct = 100 * (1 - after_area / before_area) if before_area else 0
    print(f"profundidad recortada: {len(result):,} polígonos; área removida {pct:.1f}%", flush=True)
    return result


def named_water_layers(refresh):
    """Obtiene ejes y topónimos hidrográficos nombrados de OpenStreetMap."""
    cache = ROOT / "data" / ".cache"
    cache.mkdir(parents=True, exist_ok=True)
    source = cache / "osm-water.json"
    if refresh or not source.exists():
        query = ('[out:json][timeout:60];(way["waterway"]["name"~'
                 '"Miami River|Little River|Snake Creek|Intracoastal Waterway",i]'
                 '(25.18,-81.0,26.05,-79.65););out geom;'
                 '(way["natural"="water"]["name"](25.18,-81.0,26.05,-79.65);'
                 'relation["natural"="water"]["name"](25.18,-81.0,26.05,-79.65););out center;')
        last_error = None
        for endpoint in ("https://overpass-api.de/api/interpreter",
                         "https://overpass.kumi.systems/api/interpreter"):
            req = Request(endpoint, data=query.encode(),
                          headers={"Content-Type": "application/x-www-form-urlencoded",
                                   "User-Agent": "Map Miami-Dade data pipeline/1.0"})
            try:
                with urlopen(req, timeout=90) as response:
                    source.write_bytes(response.read())
                break
            except (HTTPError, URLError, TimeoutError) as error:
                last_error = error
        else:
            if not source.exists():
                raise RuntimeError(f"No se pudo descargar el extracto OSM y no hay caché: {last_error}")
    elements = json.loads(source.read_text(encoding="utf-8"))["elements"]
    axes, labels = {}, [
        feature({"type": "Point", "coordinates": [-80.18, 25.66]}, name="Biscayne Bay"),
        feature({"type": "Point", "coordinates": [-79.78, 25.68]}, name="Atlantic Ocean"),
    ]
    canonical = (("Miami River", "Miami River"), ("Little River", "Little River"),
                 ("Snake Creek", "Snake Creek"), ("Intracoastal Waterway", "Intracoastal Waterway"))
    for element in elements:
        tags = element.get("tags", {})
        name = tags.get("name", "").strip()
        if not name:
            continue
        if tags.get("waterway"):
            mapped = next((label for token, label in canonical if token.lower() in name.lower()), None)
            coords = [[point["lon"], point["lat"]] for point in element.get("geometry", [])]
            if mapped and len(coords) >= 2:
                axes.setdefault(mapped, []).append(coords)
            continue
        if tags.get("natural") != "water" or not any(
                word in name.lower() for word in ("lake", "bay", "lagoon")):
            continue
        center = element.get("center")
        geometry = element.get("geometry", [])
        if center:
            location = [center["lon"], center["lat"]]
        elif geometry:
            location = [sum(p["lon"] for p in geometry) / len(geometry),
                        sum(p["lat"] for p in geometry) / len(geometry)]
        else:
            continue
        labels.append(feature({"type": "Point", "coordinates": location}, name=name))
    line_rows = [feature({"type": "MultiLineString", "coordinates": segments}, name=name)
                 for name, segments in axes.items()]
    write("agua-nombres.geojson", collection(labels))
    write("agua-ejes.geojson", collection(line_rows))
    print(f"agua-nombres: {len(labels)}; agua-ejes: {len(line_rows)} nombres", flush=True)
    return labels, line_rows


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
    parser.add_argument("--solo-base", action="store_true", help="Actualizar base.pmtiles sin requerir GTFS ni reconstruir otros archivos.")
    parser.add_argument("--tippecanoe", default="tippecanoe", help="Ruta al ejecutable Tippecanoe.")
    args = parser.parse_args()
    DATOS.mkdir(parents=True, exist_ok=True)
    if args.solo_base:
        specs = [
            ("condado", COUNTY, "NAME", named, {"where": "GEOID='12086'", "simplify": 0.00004}),
            ("calles", service("StreetNetwork_gdb"),
             "SNAME,ST_NAME,CLASS,RAMP,BRIDGE,TUNNEL,F_ZLEV,T_ZLEV", street, {"simplify": 0.000008}),
            ("agua", service("Water_gdb"), "NAME", named, {"simplify": 0.000014}),
            ("parques", service("MunicipalParkBoundary_gdb"), "NAME", named, {"simplify": 0.00001}),
            ("playas", service("Beachpoly_gdb"), "NAME", named, {"simplify": 0.000004}),
        ]
        layers = {}
        water_rows = None
        for name, layer, fields, transform, options in specs:
            rows = build(name, layer, fields, transform, args.actualizar, **options)
            if name == "agua":
                water_rows = rows
            layers[name] = layer_meta(f"{name}.geojson", rows)
        depth_rows = clip_depth_to_water(bathymetry(args.actualizar), water_rows)
        layers["profundidad"] = layer_meta("profundidad.geojson", depth_rows)
        water_labels, water_axes = named_water_layers(args.actualizar)
        layers["agua-nombres"] = layer_meta("agua-nombres.geojson", water_labels)
        layers["agua-ejes"] = layer_meta("agua-ejes.geojson", water_axes)
        tile_info = base_tiles(args.tippecanoe, base_only=True)
        existing = json.loads((DATOS / "manifest.json").read_text()) if (DATOS / "manifest.json").exists() else {}
        existing_layers = existing.get("layers", {})
        existing_layers.update(layers)
        existing_layers.update(tile_info)
        if tile_info.get("limites-velocidad") and "calles" in existing_layers:
            existing_layers["calles"]["withVmax"] = tile_info["limites-velocidad"]["streetFeaturesWithVmax"]
        write_manifest({**existing, "layers": existing_layers, "generated": time.strftime("%Y-%m-%d")})
        return
    bundle = read_bundle(args.gtfs_datos)
    build_jobs = [
        ("condado", COUNTY, "NAME", named, {"where": "GEOID='12086'", "simplify": 0.00004}),
        ("calles", service("StreetNetwork_gdb"),
         "SNAME,ST_NAME,CLASS,RAMP,BRIDGE,TUNNEL,F_ZLEV,T_ZLEV", street, {"simplify": 0.000008}),
        ("agua", service("Water_gdb"), "NAME", named, {"simplify": 0.000014}),
        ("parques", service("MunicipalParkBoundary_gdb"), "NAME", named, {"simplify": 0.00001}),
        ("playas", service("Beachpoly_gdb"), "NAME", named, {"simplify": 0.000004}),
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
        water_rows = json.loads((DATOS / "agua.geojson").read_text())["features"]
        depth_rows = clip_depth_to_water(bathymetry(args.actualizar), water_rows)
        layers["profundidad"] = layer_meta("profundidad.geojson", depth_rows)
        water_labels, water_axes = named_water_layers(args.actualizar)
        layers["agua-nombres"] = layer_meta("agua-nombres.geojson", water_labels)
        layers["agua-ejes"] = layer_meta("agua-ejes.geojson", water_axes)
        layers["edificios"] = county_building_tiles(args.tippecanoe, args.actualizar)
        tile_info = base_tiles(args.tippecanoe)
        layers.update(tile_info)
        if tile_info.get("limites-velocidad") and "calles" in layers:
            layers["calles"]["withVmax"] = tile_info["limites-velocidad"]["streetFeaturesWithVmax"]
    write_manifest({"layers": layers, "zones": ZONES, "generated": time.strftime("%Y-%m-%d")})


if __name__ == "__main__":
    main()
