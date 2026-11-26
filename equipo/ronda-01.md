# Ronda 1 · Calles, playas y agua

**Objetivo:** que el mapa se lea de un vistazo como el de Apple (jerarquía clara de vías) y tenga lo que Apple no cuida: arena en las playas, la bahía con su profundidad y los nombres del agua.

**Estado:** 🟡 en curso

## Codex (rama `codex/datos`)

- [x] ✅ **C1. Calles con jerarquía.** Añadir a `calles` las propiedades `clase`, `puente`, `tunel` y `ref` según [`capas.md`](capas.md). Mantener `name` y `kind`. Documentar en `data/SOURCES.md` la tabla CLASS → `clase` y de dónde salen puente, túnel y número de vía.
- [x] ✅ **C2. Playas.** Nueva capa `playas` (polígonos con `name`) en `base.pmtiles`. Documentar la fuente.
- [x] ✅ **C3. Profundidad del agua.** Nueva capa `profundidad` con bandas `0-1`, `1-2`, `2-5`, `5-10`, `10+` desde la batimetría de NOAA, simplificada para que `base.pmtiles` no crezca más de ~10 MB.
- [x] ✅ **C4. Nombres del agua.** `name` relleno en las masas de agua principales, o capas `agua-nombres` (puntos) y `agua-ejes` (líneas de ríos) si la fuente no los trae.
- [x] ✅ **C5. Publicar.** Regenerar `public/data/` en `codex/datos` y subir a R2 en `v2/` (sin borrar `v1/`). Anotar abajo en «Entregado» los tamaños y cualquier nombre que cambie.
- [x] ✅ **C6. Compilar.** Cuando Claude marque A5, fusionar `codex/datos` → `claude/laboratorio-ios` (solo `public/data/` y `data/`), compilar Map Lab y dejarlo en el iPhone. Errores de compilación: arreglo mínimo con commit `Compilación: …`.

## Claude (rama `claude/laboratorio-ios`)

- [x] ✅ **A1. Jerarquía de calles.** Estilo por `clase` (autopista cálida con borde, avenida blanca con borde fino, local fina, servicio tenue; rampas más finas). Mientras no llegue `clase`, usar `kind` como hoy. Puentes con borde de sombra, túneles punteados. Ancho real en metros a zoom 18+.
- [x] ✅ **A2. Escudos de autopista.** Escudos propios para `ref` (I, US, SR, Turnpike) como íconos del estilo, en iOS y web.
- [x] ✅ **A3. Playas y agua.** Arena para `playas`; `profundidad` en degradado turquesa (claro poco profundo → oscuro profundo) en claro y oscuro; nombres de agua en cursiva siguiendo los ríos. Generar glifos de DM Sans Italic.
- [x] ✅ **A4. Experimento «Ronda 1».** En Map Lab, un experimento con interruptor «Antes / Después» para comparar el estilo actual con el nuevo en Brickell, Miami Beach y la bahía.
- [x] ✅ **A5. Visor web.** Los mismos cambios en `viewers/web/src/map/style.js` y paletas en `styles/`, para comparar en la Mac.

## Pedidos entre los dos

- Claude → Codex: los nombres de propiedades de [`capas.md`](capas.md). Si CLASS no permite distinguir algo (p. ej. rampas), decirlo aquí y lo resolvemos con otra regla.
- Claude → Codex (nuevo): la tabla CLASS → `clase` ya está comprobada en [`capas.md`](capas.md) (8 clases: añadí `principal` y `peatonal`). Además, en `calles`:
  1. `name` con mayúsculas y minúsculas («SW 8th St», no «SW 8TH ST»).
  2. `ref` **y** `red` (`I`, `US`, `SR`, `TP`) para elegir la forma del escudo.
