# Cursor · arranque

Cursor se une al equipo con **la app web y las pruebas automáticas**. Lee primero [`README.md`](README.md) (reparto, ramas y la regla de no tocar archivos de otro).

Rama: **`cursor/web`**, creada desde `claude/laboratorio-ios`. Al terminar cada tarea, push a `cursor/web`; al cerrar la ronda, fusiona **solo tus archivos** en `claude/laboratorio-ios`.

Puedes empezar ya: nada de esto espera a Codex ni a Claude.

## Tus archivos

`viewers/web/` **menos** `viewers/web/src/map/` (eso es el estilo, de Claude): `index.html`, `src/main.js`, `src/features/`, `src/ui/` (nueva), `viewer.css`, `vite.config.js`; `package.json` y `package-lock.json`; `tests/`; `.github/`.

El estilo se usa tal cual desde `viewers/web/src/map/style.js`: `baseStyle(tema)`, `applyTheme(map, tema)`, `addShieldImages(map)` y, desde `buildings.js`, `addBuildingLayers` / `setBuildingVisibility`. Los edificios y el transporte se insertan antes de la capa `towns` (así los edificios tapan lo de detrás y los escudos quedan encima).

## Tareas

- [ ] **W1. La web como app de mapas (igual que la de iOS).** Hoy es un visor de pruebas con una barra arriba. Que sea un mapa normal:
  - Mapa a pantalla completa con el estilo de la ronda 1.
  - **Apariencia automática** (`prefers-color-scheme`) con opción clara u oscura fija (`applyTheme`).
  - Controles de vidrio arriba a la derecha, en una sola columna como en iOS: **capas** (apariencia; rutas y paradas), **2D / 3D** (en 2D, edificios planos y sin inclinación; en 3D, con volumen e inclinación de 50°) y **mi ubicación** (geolocalización del navegador).
  - **Hoja de búsqueda:** abajo en el móvil (recogida solo enseña la barra, como iOS) y a la izquierda en escritorio. Por ahora busca entre zonas y vuela a ellas, con las mismas zonas y coordenadas que `Zona` en `viewers/ios/Laboratorio/Mapa/MapaMapLibre.swift` (Todo el condado, Miami, Downtown y Brickell, Miami Beach, Miami Lakes, Bahía de Biscayne).
  - **Ficha al tocar** un edificio (dirección y altura) o una parada (nombre y rutas), con los nombres limpios como en iOS (`Texto.bonito` en `viewers/ios/Laboratorio/App/Diseno.swift`: «SE 7 ST@S MIAMI AV» → «SE 7 St y S Miami Av»).
  - **Íconos Lucide** (paquete `lucide` de npm) y letra **DM Sans** (`styles/fonts/`).
  - Se conserva la vista en la dirección (`#zoom/lat/lon/rumbo/inclinación`) y la atribución de datos del condado.
  - Funciona bien a 390 px de ancho, sin desplazamiento horizontal.
- [ ] **W2. Pruebas automáticas.** En `package.json`:
  - `npm run validar`: valida el estilo con `@maplibre/maplibre-gl-style-spec` (`validateStyleMin`) en claro y en oscuro, con las capas de edificios añadidas. Sale con error si hay alguno.
  - `npm run capturas`: con Playwright (Chromium en modo software: `--use-angle=swiftshader --enable-unsafe-swiftshader --ignore-gpu-blocklist`), guarda en `tests/capturas/AAAA-MM-DD/` (fuera de git) estas vistas a 430×900, escala 2, esperando a que el mapa termine de cargar:
    | Nombre | Hash |
    | --- | --- |
    | condado | `9.4/25.72/-80.33/0/0` |
    | centro-i95 | `13.6/25.778/-80.205/0/0` |
    | brickell | `16.3/25.7605/-80.1925/-30/55` |
    | miami-beach | `15.3/25.786/-80.132/-25/45` |
    | bahia | `11.8/25.735/-80.185/0/0` |
    | casas | `17.2/25.8235/-80.2905/0/30` |
    | brickell-oscuro | la de Brickell con apariencia oscura |
  - Que las capturas no muestren errores en la consola; si los hay, que el script los liste al final.
- [ ] **W3. GitHub Actions.** `.github/workflows/web.yml`: en cada push a `claude/laboratorio-ios`, `cursor/web` y `codex/datos`, `npm ci`, `npm run validar` y `npm run build`.
- [ ] **W4. Cuando termines W1–W3:** fusiona tus archivos en `claude/laboratorio-ios`, corre `npm run capturas` sobre esa rama y anota en la ronda abierta (`ronda-01.md` o `ronda-02.md`, sección «Entregado») qué hiciste y si hubo errores.

## Después (ronda 2)

La **búsqueda en la web**: tarea W5 de [`ronda-02.md`](ronda-02.md).

## Pedidos

- Si el estilo te da problemas en la web, escríbelo en «Pedidos entre los dos» de la ronda (dirigido a Claude) y no edites `src/map/`.
- Si necesitas datos (por ejemplo la lista de zonas en JSON o el índice de búsqueda), pídelo a Codex en la misma sección.
