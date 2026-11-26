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
| Playas | [Beachpoly](https://services.arcgis.com/8Pc9XBTAsYuxx9Ny/arcgis/rest/services/Beachpoly_gdb/FeatureServer/0) | Polígonos oficiales con `NAME`; 19 entidades en la consulta de ronda 1; geometría simplificada antes de teselar |
| Profundidad costera | [NOAA/NCEI Coastal Relief Model, vol. 3, Florida and East Gulf (2023)](https://www.ncei.noaa.gov/products/coastal-relief-model) · [THREDDS NetCDF](https://www.ngdc.noaa.gov/thredds/dodsC/crm/cudem/crm_vol3_2023.nc) | Elevación en metros, resolución de 1 segundo de arco; se usa solo la parte marina bajo 0 m, se convierte a bandas de profundidad y simplifica con tolerancia aproximada de 200 m. No sirve para navegación. |
| Huellas y alturas | [BuildingFootprint UBID/Folio](https://services.arcgis.com/8Pc9XBTAsYuxx9Ny/arcgis/rest/services/BuildingFootprintUBIDFolio_gdb/FeatureServer/0) | 605.762 huellas en la extracción inicial |
| Transporte opcional | [Miami-Dade Transit GTFS](https://www.miamidade.gov/global/transportation/open-data-feeds.page) | Paradas y formas estáticas del feed |

El condado indica que la mayoría de sus datos públicos de producción puede descargarse gratis desde su Open Data Hub. Las condiciones, actualidad y permisos dependen de cada conjunto. Antes de redistribuir datos, revisar los metadatos y términos de la capa que se use.

Los ejes hidrográficos nombrados y los centros de lagos nombrados complementan las masas de agua del condado con [OpenStreetMap](https://www.openstreetmap.org/copyright/sp). Los datos se distribuyen bajo ODbL; la atribución del mapa debe incluir «© OpenStreetMap contributors» y el enlace de copyright.

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

La capa `profundidad` cubre el condado y la plataforma costera inmediata (25.18–26.05° N, 81.00–79.65° W). El recorte retiene valores NOAA menores que el nivel 0 y asigna la profundidad como el negativo de la elevación a las bandas `0-1`, `1-2`, `2-5`, `5-10` y `10+`. Los polígonos se simplifican preservando topología; el pipeline aborta si el resultado requiere los datos NOAA y faltan las dependencias de `data/requirements.txt`.

Los nombres de Biscayne Bay y Atlantic Ocean se colocan en puntos de etiqueta; los lagos nombrados proceden del centro de sus polígonos de OpenStreetMap. Las líneas `agua-ejes` agrupan vías OSM llamadas Miami River (incluidos sus brazos), Little River Canal, Snake Creek Canal y Atlantic Intracoastal Waterway bajo los nombres del contrato del mapa. Las fuentes del condado no suministran esos nombres en sus capas de agua/stream.

## Rendición del mapa

MapLibre es el motor de dibujo. No aporta calles, direcciones, fotografías, tráfico ni comercios. El proyecto obtiene las geometrías de los archivos PMTiles creados aquí y representa las capas localmente.
