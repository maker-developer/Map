# Fuentes de datos

La primera versión usa capas descargadas del Open Data Hub de Miami-Dade y el límite del condado de U.S. Census TIGERweb. El mapa se dibuja con un estilo propio de MapLibre y se guarda como archivos de teselas propios.

| Datos | Fuente | Notas |
| --- | --- | --- |
| Límite del condado | [U.S. Census TIGERweb](https://tigerweb.geo.census.gov/tigerweb/) | Condado 12086 |
| Calles y nombres | [Street Network](https://services.arcgis.com/8Pc9XBTAsYuxx9Ny/arcgis/rest/services/StreetNetwork_gdb/FeatureServer/0) | Segmentos lineales y clasificación |
| Agua | [Water](https://services.arcgis.com/8Pc9XBTAsYuxx9Ny/arcgis/rest/services/Water_gdb/FeatureServer/0) | Geometrías simplificadas |
| Parques | [Municipal Park Boundary](https://services.arcgis.com/8Pc9XBTAsYuxx9Ny/arcgis/rest/services/MunicipalParkBoundary_gdb/FeatureServer/0) | Parques municipales |
| Huellas y alturas | [BuildingFootprint UBID/Folio](https://services.arcgis.com/8Pc9XBTAsYuxx9Ny/arcgis/rest/services/BuildingFootprintUBIDFolio_gdb/FeatureServer/0) | 605.762 huellas en la extracción inicial |
| Transporte opcional | [Miami-Dade Transit GTFS](https://www.miamidade.gov/global/transportation/open-data-feeds.page) | Paradas y formas estáticas del feed |

El condado indica que la mayoría de sus datos públicos de producción puede descargarse gratis desde su Open Data Hub. Las condiciones, actualidad y permisos dependen de cada conjunto. Antes de redistribuir datos, revisar los metadatos y términos de la capa que se use.

La primera versión no incorpora OpenStreetMap. Se puede añadir después como fuente de datos abierta, respetando la atribución y la ODbL. [Licencia y atribución de OpenStreetMap](https://www.openstreetmap.org/copyright/sp)

La nube LiDAR del condado de 2021 publicada por NOAA cubre 615 millas cuadradas. Puede aportar terreno y clasificación de edificios en las áreas cubiertas. [NOAA Digital Coast](https://www.fisheries.noaa.gov/inport/item/76028)

## Rendición del mapa

MapLibre es el motor de dibujo. No aporta calles, direcciones, fotografías, tráfico ni comercios. El proyecto obtiene las geometrías de los archivos PMTiles creados aquí y representa las capas localmente.
