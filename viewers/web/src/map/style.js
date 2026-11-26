import { light } from '../../../../styles/base-light.js';
import { dark } from '../../../../styles/base-dark.js';

// El mismo estilo está en el app iOS (viewers/ios/Laboratorio/Mapa/EstiloMapa.swift y EstiloRonda1.swift).
// Ronda 1 (equipo/ronda-01.md): calles con jerarquía, puentes, túneles, escudos, arena,
// la bahía por profundidad y los nombres del agua. Las capas que Codex aún no entrega
// (playas, profundidad, agua-nombres, agua-ejes) no se dibujan hasta que existan.

const fuente = name => new URL(`../../../../styles/fonts/${name}.ttf`, import.meta.url).href;
const lineLayout = { 'line-cap': 'round', 'line-join': 'round' };

export const themes = { light, dark };

// Clase de la vía: `clase` de Codex o, mientras no llegue, el CLASS del condado (`kind`).
// kind: 0 rampa · 1 autopista · 2 principal · 3 avenida · 4 colectora · 5 local · 6–8 servicio · 9 peatonal.
export const clase = ['coalesce', ['get', 'clase'],
  ['match', ['get', 'kind'],
    '0', 'rampa', '1', 'autopista', '2', 'principal', '3', 'avenida',
    '4', 'colectora', '5', 'local', '9', 'peatonal', 'servicio']];

const esClase = valores => ['in', clase, ['literal', valores]];

// Tipo de escudo: `red` de Codex o, si no viene, deducido del número de la vía.
const red = ['coalesce', ['get', 'red'], ['match', ['coalesce', ['get', 'ref'], ''],
  ['I-75', 'I-95', 'I-195', 'I-395', 'I-595'], 'I',
  ['US-1', 'US-27', 'US-41', 'US-441'], 'US',
  ['Turnpike', 'FL Turnpike', 'HEFT'], 'TP',
  '', 'otro', 'SR']];
const noTunel = ['!=', ['get', 'tunel'], true];
const noPuente = ['!=', ['get', 'puente'], true];
const esPuente = ['==', ['get', 'puente'], true];

// Ancho en píxeles por zoom: crece 1,6× por nivel; desde el zoom 18 se acerca al ancho real.
const anchos = {
  autopista: [[7, .8], [10, 1.6], [13, 3.6], [15, 7], [17, 15], [18, 26], [20, 90]],
  rampa: [[11, .6], [13, 1.6], [15, 3.4], [17, 8], [18, 13], [20, 46]],
  principal: [[8, .6], [11, 1.2], [13, 2.6], [15, 5.4], [17, 12], [18, 20], [20, 72]],
  avenida: [[10, .5], [12, .9], [14, 2.4], [16, 5.6], [17, 9], [18, 16], [20, 58]],
  colectora: [[11, .4], [13, .8], [15, 2.6], [17, 7], [18, 12], [20, 42]],
  local: [[12, .3], [14, .9], [16, 3], [17, 5.4], [18, 9.5], [20, 34]],
  servicio: [[14, .4], [16, 1.6], [18, 5], [20, 16]],
  peatonal: [[14, .6], [16, 2.2], [18, 6.5], [20, 22]],
};

function ancho(paradas, extra = 0) {
  return ['interpolate', ['exponential', 1.6], ['zoom'],
    ...paradas.flatMap(([zoom, px]) => [zoom, px + extra * (zoom >= 17 ? 1.6 : 1)])];
}

function colores(nombre, r) {
  switch (nombre) {
    case 'autopista': case 'rampa': return [r.autopista, r.autopistaBorde];
    case 'principal': return [r.principal, r.principalBorde];
    case 'avenida': case 'colectora': return [r.avenida, r.avenidaBorde];
    case 'local': return [r.local, r.localBorde];
    default: return [r.servicio, null];
  }
}

function via(nombre, r, filter, sufijo = '') {
  const paradas = anchos[nombre];
  const [relleno, borde] = colores(nombre, r);
  const minzoom = paradas[0][0];
  const capas = [];
  if (borde) {
    capas.push({ id: `via-${nombre}-borde${sufijo}`, type: 'line', source: 'base', 'source-layer': 'calles',
      minzoom: Math.max(minzoom, nombre === 'local' ? 14 : 9), filter, layout: lineLayout,
      paint: { 'line-color': borde, 'line-width': ancho(paradas, nombre === 'autopista' ? 2.2 : 1.6) } });
  }
  capas.push({ id: `via-${nombre}${sufijo}`, type: 'line', source: 'base', 'source-layer': 'calles',
    minzoom, filter, layout: lineLayout,
    paint: { 'line-color': relleno, 'line-width': ancho(paradas) } });
  return capas;
}

