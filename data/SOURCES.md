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
| Profundidad costera | [NOAA/NCEI Coastal Relief Model, vol. 3, Florida and East Gulf (2023)](https://www.ncei.noaa.gov/products/coastal-relief-model) · [THREDDS NetCDF](https://www.ngdc.noaa.gov/thredds/dodsC/crm/cudem/crm_vol3_2023.nc) | Elevación en metros a 1 segundo de arco; el campo marino se suaviza con filtro gaussiano (sigma 1,25 celdas, unos 35 m), se convierte a bandas y se recorta a los polígonos `agua` de Miami-Dade para excluir tierra y muelles. Simplificación final de unos 45 m seguida de un segundo recorte al agua. No sirve para navegación. |
| Huellas y alturas | [BuildingFootprint UBID/Folio](https://services.arcgis.com/8Pc9XBTAsYuxx9Ny/arcgis/rest/services/BuildingFootprintUBIDFolio_gdb/FeatureServer/0) | 605.762 huellas en la extracción inicial |
| Transporte opcional | [Miami-Dade Transit GTFS](https://www.miamidade.gov/global/transportation/open-data-feeds.page) | Paradas y formas estáticas del feed |
| Límites de velocidad | [FDOT Maximum Speed Limits (RCI Feature 311, MAXSPEED)](https://www.arcgis.com/home/item.html?id=4a61f17ab4784202ae10d7d5fb3bf9de) | `SPEED` explícita en mph; extracción de 1.652 tramos (Miami-Dade 1.109, Broward 335, Monroe 208), servicio actualizado el 2026-11-23. El inventario cubre vías designadas del SHS y muestras HPMS, no todas las calles locales; FDOT advierte que puede no reflejar condiciones actuales. Los 1.652 tramos completos están en `limites-velocidad.pmtiles`; los que coinciden estrictamente con las calles actuales llevan `vmax` dentro de `base.pmtiles` → `calles`. |
| Nombre lineal de vías FDOT | [Roadways with Local Name (RCI Feature 114, LOCALNAM)](https://services1.arcgis.com/O1JpcwDW8sjYuddV/ArcGIS/rest/services/Roadways_With_Local_Name_TDA/FeatureServer/0) | `ROADWAY`, `NAME`, `BEGIN_POST`, `END_POST` asocian nombre oficial y rango de millas para evitar unir límites por geometría sola. El inventario también puede no reflejar condiciones actuales. |

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

La capa `profundidad` cubre el condado y la plataforma costera inmediata (25.18–26.05° N, 81.00–79.65° W). El recorte retiene valores NOAA menores que el nivel 0 y asigna la profundidad como el negativo de la elevación a las bandas `0-1`, `1-2`, `2-5`, `5-10` y `10+`. La rejilla se suaviza antes de extraer contornos; luego cada banda se intersecta con `agua`, se simplifica preservando topología y se vuelve a intersectar para mantener la costa, incluidos muelles, como límite. El pipeline aborta si faltan las dependencias de `data/requirements.txt`.

Los nombres de Biscayne Bay y Atlantic Ocean se colocan en puntos de etiqueta; los lagos nombrados proceden del centro de sus polígonos de OpenStreetMap. Las líneas `agua-ejes` agrupan vías OSM llamadas Miami River (incluidos sus brazos), Little River Canal, Snake Creek Canal y Atlantic Intracoastal Waterway bajo los nombres del contrato del mapa. Las fuentes del condado no suministran esos nombres en sus capas de agua/stream.

## Límites de velocidad publicados

`data/scripts/velocidades.py` descarga el feature service oficial de FDOT, filtra por `COUNTY` en Miami-Dade, Broward y Monroe, y exige que cada tramo tenga geometría y un `SPEED` entero reconocido (5–70 mph en incrementos de 5). Si falta un límite, la descarga aborta en vez de completar o inferir el valor. Se preservan el identificador FDOT, `ROADWAY`, lado, dirección de offset y puntos de milla. La salida íntegra se almacena en `public/data/limites-velocidad.pmtiles`; `public/data/manifest.json` y `limites-velocidad-manifest.json` registran conteos y fecha de actualización.

Para la burbuja de navegación, `preparar.py` añade la propiedad numérica `vmax` (mph) a los segmentos de `calles` en `base.pmtiles`. El cruce requiere el mismo identificador `ROADWAY`, rango de millas coincidente con el nombre oficial `LOCALNAM`, nombre normalizado igual al de Street Network, distancia máxima de 5 m, cobertura del segmento de calle ≥95% y diferencia de rumbo ≤15°. Si varias velocidades explícitas coinciden con un segmento, se guarda la menor. En la extracción inicial, 643 tramos FDOT se pudieron asociar a 4.256 de las 116.465 geometrías de calles de Miami-Dade. Los datos de Broward y Monroe permanecen completos en el PMTiles auxiliar, pero no se copian a `calles` porque esta capa local todavía no cubre esos condados.

Estos datos son un inventario oficial publicado, no una lectura en tiempo real de las señales ni una garantía de que la señalización no haya cambiado. FDOT indica que MAXSPEED procede del RCI Feature 311 y que es requerido para las vías designadas del SHS y las muestras HPMS; el servicio no cubre necesariamente cada calle residencial o local. Por ello, ausencia de un tramo significa “sin dato confirmado en esta fuente”, nunca un límite supuesto. Mantener la fecha de actualización y atribución FDOT cuando se muestre o redistribuya.

Fuentes: [FDOT Maximum Speed Limits](https://services1.arcgis.com/O1JpcwDW8sjYuddV/ArcGIS/rest/services/Maximum_Speed_Limit_TDA/FeatureServer/0), [FDOT Roadways with Local Name](https://services1.arcgis.com/O1JpcwDW8sjYuddV/ArcGIS/rest/services/Roadways_With_Local_Name_TDA/FeatureServer/0), [metadatos del conjunto de velocidades](https://www.arcgis.com/sharing/rest/content/items/4a61f17ab4784202ae10d7d5fb3bf9de/info/metadata/metadata.xml?format=default), [alcance del Roadway Characteristics Inventory](https://www.fdot.gov/statistics/hwydata/default.shtm), [condiciones y actualización semanal de datos GIS FDOT](https://www.fdot.gov/statistics/gis/default.shtm).

## Rendición del mapa

MapLibre es el motor de dibujo. No aporta calles, direcciones, fotografías, tráfico ni comercios. El proyecto obtiene las geometrías de los archivos PMTiles creados aquí y representa las capas localmente.
