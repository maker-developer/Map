import { Popup } from 'maplibre-gl';

const lineLayout = { 'line-cap': 'round', 'line-join': 'round' };
let popup;

export function addTransitLayers(map) {
  map.addSource('transit', {
    type: 'vector',
    url: `pmtiles://${new URL('/data/transit.pmtiles', location.origin).href}`,
  });
  // Rutas y paradas debajo de los edificios (que las tapan si quedan detrás) y de los municipios.
  map.addLayer({
    id: 'transit-routes',
    source: 'transit',
    'source-layer': 'rutas',
    type: 'line',
    minzoom: 10,
    layout: lineLayout,
    paint: {
      'line-width': ['interpolate', ['linear'], ['zoom'], 10, .8, 15, 2.3, 19, 4.8],
      'line-color': ['case', ['get', 'rail'], '#194d49', ['get', 'color']],
      'line-opacity': .68,
    },
  }, 'towns');
  map.addLayer({
    id: 'transit-stops',
    source: 'transit',
    'source-layer': 'paradas',
    type: 'circle',
    minzoom: 13.1,
    paint: {
      'circle-radius': ['interpolate', ['linear'], ['zoom'], 13.1, 1.65, 17, 5.3],
      'circle-color': ['case', ['get', 'rail'], '#06634e', '#087c96'],
      'circle-stroke-color': '#fffbef',
      'circle-stroke-width': 1.4,
    },
  }, 'towns');
  map.on('click', 'transit-stops', event => showStop(event, map));
  map.on('mouseenter', 'transit-stops', () => { map.getCanvas().style.cursor = 'pointer'; });
  map.on('mouseleave', 'transit-stops', () => { map.getCanvas().style.cursor = ''; });
}

export function setTransitVisible(map, visible, route = '') {
  const visibility = visible ? 'visible' : 'none';
  map.setLayoutProperty('transit-routes', 'visibility', visibility);
  map.setLayoutProperty('transit-stops', 'visibility', visibility);
  map.setFilter('transit-routes', route ? ['==', ['get', 'route'], route] : null);
  map.setFilter('transit-stops', route
    ? ['in', `|${route}|`, ['string', ['get', 'routeFilter']]]
    : null);
}

function showStop(event, map) {
  const stop = event.features?.[0]?.properties;
  if (!stop) return;
  const detail = document.createElement('div');
  const name = document.createElement('strong');
  const routes = document.createElement('p');
  name.textContent = stop.name || 'Parada';
  routes.textContent = stop.routes ? `Rutas: ${stop.routes}` : 'Parada de transporte';
  detail.append(name, routes);
  popup?.remove();
  popup = new Popup({ maxWidth: '240px' }).setLngLat(event.lngLat).setDOMContent(detail).addTo(map);
}
