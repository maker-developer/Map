#!/usr/bin/env python3
"""Build a small low-zoom regional basemap around Miami-Dade.

Needs osmium-tool, tippecanoe, shapely and pyshp. The Florida PBF and source
GeoJSON are cached under data/.cache/sur-florida (never committed).
"""
from __future__ import annotations

import json
import shutil
import subprocess
import urllib.request
import zipfile
from pathlib import Path

import shapefile
from shapely.geometry import box, mapping, shape
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / "data/.cache/sur-florida"
OUTPUT = ROOT / "public/data/regional.pmtiles"
PBF = CACHE / "florida.osm.pbf"
PBF_URL = "https://download.geofabrik.de/north-america/us/florida-261124.osm.pbf"
COUNTY_URL = (
    "https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/State_County/"
    "MapServer/1/query?where=STATE%3D%2712%27%20AND%20COUNTY%20IN%20"
    "(%27011%27%2C%27086%27%2C%27087%27)&outFields=NAME%2CSTATE%2CCOUNTY%2C"
    "GEOID&outSR=4326&f=geojson"
)
NE_URL = "https://naciscdn.org/naturalearth/10m/physical/ne_10m_land.zip"
COUNTIES = {"12011": "Broward County", "12086": "Miami-Dade County", "12087": "Monroe County"}
ROADS = {"motorway": "autopista", "trunk": "autopista", "primary": "principal",
         "secondary": "avenida", "tertiary": "colectora"}
ROAD_TAGS = ",".join(ROADS | {f"{x}_link": "rampa" for x in ROADS})


def fetch(url: str, path: Path) -> None:
    if path.exists() and path.stat().st_size:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": "Map regional data builder/1.0"})
    with urllib.request.urlopen(request, timeout=120) as response, path.open("wb") as out:
        shutil.copyfileobj(response, out)


def run(*args: str) -> None:
    print("$", " ".join(map(str, args)), flush=True)
    subprocess.run(args, check=True)


def clean(geom):
    if geom is None or geom.is_empty:
        return None
    if not geom.is_valid:
        geom = geom.buffer(0)
    if geom.is_empty:
        return None
    return geom


