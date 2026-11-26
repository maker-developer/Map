# Map (iOS)

App nativa de mapas de Miami-Dade con el estilo propio, en SwiftUI, MapLibre Native e íconos Lucide. **Es un mapa normal, como Apple Maps**, y además tiene un **modo laboratorio** (el ícono del matraz junto a la búsqueda) para probar cada mejora antes de pasarla al mapa.

- **Mapa principal:** pantalla completa con el estilo de la ronda 1, apariencia automática (sigue al iPhone) o fija, controles de vidrio arriba a la derecha (capas, 2D / 3D, mi ubicación) y una hoja inferior con la búsqueda. Al tocar un edificio o una parada, su ficha sube en la hoja.
- **Búsqueda y rutas (como Apple Maps y Google Maps):** al escribir salen lugares; al tocar uno (o **mantener pulsado el mapa**) sale un pin y su ficha con «Cómo llegar» y el tiempo en coche. La pantalla de ruta tiene origen y destino con ⇅, pestañas **Coche / A pie / Bici** con su tiempo, las rutas alternativas a la vez en el mapa (elegida en azul, las demás en gris, se tocan para elegirlas, con su tiempo encima), tarjetas con duración, llegada, distancia, «Más rápida» y «por…», los pasos y **«Ir»**. Navegando: banner con la maniobra, la distancia y la calle (y la siguiente), barra con llegada, minutos y distancia que faltan, voz en español, la cámara te sigue inclinada y **recalcula** si te sales.
- **Navegación fluida:** cálculos como mucho una vez por segundo y solo sobre el tramo cercano de la ruta (no se traba en rutas largas); zoom según la velocidad (más lejos en autopista, más cerca antes de un giro); carriles que sirven y carteles de salida («Salida 4 · Downtown») en el banner, y vista previa de los próximos pasos al tocarlo; si mueves el mapa con el dedo deja de seguirte y aparece **«Volver a centrar»**; pantalla de **llegada** con la hora y «Volver».
- **Favoritos:** Casa y Trabajo («Ir» con un toque, directo a la ruta), guardados y recientes, que se conservan al cerrar el app. La ficha del lugar tiene **Guardar, Compartir, Copiar** y **Más** (abrir en Apple Maps, Google Maps o Waze; guardar como Casa o Trabajo).
- **Provisional:** la búsqueda usa Photon y las rutas OSRM de FOSSGIS (OpenStreetMap), solo para probar la experiencia. Se cambian por el índice propio (ronda 2) y el motor propio (rondas 3 y 4) tocando solo `Rutas/ServiciosRuta.swift`.
- **Modo laboratorio:** la lista de experimentos (antes / después, medidas, origen de los mapas).
- **Mapa:** MapLibre Native para iOS 6.x por Swift Package Manager. Lee los mismos PMTiles que el visor web (`public/data/`) con `pmtiles://file://`, soportado desde MapLibre iOS 6.10.0.
- **Letras:** DM Sans en formato de glifos de MapLibre (`styles/glifos/`), dentro del app. Funciona sin internet.
- **Íconos:** Lucide (licencia ISC, `Laboratorio/Resources/LICENSE-lucide.txt`) como SVG en Assets › Lucide.
- **iOS 18 o posterior.** En iOS 26 los controles usan Liquid Glass; antes, material del sistema.

El proyecto y la carpeta se siguen llamando `Laboratorio` (cambiar el nombre del target no aporta nada); en el iPhone el app se llama **Map**.

## Compilar (Mac con Xcode)

Desde la raíz del repositorio:

```sh
brew install xcodegen          # solo la primera vez
cd viewers/ios
xcodegen generate
open Laboratorio.xcodeproj
```

En Xcode: elegir el equipo de firma en *Signing & Capabilities*, elegir el iPhone y ejecutar. La primera vez Xcode descarga MapLibre (Swift Package Manager).

El app pesa unos 92 MB porque incluye los PMTiles del condado (base, edificios y transporte).

## Experimentos

| Experimento | Zona | Qué mirar |
| --- | --- | --- |
| Ronda 1 · Calles y agua | Todo el condado | «Antes / Después»: jerarquía de calles, escudos, playas, profundidad y nombres del agua ([lista](../../equipo/ronda-01.md)) |
| Mapa base | Todo el condado | Carga, nombres legibles, acercar y alejar fluido |
| Edificios en 3D | Brickell | «Los edificios tapan» encendido y apagado |
| Rutas y paradas | Brickell | Distinguir estaciones de tren y paradas de bus |
| Modo oscuro | Miami Beach | Contraste de agua, parques y nombres |
| Rendimiento | Miami Lakes | Cuadros por segundo, memoria y primer dibujo |

