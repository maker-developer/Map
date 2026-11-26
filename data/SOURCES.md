# Fuentes de datos

La primera versión usa capas descargadas del Open Data Hub de Miami-Dade y el límite del condado de U.S. Census TIGERweb. El mapa se dibuja con un estilo propio de MapLibre y se guarda como archivos de teselas propios.

| Datos | Fuente | Notas |
| --- | --- | --- |
| Límite del condado | [U.S. Census TIGERweb](https://tigerweb.geo.census.gov/tigerweb/) | Condado 12086 |
| Calles y nombres | [Street Network](https://services.arcgis.com/8Pc9XBTAsYuxx9Ny/arcgis/rest/services/StreetNetwork_gdb/FeatureServer/0) | Segmentos lineales y clasificación |
| Capa de calles, clase, rampas, puentes y túneles | [Metadatos oficiales MDC GeoStreets](https://gisweb.miamidade.gov/GISSelfServices/Data/HTML/GeoStreets.htm) y campos `RAMP`, `BRIDGE`, `TUNNEL`, `F_ZLEV`, `T_ZLEV` de Street Network | Véase tabla de clasificación abajo; los niveles elevados alimentan `puente` cuando los flags están vacíos |
| Número de ruta | `SNAME` de Street Network | Se conserva si el nombre incluye I/US/SR; alias locales explícitos para US-1, US-27, SR-997 y Florida Turnpike |
| Agua | [Water](https://services.arcgis.com/8Pc9XBTAsYuxx9Ny/arcgis/rest/services/Water_gdb/FeatureServer/0) | Geometrías simplificadas |
| Parques | [Municipal Park Boundary](https://services.arcgis.com/8Pc9XBTAsYuxx9Ny/arcgis/rest/services/MunicipalParkBoundary_gdb/FeatureServer/0) | Parques municipales |
| Huellas y alturas | [BuildingFootprint UBID/Folio](https://services.arcgis.com/8Pc9XBTAsYuxx9Ny/arcgis/rest/services/BuildingFootprintUBIDFolio_gdb/FeatureServer/0) | 605.762 huellas en la extracción inicial |
| Transporte opcional | [Miami-Dade Transit GTFS](https://www.miamidade.gov/global/transportation/open-data-feeds.page) | Paradas y formas estáticas del feed |

El condado indica que la mayoría de sus datos públicos de producción puede descargarse gratis desde su Open Data Hub. Las condiciones, actualidad y permisos dependen de cada conjunto. Antes de redistribuir datos, revisar los metadatos y términos de la capa que se use.

La primera versión no incorpora OpenStreetMap. Se puede añadir después como fuente de datos abierta, respetando la atribución y la ODbL. [Licencia y atribución de OpenStreetMap](https://www.openstreetmap.org/copyright/sp)

La nube LiDAR del condado de 2021 publicada por NOAA cubre 615 millas cuadradas. Puede aportar terreno y clasificación de edificios en las áreas cubiertas. [NOAA Digital Coast](https://www.fisheries.noaa.gov/inport/item/76028)

## Calles: tabla `CLASS` → `clase`

La tabla sigue la definición oficial de Miami-Dade County para `CLASS`:

| `CLASS` | Definición del condado | `clase` del mapa |
| --- | --- | --- |
| `0` | Expressway Ramp | `rampa` |
| `1` | Expressway, acceso limitado | `autopista` |
| `2` | Highway, sin acceso limitado | `avenida` |
| `3` | Major Road | `avenida` |
| `4` | Feeder Road | `colectora` |
| `5` | Minor Road | `local` |
| `6` | Alley | `servicio` |
| `7` | Non Paved | `servicio` |
| `8` | Driveway / Accessway | `servicio` |
| `9` | New Subdivision | `servicio` |

El campo `RAMP` y el nombre con sufijo `RAMP` también clasifican rampas como `rampa`; `CLASS=0` ya es suficiente para identificarlas. `puente` es verdadero cuando el condado marca `BRIDGE` o el segmento tiene `F_ZLEV`/`T_ZLEV` por encima del nivel 0 (la definición del condado los describe como niveles elevados). `tunel` usa `TUNNEL`. En la consulta actual, `BRIDGE` y `TUNNEL` llegan vacíos; por ello no se infieren túneles. `ref` se obtiene de los códigos incluidos en `SNAME` y de alias locales explícitos; queda vacío si el nombre no identifica una ruta numerada.

## Rendición del mapa

MapLibre es el motor de dibujo. No aporta calles, direcciones, fotografías, tráfico ni comercios. El proyecto obtiene las geometrías de los archivos PMTiles creados aquí y representa las capas localmente.
