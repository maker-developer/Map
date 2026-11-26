import { buildingLayers, themes } from './style.js';

export function addBuildingLayers(map, visible = true) {
  map.addSource('buildings', {
    type: 'vector',
    url: `pmtiles://${new URL('/data/edificios.pmtiles', location.origin).href}`,
  });
  // Debajo de los nombres de municipios y encima de calles, rutas y paradas: los edificios
  // tapan lo que queda detrás (como «Los edificios tapan» del app iOS).
  const palette = themes[document.documentElement.dataset.theme] ?? themes.light;
  for (const layer of buildingLayers(palette)) map.addLayer(layer, 'towns');
  map.setLayoutProperty('buildings-footprints', 'visibility', visible ? 'none' : 'visible');
  map.setLayoutProperty('buildings-volume', 'visibility', visible ? 'visible' : 'none');
}

export function setBuildingVisibility(map, show3D) {
  map.setLayoutProperty('buildings-footprints', 'visibility', show3D ? 'none' : 'visible');
  map.setLayoutProperty('buildings-volume', 'visibility', show3D ? 'visible' : 'none');
}
