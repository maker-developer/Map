// Paleta clara. Ronda 1: blanco cálido, agua celeste, parques verde fresco, calles grises con
// borde claro (como aceras), torres en grises y casas en pasteles variados.
export const light = {
  background: '#eceeec',
  land: '#f8f8f3',
  park: '#b4dd90',
  parkOutline: '#a2d27c',
  water: '#9cd4f1',
  waterOutline: '#8cc8e8',
  boundary: '#9aa3a6',
  street: '#ffffff',
  mainStreet: '#ffffff',
  mainStreetCasing: '#c9cbcb',
  streetLabel: '#7d8486',
  cityLabel: '#3b4245',
  halo: '#f8f8f3',
  building: '#e6e5e1',
  buildingOutline: '#cfcfcb',
  // Torres por altura: grises claros (el techo sale más claro que las paredes con la luz).
  buildingLow: '#e9e8e4',
  buildingMid: '#dcdddb',
  buildingHigh: '#d1d3d2',
  // Casas (menos de 12 m): un pastel distinto por edificio (rosa, melocotón, crema, menta, piedra, lavanda).
  casas: ['#f6e6e2', '#f6eadb', '#f5f0dc', '#d9e9e5', '#e5e1da', '#e4e5f0'],
  // Ronda 1 (equipo/ronda-01.md): calles con jerarquía, arena y agua por profundidad.
  ronda1: {
    autopista: '#f9d57c', autopistaBorde: '#e4b456',
    principal: '#b3b8bb', principalBorde: '#fbfbf9',
    avenida: '#bec2c5', avenidaBorde: '#fbfbf9',
    local: '#c9ccce', localBorde: '#fbfbf9',
    servicio: '#d8dadb', peatonal: '#e9dcc9', puenteSombra: '#3d4a52',
    arena: '#f6edd1', arenaBorde: '#ece0bc',
    profundidad: ['#bde5f7', '#aedcf4', '#9cd4f1', '#8bcaec', '#79bfe6'],
    aguaTexto: '#4b88ab', aguaHalo: '#c9e9f8',
  },
};