- Claude → Codex (aviso): en `public/data/` no cambia nada de mi lado; las letras nuevas están en `styles/glifos/DMSans-Italic` (app) y `styles/fonts/DMSans-Italic.ttf` (web).
- Claude → Codex (tras revisar `7730bc2`): ✅ recibido `clase`, `puente`, `tunel`, `ref`, `playas` (19), `profundidad` (1.767), `agua-nombres` (83) y `agua-ejes` (4). Faltó `red`: el estilo ya lo deduce de `ref` (`I-…`, `US-…`, `FL Turnpike`, el resto `SR`), así que no es urgente. **Pregunta:** ¿está publicado `v2/` en R2? `MapNubeURL` sigue en `v1/`; con la URL confirmada lo cambio en `viewers/ios/project.yml`. Mientras, «Dentro del app» ya usa los datos nuevos.
- Claude → Codex (tras la prueba del dueño en el iPhone): las bandas de `profundidad` salen con bordes rectos y «parches» cerca de la costa (Brickell, Key Biscayne). Pedido: **recortarlas con la capa `agua`** (que no pisen tierra ni muelles) y **suavizar** los bordes (simplificar + suavizado tipo Chaikin, o interpolar la rejilla de NOAA antes de sacar contornos). Claude ya bajó el contraste entre bandas para que se note menos mientras tanto.
- Codex → Claude: Sí, `v2/` ya está publicada en R2: https://pub-031a310ad68042d59e4273a0b01a7dc1.r2.dev/v2. Los tres archivos son `base.pmtiles`, `buildings.pmtiles` y `transit.pmtiles` (también está `manifest.json`); `v1/` sigue intacta. No añadí `red`: el estilo la deduce de `ref` y no es urgente.
- Codex → Claude (ajuste de profundidad): `v3/` ya está publicada en https://pub-031a310ad68042d59e4273a0b01a7dc1.r2.dev/v3. Incluye `base.pmtiles`, `buildings.pmtiles`, `transit.pmtiles` y `manifest.json`; suavicé la rejilla NOAA y recorté las bandas a `agua`, sin área detectada sobre tierra. No cambié `MapNubeURL`; puedes actualizarla cuando integres los datos.

## Entregado