function calles(r) {
  const tuneles = ['==', ['get', 'tunel'], true];
  return [
    // Túneles: debajo de todo, punteados y apagados.
    { id: 'tuneles-borde', type: 'line', source: 'base', 'source-layer': 'calles', minzoom: 12, filter: tuneles,
      layout: { 'line-cap': 'butt', 'line-join': 'round' },
      paint: { 'line-color': r.autopistaBorde, 'line-opacity': .6, 'line-dasharray': [1.5, 1],
        'line-width': ancho(anchos.principal, 1.6) } },
    { id: 'tuneles', type: 'line', source: 'base', 'source-layer': 'calles', minzoom: 12, filter: tuneles,
      layout: lineLayout, paint: { 'line-color': r.local, 'line-opacity': .55, 'line-width': ancho(anchos.principal) } },
    // De menos a más importante: las vías grandes quedan encima en los cruces.
    ...['servicio', 'local', 'colectora', 'avenida', 'principal', 'rampa', 'autopista']
      .flatMap(nombre => via(nombre, r, ['all', esClase([nombre]), noTunel, noPuente])),
    { id: 'via-peatonal', type: 'line', source: 'base', 'source-layer': 'calles', minzoom: 14,
      filter: ['all', esClase(['peatonal']), noTunel], layout: { 'line-cap': 'butt', 'line-join': 'round' },
      paint: { 'line-color': r.peatonal, 'line-width': ancho(anchos.peatonal), 'line-dasharray': [1.2, .8] } },
    // Puentes: encima, con una sombra suave que los levanta del agua.
    { id: 'puentes-sombra', type: 'line', source: 'base', 'source-layer': 'calles', minzoom: 13, filter: esPuente,
      layout: lineLayout,
      paint: { 'line-color': r.puenteSombra, 'line-opacity': .18, 'line-blur': 3, 'line-translate': [0, 2],
        'line-width': ancho(anchos.principal, 5) } },
    ...['local', 'colectora', 'avenida', 'principal', 'rampa', 'autopista']
      .flatMap(nombre => via(nombre, r, ['all', esClase([nombre]), esPuente], '-puente')),
  ];
}

function nombres(p, r) {
  const tamanoAgua = ['interpolate', ['linear'], ['zoom'], 9, 11, 13, 14, 16, 17];
  const textoAgua = { 'text-color': r.aguaTexto, 'text-halo-color': r.aguaHalo, 'text-halo-width': 1.2 };
  const grande = ['autopista', 'principal'];
  return [
    { id: 'street-names', type: 'symbol', source: 'base', 'source-layer': 'calles', minzoom: 13.5,
      filter: ['all', ['!=', ['get', 'name'], ''], ['!', esClase(['rampa', 'servicio'])]],
      layout: { 'symbol-placement': 'line', 'symbol-spacing': 220, 'text-field': ['get', 'name'],
        'text-font': ['match', clase, grande, ['literal', ['DMSans-SemiBold']], ['literal', ['DMSans-Regular']]],
        'text-max-angle': 35, 'text-transform': 'uppercase', 'text-letter-spacing': .06,
        'symbol-sort-key': ['match', clase, 'autopista', 1, 'principal', 2, 'avenida', 3, 'colectora', 4, 5],
        'text-size': ['interpolate', ['linear'], ['zoom'],
          13.5, ['match', clase, grande, 10.5, 9.5], 18, ['match', clase, grande, 14, 12.5]] },
      paint: { 'text-color': p.streetLabel, 'text-halo-color': p.halo, 'text-halo-width': 1.4 } },
    { id: 'escudos', type: 'symbol', source: 'base', 'source-layer': 'calles', minzoom: 9,
      filter: ['all', ['has', 'ref'], ['!=', ['get', 'ref'], ''], esClase(['autopista', 'principal'])],
      layout: { 'symbol-placement': 'line', 'symbol-spacing': ['interpolate', ['linear'], ['zoom'], 9, 260, 15, 520],
        'icon-image': ['concat', 'escudo-', red],
        'icon-text-fit': 'both', 'icon-text-fit-padding': [2, 5, 2, 5],
        'icon-rotation-alignment': 'viewport', 'text-rotation-alignment': 'viewport',
        'text-field': ['get', 'ref'], 'text-font': ['literal', ['DMSans-SemiBold']], 'text-size': 10.5,
        'symbol-sort-key': 0 },
      paint: { 'text-color': ['match', red, ['I', 'TP'], '#ffffff', '#1d2421'] } },
    { id: 'agua-ejes', type: 'symbol', source: 'base', 'source-layer': 'agua-ejes', minzoom: 12,
      layout: { 'symbol-placement': 'line', 'symbol-spacing': 320, 'text-field': ['get', 'name'],
        'text-font': ['literal', ['DMSans-Italic']], 'text-size': tamanoAgua, 'text-letter-spacing': .08, 'text-max-angle': 30 },
      paint: textoAgua },
    { id: 'agua-nombres', type: 'symbol', source: 'base', 'source-layer': 'agua-nombres', minzoom: 8,
      layout: { 'text-field': ['get', 'name'], 'text-font': ['literal', ['DMSans-Italic']], 'text-size': tamanoAgua,
        'text-letter-spacing': .12, 'text-max-width': 7 },
      paint: textoAgua },
    { id: 'agua-poligonos-nombres', type: 'symbol', source: 'base', 'source-layer': 'agua', minzoom: 14,
      filter: ['!=', ['coalesce', ['get', 'name'], ''], ''],
      layout: { 'text-field': ['get', 'name'], 'text-font': ['literal', ['DMSans-Italic']], 'text-size': 12,
        'text-letter-spacing': .06, 'text-max-width': 7 },
      paint: textoAgua },
  ];
}

