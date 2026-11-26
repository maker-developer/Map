# Ronda 2 · Búsqueda

**Objetivo:** que la barra de búsqueda del mapa (iOS y web) encuentre direcciones, calles, barrios, municipios y lugares públicos de Miami-Dade, al instante y sin internet, y vuele al resultado con su ficha.

**Estado:** ⏸️ preparada; empieza cuando el dueño cierre la ronda 1.

**Límite honesto:** el condado no publica negocios (restaurantes, tiendas, cafés). Eso queda para una ronda posterior con otra fuente (OpenStreetMap u Overture Maps).

## Contrato: el índice de búsqueda

Un archivo SQLite con búsqueda de texto completo (FTS5), igual para iOS y web:

`public/data/busqueda.sqlite` (y en R2 `v3/busqueda.sqlite`)

```sql
-- Una fila por cosa que se puede encontrar.
CREATE TABLE lugares (
  id        INTEGER PRIMARY KEY,
  nombre    TEXT NOT NULL,   -- «1200 Brickell Ave», «Brickell», «Bayfront Park», «Miami Senior High»
  subtitulo TEXT NOT NULL,   -- «Miami, FL 33131», «Barrio de Miami», «Parque · Downtown»
  tipo      TEXT NOT NULL,   -- ver tabla de tipos
  lon       REAL NOT NULL,
  lat       REAL NOT NULL,
  -- Caja del lugar (para encuadrar barrios, parques o calles enteras); NULL en puntos.
  oeste REAL, sur REAL, este REAL, norte REAL,
  peso      INTEGER NOT NULL -- importancia para ordenar (mayor = antes); ver abajo
);

-- Texto normalizado para buscar: minúsculas, sin acentos, con las variantes
-- («st» y «street», «sw» y «southwest», «ave» y «avenue», «ne 2nd» y «ne 2»).
CREATE VIRTUAL TABLE lugares_fts USING fts5(texto, content='', tokenize='unicode61 remove_diacritics 2', prefix='1 2 3');
-- rowid de lugares_fts = id de lugares.
```

| `tipo` | Qué | Fuente sugerida | `peso` |
| --- | --- | --- | --- |
| `municipio` | Miami, Hialeah, Coral Gables… | límites municipales del condado | 100 |
| `barrio` | Brickell, Wynwood, Little Havana… | barrios del condado o de la ciudad de Miami | 90 |
| `estacion` | Metrorail, Metromover, Tri-Rail | GTFS (ya en `transit.pmtiles`) | 80 |
| `parque` | Bayfront Park, Tropical Park… | `parques` (ya en `base.pmtiles`) | 70 |
| `playa` | South Beach, Crandon… | `playas` (ronda 1) | 70 |
| `agua` | Biscayne Bay, Miami River… | `agua-nombres` (ronda 1) | 60 |
| `hospital`, `escuela`, `universidad`, `biblioteca`, `bomberos`, `policia` | lugares públicos | Open Data Hub del condado | 60 |
| `calle` | «SW 8th St» (una por nombre, con su caja) | `calles` | 50 |
| `direccion` | «1200 Brickell Ave» | puntos de dirección del condado | 10 |

Nombres con mayúsculas y minúsculas («SW 8th St», no «SW 8TH ST»). Tamaño objetivo: menos de 60 MB; si las direcciones lo pasan, decirlo y se descargan aparte desde R2.

## Codex (rama `codex/datos`)

- [ ] **B1. Fuentes.** Inventariar y documentar en `data/SOURCES.md` las capas del condado para municipios, barrios, puntos de dirección y lugares públicos (con licencia y fecha).
- [ ] **B2. Índice.** Generar `public/data/busqueda.sqlite` con el esquema de arriba desde `data/scripts/`, incluida la normalización de `texto` (variantes de abreviaturas y números).
- [ ] **B3. Publicar.** Subir a R2 en `v3/` (con los PMTiles de `v2/` copiados, para que `v3/` esté completa) y anotar en «Entregado» tamaños, número de filas por `tipo` y la URL.
- [ ] **B4. Compilar.** Cuando Claude marque A4, fusionar los datos en `claude/laboratorio-ios`, compilar e instalar en el iPhone.
- [ ] **B5. Web publicada.** Cuando Cursor lo pida, publicar la app web en Cloudflare Pages (con los PMTiles e índice de R2).

## Claude (rama `claude/laboratorio-ios`)

