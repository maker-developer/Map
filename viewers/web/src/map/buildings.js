import { buildingLayers, themes } from './style.js';

export function addBuildingLayers(map, visible = true) {
  map.addSource('buildings', {
    type: 'vector',
    url: `pmtiles://${new URL('/data/edificios.pmtiles', location.origin).href}`,
  });
  for (const layer of buildingLayers(themes.light)) map.addLayer(layer);
  map.setLayoutProperty('buildings-footprints', 'visibility', visible ? 'none' : 'visible');
  map.setLayoutProperty('buildings-volume', 'visibility', visible ? 'visible' : 'none');
}

export function setBuildingVisibility(map, show3D) {
  map.setLayoutProperty('buildings-footprints', 'visibility', show3D ? 'none' : 'visible');
  map.setLayoutProperty('buildings-volume', 'visibility', show3D ? 'visible' : 'none');
}