| Quién | Qué | Dónde | Notas |
| --- | --- | --- | --- |
| Codex | C1 · jerarquía de calles y propiedades | `data/scripts/preparar.py`, `data/SOURCES.md` | Conserva `name` y `kind`; `CLASS=0` y `RAMP` permiten identificar rampas. `BRIDGE`/`TUNNEL` llegan nulos en la fuente consultada; `puente` también usa `F_ZLEV`/`T_ZLEV`; `tunel` queda false si no hay marca. `ref` se lee del nombre o alias documentados. |
| Codex | C2 · polígonos de playas | `data/scripts/preparar.py`, `data/SOURCES.md` | Capa `playas`, `name` desde `Beachpoly_gdb`; minzoom 9. Fuente ofrece 19 polígonos nombrados. |
| Codex | C3 · bandas de profundidad | `data/scripts/preparar.py`, `data/requirements.txt`, `data/SOURCES.md` | NOAA CRM Vol. 3 (2023), 1 segundo de arco; tras suavizar la rejilla y recortar por `agua`, quedaron 1.020 polígonos. Validación geométrica: área fuera de `agua` ≈ 0. |
| Codex | C4 · nombres sobre el agua | `data/scripts/preparar.py`, `data/SOURCES.md` | Capa de 83 puntos `agua-nombres` y 4 líneas agrupadas `agua-ejes`; incluye Biscayne Bay, Atlantic Ocean, 81 lagos/lagunas nombrados y las cuatro vías del contrato. Nombres hidrográficos de OSM por falta de topónimos en las capas de agua del condado. |
| Codex | C5 · archivos publicados en v2 | `public/data/`, R2 `map-tiles/v2/` | `base.pmtiles` 19,519,565 B (+2,889,097 B vs. v1, bajo el objetivo de +~10 MB); `buildings.pmtiles` 70,697,232 B; `transit.pmtiles` 2,128,071 B; `manifest.json` 2,654 B. R2 conserva el nombre contractual `buildings.pmtiles`; el archivo del repo sigue como `edificios.pmtiles`. v1 no se borró. R2 público: `https://pub-031a310ad68042d59e4273a0b01a7dc1.r2.dev/v2/`. |
| Codex | Profundidad refinada · publicación v3 | `public/data/`, R2 `map-tiles/v3/` | `base.pmtiles` 19,055,260 B; `buildings.pmtiles` 70,697,232 B; `transit.pmtiles` 2,128,071 B; `manifest.json` 2,654 B. `v1/` y `v2/` permanecen intactas. R2 público: `https://pub-031a310ad68042d59e4273a0b01a7dc1.r2.dev/v3/`. |
| Codex | C6 · integración y prueba en iPhone | Rama `claude/laboratorio-ios`, commit `7730bc2`; iPhone 17 Pro Max | A5 estaba ✅. Integrados solo `data/` y `public/data/`; Map Lab compiló, se instaló y abrió. Para esta instalación se usó `MapNubeURL` v2 temporalmente sin editar `viewers/ios/project.yml`; queda el pedido a Claude para cambiar el valor del repo a `/v2`. |
| Claude | Estilo ronda 1 en iOS: `EstiloRonda1.swift` (calles por clase con ancho real desde zoom 18, puentes con sombra, túneles punteados, peatonales, nombres con prioridad, escudos, arena, agua por profundidad, nombres del agua en cursiva) y `Escudos.swift` | `claude/laboratorio-ios` · `viewers/ios/Laboratorio/Mapa/` | Funciona ya con `kind`; usa `clase`, `puente`, `tunel`, `ref`, `red`, `playas`, `profundidad`, `agua-nombres`, `agua-ejes` en cuanto existan |
| Claude | Experimento «Ronda 1 · Calles y agua» con «Antes / Después», zona nueva «Bahía de Biscayne», interruptor en el menú de capas | `viewers/ios/Laboratorio/Experimentos/` | Sin compilar (no hay Xcode en la nube) |
| Claude | El mismo estilo en el visor web, paletas `ronda1` en `styles/base-*.js`, escudos en canvas, edificios encima de calles y transporte, la vista en la dirección (`#zoom/lat/lon/rumbo/inclinación`) | `viewers/web/src/`, `styles/` | Validado con el validador oficial de MapLibre (42 capas, sin errores) y probado en el navegador |
| Claude | Arreglo: el visor web fallaba al cargar las rutas («features is not iterable»); el transporte quedaba encendido y el filtro vacío | `viewers/web/src/main.js` | Ya carga las 127 rutas |
| Claude | DM Sans Italic (instancia estática 9 pt, 400) para los nombres del agua | `styles/fonts/`, `styles/glifos/DMSans-Italic/` | OFL, como las demás DM Sans |
| Claude | Ajustes tras la primera prueba en el iPhone: escudos **encima de los edificios** (las casas en 3D los manchaban y las torres los tapaban), escudos algo más pequeños y espaciados; brújula debajo de los controles; hoja recogida solo con la barra; bandas de agua con menos contraste | `EstiloMapa.swift`, `EstiloRonda1.swift`, `MapaMapLibre.swift`, `MapaPrincipal.swift`, `HojaBusqueda.swift`, `style.js`, `styles/` | Estilo validado |
| Claude | **El app pasa a ser un mapa normal** (pedido del dueño): `Principal/MapaPrincipal.swift` (mapa a pantalla completa, apariencia automática, capas, 2D / 3D, ubicación) y `Principal/HojaBusqueda.swift` (hoja inferior con búsqueda de zonas, ficha de lo tocado y botón del laboratorio). Los experimentos siguen en el modo laboratorio. Nombre en el iPhone: **Map** | `viewers/ios/Laboratorio/Principal/` | Sin compilar |
| Claude | **Colores nuevos** (pedido del dueño, inspirados en Apple Maps sin copiarlos): tierra blanco cálido, agua celeste por profundidad, parques verde fresco, calles grises con borde claro, torres grises con luz neutra, **casas en seis pasteles** (cada casa de un color, siempre el mismo), nombres de calles en mayúsculas espaciadas; modo oscuro grafito con agua azul noche | `styles/base-*.js`, `EstiloMapa.swift`, `EstiloRonda1.swift`, `style.js` | En Map Lab, «Antes» conserva los colores anteriores para comparar |
## Probar (el dueño, en el iPhone)

El app abre ya en el **mapa normal** con el estilo de la ronda 1. Para comparar, el matraz junto a la búsqueda abre el **modo laboratorio** → experimento **Ronda 1**, con el interruptor Antes / Después:

1. **Condado entero:** ¿se distinguen de un vistazo las autopistas (I-95, 836, Turnpike) de las avenidas y las calles?
2. **Brickell inclinado:** ¿se leen los puentes sobre el río y las rampas de la I-95?
3. **Miami Beach:** ¿se ve la arena de la playa de punta a punta?
4. **Bahía de Biscayne:** ¿se nota la profundidad (más claro cerca de la costa)?
5. **Nombres del agua:** ¿salen Biscayne Bay y Miami River, y el del río sigue su curva?
6. **Modo oscuro:** lo mismo de noche: ¿se lee todo?
6b. **Colores:** comparar con Apple Maps en las mismas zonas (Key Biscayne, Brickell, un barrio de casas): ¿tierra, agua, parques, torres grises y casas pastel se sienten igual de agradables?
7. **Rendimiento:** en el panel de medidas, ¿el primer dibujo y los cuadros/s son parecidos a antes?

Mandar una captura de cada punto (antes y después) y lo que guste o no. Con eso se abre la ronda 2.
