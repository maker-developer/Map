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
- **Dueño:** suma a **Cursor** al equipo para avanzar más rápido. Reparto a tres: Claude (app iOS y estilo), Codex (datos, nube, compilar), Cursor (app web y pruebas automáticas). Arranque de Cursor en [`cursor.md`](cursor.md).
- **Dueño:** la experiencia de buscar una ruta se sentía pobre; pide igualar a Apple Maps y Google Maps. **Claude** construye en el app iOS el flujo completo: búsqueda de lugares, pin al mantener pulsado, ficha con «Cómo llegar», pantalla de ruta (origen/destino ⇅, coche / a pie / bici con su tiempo, alternativas en el mapa, tarjetas, pasos, «Ir») y navegación (banner, barra de llegada, voz, cámara que sigue, recálculo). Servicios **provisionales** (Photon y OSRM de OpenStreetMap) hasta el índice y el motor propios.
- **Claude:** navegación más fluida y completa a pedido del dueño: cálculos ligeros (1/s, tramo cercano), zoom por velocidad, carriles y salidas, vista previa de pasos, «Volver a centrar», pantalla de llegada; Casa / Trabajo / guardados / recientes; ficha con guardar, compartir, copiar y abrir en otras apps; transiciones y vibraciones.
- **Dueño (prueba en el iPhone):** al navegar no se podía tocar el mapa y la cámara no seguía de cerca. **Claude:** mapa siempre tocable al navegar; cámara propia que se desliza cada segundo a tu posición, rumbo y zoom por velocidad, con la flecha en el tercio inferior; cualquier gesto deja de seguir y aparece «Volver a centrar»; barra de navegación que se sube con Resumen, Compartir llegada, Voz y próximos pasos; burbuja de velocidad.
- **Dueño (prueba con la versión de Cursor):** barra inferior amontonada y alta, números pequeños, «Finalizar» siempre visible; pide brújula Liquid Glass, qué pasa con lo recorrido y si la llegada es automática. **Claude:** barra recogida de 100 pt con llegada · tiempo · distancia simétricas en SF Rounded grande y «Finalizar» solo al subirla; brújula de vidrio propia (se esconde al norte, toca para volver al norte); lo recorrido en gris claro; llegada automática también junto al destino y cierre solo al minuto. **Nota:** Cursor había editado archivos del app iOS (de Claude) solo en la Mac; se le pide descartar esos cambios para no chocar.