export function baseStyle(theme) {
  const p = themes[theme];
  const r = p.ronda1;
  return {
    version: 8,
    'font-faces': {
      'DMSans-Regular': [{ url: fuente('DMSans-Regular') }],
      'DMSans-SemiBold': [{ url: fuente('DMSans-SemiBold') }],
      'DMSans-Italic': [{ url: fuente('DMSans-Italic') }],
    },
    // Luz blanca neutra: las torres se ven grises (con luz cálida salían beige).
    light: { anchor: 'map', intensity: .38, color: '#ffffff', position: [1.15, 210, 35] },
    sources: {
      base: { type: 'vector', url: 'pmtiles:///data/base.pmtiles' },
      towns: { type: 'geojson', data: townLocations },
    },
    layers: [
      { id: 'background', type: 'background', paint: { 'background-color': p.background } },
      { id: 'land', source: 'base', 'source-layer': 'condado', type: 'fill', paint: { 'fill-color': p.land } },
      { id: 'playas', source: 'base', 'source-layer': 'playas', type: 'fill', minzoom: 9,
        paint: { 'fill-color': r.arena, 'fill-outline-color': r.arenaBorde } },
      { id: 'parks', source: 'base', 'source-layer': 'parques', type: 'fill',
        paint: { 'fill-color': p.park, 'fill-outline-color': p.parkOutline } },
      { id: 'water', source: 'base', 'source-layer': 'agua', type: 'fill',
        // Turquesa intermedio de base: la capa «profundidad» pinta encima lo claro y lo hondo.
        paint: { 'fill-color': r.profundidad[2], 'fill-outline-color': p.waterOutline } },
      { id: 'profundidad', source: 'base', 'source-layer': 'profundidad', type: 'fill',
        paint: { 'fill-antialias': false, 'fill-color': ['match', ['get', 'banda'],
          '0-1', r.profundidad[0], '1-2', r.profundidad[1], '2-5', r.profundidad[2], '5-10', r.profundidad[3],
          r.profundidad[4]] } },
      { id: 'county-line', source: 'base', 'source-layer': 'condado', type: 'line', maxzoom: 12,
        paint: { 'line-color': p.boundary, 'line-width': 1.1, 'line-dasharray': [3, 2] } },
      ...calles(r),
      ...nombres(p, r),
      { id: 'towns', source: 'towns', type: 'symbol', minzoom: 8, maxzoom: 14,
        layout: { 'text-field': ['get', 'name'], 'text-font': ['literal', ['DMSans-SemiBold']], 'text-size': 14 },
        paint: { 'text-color': p.cityLabel, 'text-halo-color': p.halo, 'text-halo-width': 1.8 } },
    ],
  };
}