def write_seq(path: Path, features) -> int:
    count = 0
    with path.open("w", encoding="utf-8") as out:
        for geom, props in features:
            geom = clean(geom)
            if geom is None:
                continue
            out.write(json.dumps({"type": "Feature", "geometry": mapping(geom),
                                 "properties": props}, ensure_ascii=False, separators=(",", ":")) + "\n")
            count += 1
    return count


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    counties_path = CACHE / "counties.geojson"
    fetch(PBF_URL, PBF)
    fetch(COUNTY_URL, counties_path)
    counties_fc = json.loads(counties_path.read_text())
    selected = [f for f in counties_fc["features"] if f["properties"].get("GEOID") in COUNTIES]
    if len(selected) != 3:
        raise RuntimeError(f"Se esperaban 3 condados del Censo; llegaron {len(selected)}")
    county_union = unary_union([shape(f["geometry"]) for f in selected])
    bounds = county_union.bounds
    left, bottom, right, top = bounds

    ne_zip = CACHE / "ne_10m_land.zip"
    ne_dir = CACHE / "natural-earth"
    fetch(NE_URL, ne_zip)
    shp = ne_dir / "ne_10m_land.shp"
    if not shp.exists():
        ne_dir.mkdir(exist_ok=True)
        with zipfile.ZipFile(ne_zip) as zf:
            zf.extractall(ne_dir)
    land_parts = []
    reader = shapefile.Reader(str(shp))
    regional_box = box(left, bottom, right, top)
    for record in reader.iterShapeRecords():
        geom = shape(record.shape.__geo_interface__)
        if geom.intersects(regional_box):
            clipped = clean(geom.intersection(county_union))
            if clipped is not None:
                land_parts.append(clipped)
    land = clean(unary_union(land_parts))
    ocean = clean(county_union.difference(land))

    interim = CACHE / "extract.pbf"
    filtered = CACHE / "selected.osm.pbf"
    geojsonseq = CACHE / "selected.geojsonseq"
    run("osmium", "extract", f"--bbox={left},{bottom},{right},{top}", "--strategy=complete_ways",
        "--set-bounds", "--overwrite", "-o", str(interim), str(PBF))
    run("osmium", "tags-filter", "--overwrite", "-o", str(filtered), str(interim),
        f"w/highway={ROAD_TAGS}", "n/place=city,town,village,suburb", "w/waterway=river,canal",
        "w/natural=water", "r/natural=water", "w/landuse=reservoir")
    run("osmium", "export", "--overwrite", "--add-unique-id=type_id", "-o", str(geojsonseq), str(filtered))

    data = {"roads": [], "places": [], "waterways": [], "water": []}
    with geojsonseq.open(encoding="utf-8") as src:
        for line in src:
            row = json.loads(line.lstrip("\x1e"))
            props = row.get("properties") or {}
            geom = clean(shape(row["geometry"]).intersection(county_union))
            if geom is None:
                continue
            tags = props.get("tags", props)
            highway = tags.get("highway")
            if highway in ROADS or highway in {f"{x}_link" for x in ROADS}:
                data["roads"].append((geom, {"name": tags.get("name", ""), "kind": ROADS.get(highway, "rampa"),
                                             "clase": highway, "ref": tags.get("ref", ""),
                                             "bridge": tags.get("bridge", ""), "tunnel": tags.get("tunnel", "")}))
            elif tags.get("place") in {"city", "town", "village", "suburb"} and geom.geom_type == "Point":
                data["places"].append((geom, {"name": tags.get("name", ""), "kind": tags["place"]}))
            elif tags.get("waterway") in {"river", "canal"}:
                data["waterways"].append((geom, {"name": tags.get("name", ""), "kind": tags["waterway"]}))
            elif tags.get("natural") == "water" or tags.get("landuse") == "reservoir":
                data["water"].append((geom, {"name": tags.get("name", ""), "kind": tags.get("water", tags.get("landuse", "water"))}))

    layers = {
        "regional_land": [(clean(land.simplify(0.0008, preserve_topology=True)), {})],
        "regional_ocean": [(clean(ocean.simplify(0.0008, preserve_topology=True)), {})],
        "regional_counties": [(clean(shape(f["geometry"]).simplify(0.001, preserve_topology=True)),
                               {"name": f["properties"]["NAME"], "geoid": f["properties"]["GEOID"]}) for f in selected],
        "regional_roads": data["roads"],
        "regional_places": data["places"],
        "regional_waterways": data["waterways"],
        "regional_water": data["water"],
    }
    inputs = []
    report = {}
    for layer, features in layers.items():
        path = CACHE / f"{layer}.geojsonl"
        report[layer] = write_seq(path, features)
        inputs.extend(["-L", f"{layer}:{path.relative_to(ROOT)}"])
        print(f"{layer}: {report[layer]} features", flush=True)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    run("tippecanoe", "--force", "--output", str(OUTPUT.relative_to(ROOT)), "--name=Map regional low detail",
        "--description=Broward, Miami-Dade and Monroe low-zoom coverage", "--attribution=© OpenStreetMap contributors · Natural Earth · U.S. Census TIGERweb",
        "--minimum-zoom=5", "--maximum-zoom=10", "--drop-densest-as-needed", "--simplification=5", *inputs)
    manifest = {"file": OUTPUT.name, "bytes": OUTPUT.stat().st_size, "minzoom": 5, "maxzoom": 10,
                "bounds": [left, bottom, right, top], "layers": report,
                "sources": {"roads_water_places": "Geofabrik Florida extract 2026-11-24 (OpenStreetMap, ODbL)",
                            "land": "Natural Earth 1:10m Physical, version 5.1.1 (public domain)",
                            "county_boundaries": "U.S. Census TIGERweb State_County layer 1"},
                "attribution": "© OpenStreetMap contributors · Natural Earth · U.S. Census TIGERweb"}
    (OUTPUT.parent / "regional.manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2), flush=True)


if __name__ == "__main__":
    main()
