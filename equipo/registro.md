# Registro

Una entrada por ronda: qué se entregó, qué probó el dueño y qué decidió.

## Ronda 0 · Punto de partida (26 de noviembre de 2026)

- **Codex:** repositorio `Map` con generador de datos, PMTiles de Miami-Dade (base, edificios con altura, transporte), visor web con tema claro y oscuro. Teselas publicadas en Cloudflare R2 (`v1/`) con rangos HTTP.
- **Claude:** app Map Lab para iOS (rama `claude/laboratorio-ios`): SwiftUI, MapLibre Native 6.x, íconos Lucide, cinco experimentos, opción «Los edificios tapan», medidas en vivo y origen de los mapas (app, nube, Mac). Glifos DM Sans en `styles/glifos/`.
- **Dueño:** probó Map Lab en el iPhone. Pide subir el nivel de diseño por encima del mapa de Apple. Se acuerda trabajar por rondas.
- **Siguiente:** [ronda 1](ronda-01.md), calles, playas y agua.

## Ronda 1 · en curso

- **Codex:** datos de la ronda 1 fusionados en `claude/laboratorio-ios` (`7730bc2`): `clase`, `puente`, `tunel`, `ref`, playas, profundidad (NOAA), nombres del agua. `base.pmtiles` pasa de 16,6 a 19,5 MB.
- **Claude:** estilo de la ronda 1 (web e iOS), colores nuevos inspirados en Apple Maps a pedido del dueño, y escudos con forma aunque falte `red`.
- **Dueño:** decide que el app sea **un mapa normal** (como Apple Maps) con un **modo laboratorio** aparte, porque cuando terminen las pruebas seguirá siendo un app de mapas. Claude lo implementa antes de la compilación de la ronda 1. Próximas rondas propuestas: búsqueda (2), rutas a pie (3), rutas en coche (4).
