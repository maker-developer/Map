import { light } from '../../../../styles/base-light.js';
import { dark } from '../../../../styles/base-dark.js';

const labels = ['DM Sans'];
const majorRoad = ['in', ['get', 'kind'], ['literal', ['0', '1', '2', '3']]];
const namedRoad = ['!=', ['get', 'name'], ''];
const lineLayout = { 'line-cap': 'round', 'line-join': 'round' };

export const themes = { light, dark };

export function baseStyle(theme) {
  const palette = themes[theme];

  return {
    version: 8,
    'font-faces': { 'DM Sans': [{ url: new URL('../../../../styles/fonts/DMSans-Regular.ttf', import.meta.url).href }] },
    light: { anchor: 'map', intensity: .45, color: '#fff5e5', position: [1.15, 210, 35] },
    sources: {
      base: { type: 'vector', url: 'pmtiles:///data/base.pmtiles' },
      towns: { type: 'geojson', data: townLocations },
    },
    layers: [
      { id: 'background', type: 'background', paint: { 'background-color': palette.background } },
      { id: 'land', source: 'base', 'source-layer': 'condado', type: 'fill', paint: { 'fill-color': palette.land } },
      { id: 'parks', source: 'base', 'source-layer': 'parques', type: 'fill',
        paint: { 'fill-color': palette.park, 'fill-outline-color': palette.parkOutline } },
      { id: 'water', source: 'base', 'source-layer': 'agua', type: 'fill',
        paint: { 'fill-color': palette.water, 'fill-outline-color': palette.waterOutline } },
      { id: 'county-line', source: 'base', 'source-layer': 'condado', type: 'line', maxzoom: 12,
        paint: { 'line-color': palette.boundary, 'line-width': 1.1, 'line-dasharray': [3, 2] } },
      { id: 'streets', source: 'base', 'source-layer': 'calles', type: 'line', minzoom: 11, layout: lineLayout,
        paint: { 'line-color': palette.street, 'line-width': ['interpolate', ['linear'], ['zoom'], 11, .35, 14, 1.6, 17, 5.5, 19, 10] } },
      { id: 'main-streets-casing', source: 'base', 'source-layer': 'calles', type: 'line', filter: majorRoad, minzoom: 8, layout: lineLayout,
        paint: { 'line-color': palette.mainStreetCasing, 'line-width': ['interpolate', ['linear'], ['zoom'], 9, 1.6, 13, 2.7, 16, 5.9, 19, 15.9], 'line-opacity': .8 } },
      { id: 'main-streets', source: 'base', 'source-layer': 'calles', type: 'line', filter: majorRoad, minzoom: 8, layout: lineLayout,
        paint: { 'line-color': palette.mainStreet, 'line-width': ['interpolate', ['linear'], ['zoom'], 9, .7, 13, 1.8, 16, 5, 19, 15] } },
      { id: 'street-names', source: 'base', 'source-layer': 'calles', type: 'symbol', minzoom: 14.4, filter: namedRoad,
        layout: { 'symbol-placement': 'line', 'symbol-spacing': 185, 'text-field': ['get', 'name'],
          'text-font': labels, 'text-size': ['interpolate', ['linear'], ['zoom'], 14.4, 10, 18, 13], 'text-max-angle': 38 },
        paint: { 'text-color': palette.streetLabel, 'text-halo-color': palette.halo, 'text-halo-width': 1.3 } },
      { id: 'towns', source: 'towns', type: 'symbol', minzoom: 8, maxzoom: 14,
        layout: { 'text-field': ['get', 'name'], 'text-font': labels, 'text-size': 14 },
        paint: { 'text-color': palette.cityLabel, 'text-halo-color': palette.halo, 'text-halo-width': 1.8 } },
    ],
  };
}

export function applyTheme(map, theme) {
  const palette = themes[theme];
  const colors = {
    background: ['background-color', palette.background],
    land: ['fill-color', palette.land],
    parks: ['fill-color', palette.park],
    water: ['fill-color', palette.water],
    'county-line': ['line-color', palette.boundary],
    streets: ['line-color', palette.street],
    'main-streets': ['line-color', palette.mainStreet],
    'main-streets-casing': ['line-color', palette.mainStreetCasing],
    'street-names': ['text-color', palette.streetLabel],
    towns: ['text-color', palette.cityLabel],
  };
  for (const [id, [property, value]] of Object.entries(colors)) map.setPaintProperty(id, property, value);
  map.setPaintProperty('parks', 'fill-outline-color', palette.parkOutline);
  map.setPaintProperty('water', 'fill-outline-color', palette.waterOutline);
  map.setPaintProperty('street-names', 'text-halo-color', palette.halo);
  map.setPaintProperty('towns', 'text-halo-color', palette.halo);
  map.setPaintProperty('buildings-footprints', 'fill-color', palette.building);
  map.setPaintProperty('buildings-footprints', 'fill-outline-color', palette.buildingOutline);
  map.setPaintProperty('buildings-volume', 'fill-extrusion-color', buildingColor(palette));
}

export function buildingLayers(palette) {
  const color = buildingColor(palette);
  return [
    { id: 'buildings-footprints', source: 'buildings', 'source-layer': 'edificios', type: 'fill', minzoom: 13,
      paint: { 'fill-color': palette.building, 'fill-outline-color': palette.buildingOutline } },
    { id: 'buildings-volume', source: 'buildings', 'source-layer': 'edificios', type: 'fill-extrusion', minzoom: 13,
      filter: ['!=', ['get', 'height'], null],
      paint: { 'fill-extrusion-height': ['get', 'height'], 'fill-extrusion-color': color,
        'fill-extrusion-base': 0, 'fill-extrusion-vertical-gradient': true } },
  ];
}

function buildingColor(palette) {
  return ['interpolate', ['linear'], ['coalesce', ['get', 'height'], 0],
    0, palette.buildingLow, 15, palette.buildingLow, 46, palette.buildingMid, 120, palette.buildingHigh, 200, palette.buildingHigh];
}

const townLocations = {
  type: 'FeatureCollection',
  features: [
    ['Miami', -80.207, 25.778], ['Miami Beach', -80.132, 25.823], ['Miami Lakes', -80.324, 25.912],
    ['Hialeah', -80.291, 25.848], ['Doral', -80.356, 25.814], ['Coral Gables', -80.264, 25.749],
    ['Kendall', -80.340, 25.671], ['Homestead', -80.477, 25.469], ['Key Biscayne', -80.163, 25.693],
    ['Aventura', -80.140, 25.958], ['Everglades', -80.784, 25.545],
  ].map(([name, longitude, latitude]) => ({
    type: 'Feature',
    geometry: { type: 'Point', coordinates: [longitude, latitude] },
    properties: { name },
  })),
};
