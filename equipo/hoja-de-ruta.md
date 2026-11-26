# Hoja de ruta

Meta: un mapa propio de Miami-Dade, completo y con identidad, que se vea mejor que el mapa estándar de Apple donde podemos ganar (identidad, coherencia, detalle de Miami) y que sirva para cualquier proyecto. Busdade llega al final como un estilo y unas capas encima.

Cada ronda se prueba en el iPhone con Map Lab antes de pasar a la siguiente. El orden puede cambiar según lo que el dueño vea en las pruebas.

| Ronda | Tema | Claude | Codex |
| --- | --- | --- | --- |
| **1** | **Calles, playas y agua** | Jerarquía de calles, puentes, túneles, escudos; arena; agua por profundidad; nombres de agua en cursiva; experimento «Ronda 1» | `clase`, `puente`, `tunel`, `ref` en calles; capa `playas`; batimetría NOAA `profundidad`; nombres de agua; R2 `v2/`; compilar |
| 2 | **Búsqueda** ([ronda-02.md](ronda-02.md)) | Motor SQLite en iOS, hoja de resultados, marcador y ficha | Índice `busqueda.sqlite`: direcciones, calles, barrios, municipios, lugares públicos |
| 3 | Rutas a pie | Cálculo en el teléfono sobre las calles, línea en el mapa y pasos | Red peatonal de las calles del condado |
| 4 | Rutas en coche | Pantalla de ruta, alternativas y tiempos | Servidor de rutas (Valhalla u OSRM) con datos de OpenStreetMap |
| 5 | Barrios y nombres | Etiquetas de barrios (mayúsculas espaciadas), prioridades y colisiones, municipios desde datos | Capas `barrios` y `municipios` del condado con nombre y punto de etiqueta |
| 6 | Tren elevado y emblemáticos | Vía del Metrorail y Metromover en 3D, estaciones con volumen, edificios emblemáticos destacados | Trazado de la vía con altura, estaciones (huella y entradas), lista de emblemáticos con id de edificio |
| 7 | Lugares con íconos Lucide | Íconos Lucide en círculos por tipo, reglas de aparición por zoom, ficha al tocar | Capa `lugares` (hospitales, escuelas, bibliotecas, parques, policía, bomberos, estaciones) con `tipo` y `name` |
| 8 | Suelo vivo | Colores suaves de usos del suelo y arbolado | Capas `uso-suelo` (aeropuerto, campus, industria, golf, cementerio…) y `arbolado` |
| 9 | Edificios con presencia | Aparición suave por zoom, techos más claros, sombra falsa, color por uso | Uso del edificio (si existe en el inventario) y revisión de alturas con LiDAR |
| 10 | Noche y profundidad | Modo oscuro con personalidad, niebla y cielo al inclinar | — |
| 11 | Estilo único | Un solo estilo JSON compartido por web e iOS (hoy está duplicado en `style.js` y `EstiloMapa.swift`) | Generar el JSON del estilo en el pipeline y publicarlo en R2 |
| 12 | Nube en serio | Que el app use la nube por defecto y lleve solo una zona dentro | Dominio propio para R2, caché, versionado |
| 13 | Más allá del condado | Estilo para la base continua | Base OpenStreetMap del sur de Florida (Broward, Monroe, Collier) bajo los datos del condado |

Después: búsqueda de direcciones (`extras/search`), rutas a pie (`extras/routing`) e integración en Busdade.