Controles a la derecha del mapa (de arriba abajo): zona, capas (3D, «los edificios tapan», transporte, inclinación), tema claro/oscuro, medidas y mi ubicación. Al tocar un edificio sale su dirección y altura; al tocar una parada, su nombre y rutas.

**«Los edificios tapan»:** los nombres de calles, rutas y paradas se dibujan antes que los edificios, así una torre tapa lo que queda detrás. Apagado, se comporta como el visor web actual (todo flota encima).

## Origen de los mapas

En el app, *Origen de los mapas* (abajo en la lista):

| Origen | De dónde | Para qué |
| --- | --- | --- |
| Dentro del app | `public/data/` copiado al bundle | Sin internet |
| En la nube | Cloudflare R2, `Info.plist › MapNubeURL` | Baja solo la parte de cada zona (rangos HTTP, respuesta 206) |
| Desde la Mac | `npm run dev` en la misma Wi-Fi | Probar teselas nuevas sin compilar |

La nube usa `pmtiles://https://…/v1/base.pmtiles`, `buildings.pmtiles` y `transit.pmtiles` (en la nube los edificios se llaman `buildings`, no `edificios`). La dirección `r2.dev` es solo para desarrollo: para producción, conectar un dominio propio al bucket y cambiar `MapNubeURL` en `project.yml`.

El panel de medidas dice qué origen está en uso, para comparar el primer dibujo y la fluidez entre la nube y el app.

Para la Mac: desde la raíz del repositorio, `npm run dev`; en el app, elegir *Desde la Mac* y escribir la dirección «Network» que muestra Vite (por ejemplo `http://192.168.1.20:4180`).

## Estructura

```text
viewers/ios/
  project.yml                    Proyecto de XcodeGen (MapLibre, datos y letras como recursos)
  Laboratorio/
    App/                         Entrada del app, íconos Lucide, vidrio y textos
    Principal/                   El mapa normal: MapaPrincipal (mapa y controles) y HojaBusqueda
    Rutas/                       Búsqueda, ficha del lugar, rutas y navegación: Navegador (fases y lógica),
                                 HojasRuta (pantallas), ServiciosRuta (Photon y OSRM provisionales), ModelosRuta
    Mapa/MapaRutas.swift         Rutas en el mapa (azul / gris), tiempos, pin, encuadre y cámara al navegar
    Mapa/EstiloMapa.swift        Estilo del mapa en código (paletas de styles/), escrito como JSON
    Mapa/EstiloRonda1.swift      Ronda 1: calles por clase, puentes, túneles, escudos, arena y agua
    Mapa/Escudos.swift           Escudos de autopista dibujados en código (estirables)
    Mapa/MapaMapLibre.swift      MLNMapView en SwiftUI, zonas, toques y medidas
    Experimentos/                Lista de experimentos y pantalla del mapa
    Resources/                   Assets (Lucide, ícono, color) y licencia de Lucide
```

El estilo replica `viewers/web/src/map/style.js` con las paletas de `styles/base-light.js` y `styles/base-dark.js`. Si cambian allí, hay que cambiarlo también en `EstiloMapa.swift` (pendiente: un único estilo JSON compartido por web e iOS).

## Regenerar las letras

Los glifos se generaron con [fontnik](https://github.com/mapbox/node-fontnik) 0.7.7 a partir de `styles/fonts/DMSans-*.ttf`:

```sh
npx --yes -p fontnik@0.7.7 build-glyphs styles/fonts/DMSans-Regular.ttf styles/glifos/DMSans-Regular
npx --yes -p fontnik@0.7.7 build-glyphs styles/fonts/DMSans-SemiBold.ttf styles/glifos/DMSans-SemiBold
```

El nombre de la carpeta (`DMSans-Regular`, `DMSans-SemiBold`, `DMSans-Italic`) es el que va en `text-font` del estilo. La itálica es una instancia estática (opsz 9, wght 400) de la DM Sans Italic variable de Google Fonts.

## Limitaciones conocidas

- Las fuentes PMTiles no admiten los paquetes de descarga offline de MapLibre; aquí todo va dentro del app.
- Los cuadros por segundo son los que dibuja MapLibre mientras el mapa se mueve; en reposo no hay medida.
- Escrito sin Xcode a mano: si algo no compila, copiar el error tal cual.

## Referencias

- [Primer mapa SwiftUI con MapLibre](https://maplibre.org/maplibre-native/ios/latest/documentation/maplibre-native-for-ios/gettingstarted/)
- [PMTiles local y remoto en iOS](https://maplibre.org/maplibre-native/ios/latest/documentation/maplibre-native-for-ios/pmtiles/)