/// Cambia el tema conservando las capas que se añaden aparte (edificios y transporte):
/// se carga el estilo nuevo y se vuelven a poner esas capas, con los colores del tema.
export function applyTheme(map, theme) {
  const palette = themes[theme];
  map.setStyle(baseStyle(theme), {
    diff: false,
    transformStyle: (previous, next) => {
      if (!previous) return next;
      const extras = previous.layers.filter(layer => layer.source === 'buildings' || layer.source === 'transit');
      const recolored = extras.map(layer => {
        if (layer.id === 'buildings-footprints') {
          return { ...layer, paint: { ...layer.paint, 'fill-color': footprintColor(palette), 'fill-outline-color': palette.buildingOutline } };
        }
        if (layer.id === 'buildings-volume') {
          return { ...layer, paint: { ...layer.paint, 'fill-extrusion-color': buildingColor(palette) } };
        }
        return layer;
      });
      const towns = next.layers.findIndex(layer => layer.id === 'towns');
      const sources = { ...next.sources };
      for (const id of ['buildings', 'transit']) if (previous.sources[id]) sources[id] = previous.sources[id];
      return { ...next, sources, layers: [...next.layers.slice(0, towns), ...recolored, ...next.layers.slice(towns)] };
    },
  });
}

/// Escudos de autopista dibujados en un canvas, estirables (MapLibre `icon-text-fit`).
/// Se añaden cuando el mapa los pide, así sobreviven a los cambios de tema.
export function addShieldImages(map) {
  const disenos = {
    'escudo-I': ['#1f4d9e', '#ffffff', 6],
    'escudo-US': ['#ffffff', '#1f1f1f', 4],
    'escudo-SR': ['#ffffff', '#2e6b4c', 3],
    'escudo-TP': ['#297850', '#ffffff', 6],
    'escudo-otro': ['#f5f5f5', '#737373', 4],
  };
  map.on('styleimagemissing', event => {
    const diseno = disenos[event.id];
    if (!diseno || map.hasImage(event.id)) return;
    const [relleno, borde, radio] = diseno;
    const escala = 2, w = 24 * escala, h = 18 * escala;
    const canvas = document.createElement('canvas');
    canvas.width = w; canvas.height = h;
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = relleno; ctx.strokeStyle = borde; ctx.lineWidth = 1.5 * escala;
    ctx.beginPath();
    ctx.roundRect(escala, escala, w - 2 * escala, h - 2 * escala, radio * escala);
    ctx.fill(); ctx.stroke();
    map.addImage(event.id, ctx.getImageData(0, 0, w, h), {
      pixelRatio: escala,
      stretchX: [[8 * escala, w - 8 * escala]],
      stretchY: [[7 * escala, h - 7 * escala]],
      content: [5 * escala, 3 * escala, w - 5 * escala, h - 3 * escala],
    });
  });
}

export function buildingLayers(palette) {
  const color = buildingColor(palette);
  return [
    { id: 'buildings-footprints', source: 'buildings', 'source-layer': 'edificios', type: 'fill', minzoom: 13,
      paint: { 'fill-color': footprintColor(palette), 'fill-outline-color': palette.buildingOutline } },
    { id: 'buildings-volume', source: 'buildings', 'source-layer': 'edificios', type: 'fill-extrusion', minzoom: 13,
      filter: ['!=', ['get', 'height'], null],
      paint: { 'fill-extrusion-height': ['get', 'height'], 'fill-extrusion-color': color,
        'fill-extrusion-base': 0, 'fill-extrusion-vertical-gradient': true } },
  ];
}

// Torres en grises según la altura; casas (menos de 12 m) en uno de seis pasteles.
// El decimal de la altura elige el pastel: cada casa sale de un color distinto, pero siempre el mismo.
function buildingColor(palette) {
  const altura = ['coalesce', ['get', 'height'], 0];
  const torres = ['interpolate', ['linear'], altura,
    0, palette.buildingLow, 20, palette.buildingLow, 60, palette.buildingMid, 150, palette.buildingHigh];
  if (!palette.casas) return torres;
  return ['case', ['<', altura, 12], pastel(palette, ['*', altura, 10]), torres];
}

// Uno de los pasteles de `palette.casas` a partir de un número (altura o largo de la dirección).
function pastel(palette, numero) {
  const indice = ['%', ['round', numero], palette.casas.length];
  return ['match', indice, ...palette.casas.flatMap((color, i) => [i, color]), palette.casas[0]];
}

// Huellas sin altura (en planta): pastel según el largo de la dirección.
function footprintColor(palette) {
  if (!palette.casas) return palette.building;
  return pastel(palette, ['length', ['coalesce', ['get', 'address'], '']]);
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