- [ ] **A1. Motor de búsqueda en iOS.** Módulo `Busqueda` con SQLite (sin dependencias): consultas por prefijo mientras se escribe, orden por coincidencia exacta, `peso` y cercanía al centro del mapa; menos de 50 ms por letra.
- [ ] **A2. Hoja de búsqueda.** Resultados en la hoja con íconos Lucide por `tipo`, búsquedas recientes, «sin resultados» útil. Al elegir: vuela al lugar (o encuadra su caja), pone un marcador y abre su ficha (nombre, tipo, dirección, coordenadas y botón «Cómo llegar», desactivado hasta la ronda 3).
- [ ] **A3. Marcador de lugar.** Pin propio (Lucide `map-pin`) en el mapa para el resultado elegido, en claro y oscuro.
- [ ] **A4. Laboratorio.** Experimento «Búsqueda» con medidas: milisegundos por consulta y número de resultados, para probar en el iPhone.
- [ ] **A5. Algoritmo compartido.** Documentar en `extras/search/README.md` cómo se ordena (exacta > prefijo, `peso`, cercanía), para que Cursor haga lo mismo en la web.

## Cursor (rama `cursor/web`)

- [ ] **W5. Búsqueda en la web.** La misma búsqueda en la hoja de la app web, con `sql.js` sobre `busqueda.sqlite` (cargado desde `public/data/` o R2 `v3/`), con el orden que documente Claude en A5. Si el índice pesa demasiado para el navegador, proponer en «Pedidos» un índice web más pequeño (sin direcciones, o por zonas) y Codex lo genera.
- [ ] **W6. Pruebas de búsqueda.** `npm run probar-busqueda`: las consultas de la lista «Probar» de abajo, con el primer resultado esperado; sale con error si alguna falla.

## Nota: experiencia de rutas ya montada en iOS

El app iOS ya tiene el flujo de búsqueda → ficha → ruta → navegación (ver `viewers/ios/README.md`), con servicios **provisionales** (Photon para buscar, OSRM de FOSSGIS para rutas). Esta ronda sustituye la búsqueda por el índice propio; las rondas 3 y 4, las rutas. El cambio en iOS se hace solo en `viewers/ios/Laboratorio/Rutas/ServiciosRuta.swift`.

- Para **Cursor:** la misma experiencia en la web (W7, opcional en esta ronda): mismas fases y pantallas; los textos de las maniobras en español están en `Rutas/ModelosRuta.swift` (`Maniobra.describir`).
- Para **Codex:** en la ronda 4, el motor propio debería responder **como OSRM** (`/route/v1/{perfil}/{lon,lat;lon,lat}?alternatives=3&steps=true&geometries=geojson&overview=full`), así el app no cambia.

## Pedidos entre los dos

- Claude → Codex: el esquema de arriba es el contrato. Si una fuente no existe o no se puede usar (licencia), decirlo aquí y se ajusta.
- Codex → Claude: rama `codex/negocios-enriquecidos` añade `data/scripts/lugares_enriquecidos.py`; genera DB separados por fuente/licencia y FTS5. Descargas públicas: [manifiesto](https://pub-031a310ad68042d59e4273a0b01a7dc1.r2.dev/places/v1/manifest.json), [Overture SQLite gzip (121 MB)](https://pub-031a310ad68042d59e4273a0b01a7dc1.r2.dev/places/v1/overture.sqlite.gz), [OSM SQLite gzip (9 MB)](https://pub-031a310ad68042d59e4273a0b01a7dc1.r2.dev/places/v1/openstreetmap.sqlite.gz). Descomprimir antes de abrir SQLite. Overture: 368.582 lugares en Miami-Dade, Broward y Monroe; tiene teléfonos/web/correo cuando la fuente los aporta, con licencia por registro. OSM: 32.880 lugares, incluye horarios, etiquetas de pagos/servicios y 18 referencias Commons con licencia y atribución verificadas. Cada fuente se mantiene separada: consultar las bases por separado y combinar resultados en runtime, sin consolidar las filas en una DB derivada que mezcle licencias. El layer Business Tracker/LocalBusinessTax del condado se excluye: sus metadatos oficiales lo restringen a uso interno y dicen que el teléfono no es público. |

## Entregado

| Quién | Qué | Dónde | Notas |
| --- | --- | --- | --- |
| | | | |

## Probar (el dueño, en el iPhone)

1. Escribe «1200 brick»: ¿sale 1200 Brickell Ave antes de terminar de escribir?
2. «wynwood», «little havana», «coral gables»: ¿vuela al barrio o municipio y lo encuadra?
3. «sw 8», «calle 8», «biscayne blvd»: ¿encuentra la calle entera?
4. «bayfront», «jackson memorial», «miami dade college»: ¿encuentra el lugar?
5. Sin internet (modo avión): ¿sigue buscando igual?
6. ¿La ficha del resultado se lee bien y el marcador se ve en claro y en oscuro?
7. En la web (móvil y escritorio): lo mismo que 1–4.
