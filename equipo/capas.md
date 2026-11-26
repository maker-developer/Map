# Contrato de datos

Lo que **Codex produce** en los PMTiles y **Claude usa** en el estilo. Si una capa o propiedad cambia de nombre, se cambia aquí primero y se avisa en la ronda.

Una capa que el estilo pide y todavía no existe no rompe el mapa: MapLibre simplemente no dibuja nada. Así Claude puede preparar el estilo antes de que lleguen los datos.

## Archivos

| Archivo | En el repo (`public/data/`) | En la nube (R2 `v2/`, ronda 1) |
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
| `calles` | línea | `name` (en MAYÚSCULAS), `kind` (campo CLASS del condado, ver tabla abajo) | 8+ |
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

### Qué es cada valor de `kind` (CLASS del condado)

Comprobado por Claude leyendo `base.pmtiles` (Brickell, Downtown, Miami Beach, Miami Lakes, Coral Gables, Kendall):

| `kind` | `clase` | Ejemplos |
| --- | --- | --- |
| `0` | `rampa` | I 95 RAMP, SR 826 RAMP, I 195 RAMP |
| `1` | `autopista` | I 95 EXPY, SR 826 EXPY, SR 112, Gratigny Pkwy |
| `2` | `principal` | Biscayne Blvd, Brickell Ave, SW 8th St, Alton Rd |
| `3` | `avenida` | Ponce de León Blvd, NW 7th Ave, S Miami Ave |
| `4` | `colectora` | Meridian Ave, NW 14th Ave |
| `5` | `local` | Salzedo St, Galiano St |
| `6`, `7`, `8` | `servicio` | callejones, privadas (Lenox Ct, Riverfront Aly) |
| `9` | `peatonal` | Lincoln Rd |

**Esta es la tabla única** (acordada tras la revisión de Cursor). El estilo la aplica así, en web e iOS:
1. `rampa` si el dato trae `clase = rampa` (Codex la detecta mejor: CLASS 0, campo RAMP o « RAMP» en el nombre);
2. si no, por `kind` con la tabla de arriba;
3. sin `kind`, la `clase` del dato (o `local`).

Pedido a Codex: que `clase` siga esta misma tabla (hoy CLASS 2 sale `avenida` y CLASS 9 `servicio`), para que el índice de búsqueda y cualquier otro uso digan lo mismo que el mapa.

### `calles`: propiedades nuevas (se mantienen `name` y `kind`)

| Propiedad | Valores | Notas |
| --- | --- | --- |
| `clase` | `autopista`, `rampa`, `principal`, `avenida`, `colectora`, `local`, `servicio`, `peatonal` | Según la tabla de arriba. Si algún CLASS no encaja, decirlo en la ronda. |
| `puente` | `true`/`false` | Si el condado lo marca (o por cruce con agua). |
| `tunel` | `true`/`false` | Si existe en la fuente (p. ej. el túnel del puerto). |
| `ref` | `I-95`, `I-195`, `US-1`, `US-41`, `SR-836`, `SR-112`, `Turnpike`… | Número de la vía, para los escudos. Se puede sacar del nombre («I 95 EXPY» → `I-95`). Vacío si no tiene. |
| `red` | `I`, `US`, `SR`, `TP` | Tipo de escudo: interestatal, federal, estatal, Turnpike. Elige la imagen `escudo-<red>`. |
| `name` | «SW 8th St», «Brickell Ave» | **Con mayúsculas y minúsculas**, no todo en mayúsculas (hoy viene «SW 8TH ST»). Puntos cardinales en mayúscula (NE, SW…) y ordinales en minúscula («8th»). |

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
