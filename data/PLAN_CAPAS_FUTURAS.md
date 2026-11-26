# Plan de capas y fuentes para Map

Este documento prepara las próximas fuentes públicas sin cambiar el generador, los PMTiles, la app ni el visor web. El objetivo es sumar datos útiles de Miami-Dade con procedencia, actualización y licencia claras, manteniendo el mapa base ligero.

## Lo que ya existe o está en marcha

- **Ya está en Map:** calles, agua, parques, playas, profundidad NOAA, edificios, transporte estático y publicación PMTiles versionada en R2.
- **Ronda 2 en el árbol de trabajo compartido:** Cursor está trabajando en búsqueda de direcciones y lugares, índice SQLite, red peatonal y la interfaz de rutas. No duplicar ni modificar esos archivos mientras Cursor termina su tanda.
- **Este plan:** solo documenta las siguientes incorporaciones. No cambia `data/scripts/`, `public/data/`, `viewers/`, `package*.json` ni R2.

## Catálogo de fuentes candidatas

| Capa o función | Fuente primaria | Tipo y frecuencia | Formato recomendado en Map | Condiciones / trabajo pendiente |
| --- | --- | --- | --- | --- |
| Direcciones, puntos públicos, parcelas, barrios, zonificación, instalaciones | [Miami-Dade Open Data Hub](https://opendata.miamidade.gov/) y [servicios GIS del condado](https://www.miamidade.gov/global/service.page?Mduid_service=ser1468850841882434) | Descarga/API; la frecuencia depende de cada conjunto | Datos estáticos en `busqueda.sqlite` o PMTiles según el uso | Revisar metadatos/licencia por conjunto. El localizador GeoAddress se actualiza semanalmente; confirmar acceso, límites y condiciones antes de convertirlo en dependencia de producción.
| Veredas, cruces, ciclovías, accesos, negocios y detalle comunitario | [OpenStreetMap](https://www.openstreetmap.org/copyright) | Extracto estático actualizado por lotes; comunidad voluntaria | Completar la red peatonal y lugares, conservando fuente por capa | Mostrar atribución y cumplir ODbL al redistribuir bases derivadas. No usar los servidores de teselas de OSM como alojamiento de Map.
| Elevación de terreno y LiDAR | [USGS 3DEP](https://www.usgs.gov/3d-elevation-program/) y [LidarExplorer](https://www.usgs.gov/tools/lidarexplorer) | Descarga por área/proyecto; la cobertura y fecha varían | DEM recortado y simplificado; evaluar terreno raster aparte de huellas vectoriales | Datos gratuitos y sin restricciones de uso según USGS. Primero comprobar cobertura, resolución, fecha, datum vertical y tamaño para Miami-Dade.
| Batimetría y continuidad costa-tierra | [NOAA/NCEI Bathymetry](https://www.ncei.noaa.gov/products/bathymetry) y [modelos costeros NOAA](https://www.ncei.noaa.gov/products/coastal-elevation-models) | Modelos y levantamientos de varias fechas | Mantener como capa temática; reemplazar solo tras validar cobertura y resolución | La capa actual ya usa NOAA CRM. Comparar CUDEM más reciente antes de sustituirla. No es información para navegación.
| Zonas oficiales de inundación | [FEMA National Flood Hazard Layer](https://www.fema.gov/flood-maps/national-flood-hazard-layer) | Base geográfica con revisiones y cartas efectivas | `inundacion.pmtiles` separado, opcional y versionado | Registrar fecha/vintage y autoridad del mapa. Es cartografía de riesgo, no una predicción de inundación en tiempo real.
| Alertas, pronóstico y avisos por ubicación | [API del National Weather Service](https://www.weather.gov/documentation/services-web-alerts) | API dinámica | Endpoint del servidor con caché; no incluir una copia fija en el mapa base | Consultar con moderación (NWS recomienda no pedir alertas más de una vez cada 30 s), identificar el cliente y mostrar hora de actualización.
| Conteos históricos y clasificación de carreteras | [GIS y estadísticas FDOT](https://www.fdot.gov/statistics/gis/) | Descargas GIS; varios productos son anuales | Atributos de carreteras en una capa temática compacta | No confundir AADT histórico con velocidad o congestión actual.
| Incidentes, velocidades, cámaras, obras y cierres | [Florida 511](https://www.fl511.com/faq) | Servicio de información en vivo | Solo integrar después de confirmar un feed/API reutilizable y sus términos; proxy/cache del servidor si está permitido | La web pública muestra datos en tiempo real, pero eso por sí solo no autoriza extraerlos o redistribuirlos. No raspar la web como sustituto de una API autorizada.
| Ortofotos e imágenes aéreas | [Miami-Dade GIS](https://www.miamidade.gov/global/service.page?Mduid_service=ser1468850841882434), [NOAA Digital Coast](https://coast.noaa.gov/digitalcoast/data/) y productos federales disponibles por zona | Cobertura, resolución, fecha y licencia varían | Teselas raster independientes, con fecha visible y opción de activar/desactivar | El condado indica que algunos paquetes completos de ortofotos pueden tener costo. Comprobar derechos y fecha antes de publicar; no incorporarlas al bundle iOS por defecto.
| Horarios y vehículos de tránsito | [Feeds de Miami-Dade Transit](https://www.miamidade.gov/global/transportation/open-data-feeds.page) / Swiftly | GTFS estático y GTFS-Realtime | Horarios como archivo versionado; realtime vía servidor/cache | GTFS-RT de Swiftly requiere acceso API. Ya está contemplado en el trabajo de transporte del proyecto.

## Orden propuesto

1. **Cerrar búsqueda y rutas peatonales de la ronda 2.** Revisar la tanda actual de Cursor e integrar solamente cuando termine. La red derivada de calles debe rotularse como aproximación si no incluye aceras verificadas.
2. **Añadir inundación de FEMA.** Es una capa estática, local y de valor práctico alto. Validar el vintage del condado, simplificar geometrías, publicar separada y permitir apagarla.
3. **Añadir alertas meteorológicas NWS.** Responder desde el servidor, guardar caché breve, mostrar fuente y hora; manejar respuestas vacías o atrasadas.
4. **Evaluar 3DEP/LiDAR y el terreno.** Hacer primero un inventario de cobertura y resolución en Miami-Dade; comparar DEM del suelo con nube de puntos antes de elegir un formato de terreno.
5. **Investigar tráfico FDOT/Florida 511.** Confirmar acceso técnico y permiso de uso/redistribución antes de escribir un adaptador.
6. **Evaluar ortofotos.** Seleccionar una fuente con fecha, resolución y licencia compatibles. Servirlas como capa raster opcional.
7. **Rutas en coche y expansión regional.** Usar una red OpenStreetMap procesada por un motor propio como Valhalla u OSRM; validar restricciones y límites del servicio antes de ofrecer navegación.

## Contrato para no cargar ni mezclar de más

- **Capas estáticas:** geometrías procesadas en archivos propios PMTiles/SQLite, publicadas en una versión nueva de R2; mantener las versiones anteriores para poder volver atrás.
- **Capas en vivo:** tránsito, avisos y condiciones cambiantes se consultan mediante servidor/cache con su propia marca de tiempo y manejo de errores.
- **Manifiesto:** cada producto nuevo debe declarar fuente, fecha de descarga, fecha/vintage de origen, licencia/atribución, cobertura, cantidad de objetos y bytes.
- **Visor:** las capas temáticas pesadas deben poder activarse y desactivarse; imágenes y terreno no se agregan al paquete iOS hasta medir su tamaño y rendimiento.
- **Calidad:** antes de publicar, comprobar cobertura completa, geometrías inválidas, duplicados, coordenadas fuera del condado, antigüedad y tamaño final.

## Coordinación de archivos

La tanda activa de Cursor toca `data/scripts/busqueda.py`, `data/scripts/peatonal.py`, `public/data/`, `viewers/ios/`, `viewers/web/` y `package*.json`. Codex no editará esas rutas mientras la tanda siga en curso. Este documento está en una rama aislada; los futuros cambios de datos se separarán por producto y se integrarán tras acordar el contrato y la carpeta de R2.
