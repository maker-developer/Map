# Contrato de datos

Lo que **Codex produce** en los PMTiles y **Claude usa** en el estilo. Si una capa o propiedad cambia de nombre, se cambia aquí primero y se avisa en la ronda.

Una capa que el estilo pide y todavía no existe no rompe el mapa: MapLibre simplemente no dibuja nada. Así Claude puede preparar el estilo antes de que lleguen los datos.

## Archivos

| Archivo | En el repo (`public/data/`) | En la nube (R2 `v1/`) |
| --- | --- | --- |
| Mapa base | `base.pmtiles` | `base.pmtiles` |
| Edificios | `edificios.pmtiles` | `buildings.pmtiles` |
| Transporte | `transit.pmtiles` | `transit.pmtiles` |

Al regenerar, Codex sube a una carpeta nueva de R2 (`v2/`, `v3/`…) y no pisa la anterior, para que el app publicado no se rompa. Claude cambia `MapNubeURL` cuando la nueva esté probada.

## Hoy (ronda 0)

### `base.pmtiles`

| Capa | Geometría | Propiedades | Zoom |
| --- | --- | --- | --- |
| `condado` | polígono | — | 7+ |
| `calles` | línea | `name`, `kind` (campo CLASS del condado: `0`–`3` principales) | 8+ |
| `agua` | polígono | `name` | 7+ |
| `parques` | polígono | `name` | 9+ |

### `edificios.pmtiles`

| Capa | Geometría | Propiedades | Zoom |
| --- | --- | --- | --- |
| `edificios` | polígono | `height` (m, o null), `address` | 13–16 |

### `transit.pmtiles`

| Capa | Geometría | Propiedades | Zoom |
| --- | --- | --- | --- |
| `paradas` | punto | `id`, `name`, `routes`, `routeFilter`, `rail` | 13+ |
| `rutas` | línea | `route`, `name`, `color`, `rail` | 10+ |

## Pedido para la ronda 1 (Codex)

### `calles`: propiedades nuevas (se mantienen `name` y `kind`)

| Propiedad | Valores | Notas |
| --- | --- | --- |
| `clase` | `autopista`, `rampa`, `avenida`, `colectora`, `local`, `servicio` | Traducción de CLASS del condado. Documentar la tabla CLASS → clase en `data/SOURCES.md`. |
| `puente` | `true`/`false` | Si el condado lo marca (o por cruce con agua). |
| `tunel` | `true`/`false` | Si existe en la fuente. |
| `ref` | p. ej. `I-95`, `US-1`, `SR-836`, `FL Turnpike` | Número de la vía, para escudos. Vacío si no tiene. |

### `playas` (capa nueva en `base.pmtiles`)

| Geometría | Propiedades | Zoom |
| --- | --- | --- |
| polígono | `name` | 9+ |

Fuente sugerida: capa de playas o de uso del suelo del condado. Si no hay, arena desde la línea de costa (franja entre `agua` y tierra en la costa atlántica). Documentar.

### `profundidad` (capa nueva en `base.pmtiles`)

| Geometría | Propiedades | Zoom |
| --- | --- | --- |
| polígono | `banda`: `0-1`, `1-2`, `2-5`, `5-10`, `10+` (metros) | 7+ |

Fuente: batimetría de NOAA (Biscayne Bay y costa). Polígonos por banda, simplificados.

### `agua`: nombres

Que `name` venga relleno al menos en: Biscayne Bay, Atlantic Ocean, Miami River, Intracoastal Waterway, Little River, Snake Creek, lagos grandes. Si la fuente no lo trae, una capa de puntos `agua-nombres` con `name` y, para ríos, líneas `agua-ejes` con `name` (para el texto curvo).
