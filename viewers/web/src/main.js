import { Map, NavigationControl, ScaleControl, Popup, addProtocol, setWorkerUrl } from 'maplibre-gl';
import { Protocol } from 'pmtiles';
import mapWorkerURL from 'maplibre-gl/dist/maplibre-gl-worker.mjs?url';
import 'maplibre-gl/dist/maplibre-gl.css';
import './viewer.css';
import { addTransitLayers, setTransitVisible } from './features/transit.js';
import { addBuildingLayers, setBuildingVisibility } from './map/buildings.js';
import { addShieldImages, applyTheme, baseStyle } from './map/style.js';

setWorkerUrl(new URL(mapWorkerURL, location.href).href);
addProtocol('pmtiles', new Protocol().tile);

const mapElement = document.getElementById('map');
const status = document.getElementById('map-status');
const error = document.getElementById('map-error');
const buildingControl = document.getElementById('buildings');
const themeControl = document.getElementById('theme');
const transitControl = document.querySelector('.transit-toggle');
const routeControl = document.getElementById('route');
const bounds = [[-80.874, 25.137], [-80.062, 25.98]];
const map = new Map({
  container: mapElement,
  style: baseStyle(themeControl.value),
  center: [-80.52, 25.62],
  zoom: 9.5,
  minZoom: 7,
  maxZoom: 20,
  maxBounds: [[-81.04, 25.08], [-79.85, 26.04]],
  renderWorldCopies: false,
  attributionControl: false,
  maxPitch: 65,
  // La vista queda en la dirección (#zoom/lat/lon/rumbo/inclinación): se puede compartir o volver a ella.
  hash: true,
});

addShieldImages(map);
map.addControl(new NavigationControl({ visualizePitch: true }), 'top-right');
map.addControl(new ScaleControl({ unit: 'metric' }), 'bottom-left');

map.on('error', event => {
  error.hidden = false;
  error.textContent = 'No se pudo cargar una capa del mapa. ' + (event.error?.message ?? '');
});

map.on('load', async () => {
  addTransitLayers(map);
  addBuildingLayers(map, buildingControl.checked);
  addBuildingInteraction(map);
  // rutas.geojson es una FeatureCollection: las rutas están en .features.
  addRouteOptions((await loadRoutes()).features ?? []);
  setTransitVisible(map, transitControl.checked);
  status.textContent = 'Miami-Dade · 605.762 edificios · 567.911 con altura';
  if (!location.hash) map.fitBounds(bounds, { padding: 28, duration: 0 });
});

themeControl.addEventListener('change', () => {
  document.documentElement.dataset.theme = themeControl.value;
  applyTheme(map, themeControl.value);
});

buildingControl.addEventListener('change', () => setBuildingVisibility(map, buildingControl.checked));
transitControl.addEventListener('change', () => setTransitVisible(map, transitControl.checked, routeControl.value));
routeControl.addEventListener('change', () => setTransitVisible(map, transitControl.checked, routeControl.value));

function addBuildingInteraction(map) {
  map.on('click', 'buildings-footprints', event => {
    if (!buildingControl.checked && event.features?.[0]?.properties?.height != null) return;
    if (map.queryRenderedFeatures(event.point, { layers: ['buildings-volume'] }).length) return;
    showBuilding(event);
  });
  map.on('click', 'buildings-volume', showBuilding);
}

function showBuilding(event) {
  const building = event.features?.[0]?.properties;
  if (!building) return;
  const detail = document.createElement('div');
  const address = document.createElement('strong');
  const height = document.createElement('p');
  address.textContent = building.address || 'Edificio';
  height.textContent = building.height == null
    ? 'Altura sin publicar'
    : 'Altura en el inventario: ' + building.height + ' m';
  detail.append(address, height);
  new Popup({ maxWidth: '240px' }).setLngLat(event.lngLat).setDOMContent(detail).addTo(map);
}

async function loadRoutes() {
  const response = await fetch('/data/rutas.geojson');
  if (!response.ok) throw new Error('No se pudo cargar el catálogo de rutas (' + response.status + ')');
  return response.json();
}

function addRouteOptions(features) {
  const routes = new globalThis.Map();
  for (const { properties } of features) routes.set(properties.route, properties.name);
  for (const [id, name] of [...routes].sort(([a], [b]) => a.localeCompare(b, 'es', { numeric: true }))) {
    routeControl.add(new Option(name ? id + ' · ' + name : id, id));
  }
}
