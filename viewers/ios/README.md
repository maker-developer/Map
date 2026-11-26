# Map Lab (iOS)

App nativa de pruebas del mapa propio, con SwiftUI, MapLibre Native e íconos Lucide. Sirve para medir en un iPhone real cada mejora del mapa antes de llevarla a otro proyecto (Busdade u otros).

- **Mapa:** MapLibre Native para iOS 6.x por Swift Package Manager. Lee los mismos PMTiles que el visor web (`public/data/`) con `pmtiles://file://`, soportado desde MapLibre iOS 6.10.0.
- **Letras:** DM Sans en formato de glifos de MapLibre (`styles/glifos/`), dentro del app. Funciona sin internet.
- **Íconos:** Lucide (licencia ISC, `Laboratorio/Resources/LICENSE-lucide.txt`) como SVG en Assets › Lucide.
- **iOS 18 o posterior.** En iOS 26 los controles usan Liquid Glass; antes, material del sistema.

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
| Mapa base | Todo el condado | Carga, nombres legibles, acercar y alejar fluido |
| Edificios en 3D | Brickell | «Los edificios tapan» encendido y apagado |
| Rutas y paradas | Brickell | Distinguir estaciones de tren y paradas de bus |
| Modo oscuro | Miami Beach | Contraste de agua, parques y nombres |
| Rendimiento | Miami Lakes | Cuadros por segundo, memoria y primer dibujo |

Controles a la derecha del mapa (de arriba abajo): zona, capas (3D, «los edificios tapan», transporte, inclinación), tema claro/oscuro, medidas y mi ubicación. Al tocar un edificio sale su dirección y altura; al tocar una parada, su nombre y rutas.

**«Los edificios tapan»:** los nombres de calles, rutas y paradas se dibujan antes que los edificios, así una torre tapa lo que queda detrás. Apagado, se comporta como el visor web actual (todo flota encima).

## Datos desde la Mac

Para probar teselas nuevas sin volver a compilar: en la Mac, desde la raíz del repositorio, `npm run dev`. En el app, *Datos desde la Mac*, escribir la dirección «Network» que muestra Vite (por ejemplo `http://192.168.1.20:4180`). El app pide los PMTiles a la Mac por la Wi-Fi; las letras siguen saliendo del app.

## Estructura

```text
viewers/ios/
  project.yml                    Proyecto de XcodeGen (MapLibre, datos y letras como recursos)
  Laboratorio/
    App/                         Entrada del app, íconos Lucide, vidrio y textos
    Mapa/EstiloMapa.swift        Estilo del mapa en código (paletas de styles/), escrito como JSON
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

El nombre de la carpeta (`DMSans-Regular`, `DMSans-SemiBold`) es el que va en `text-font` del estilo.

## Limitaciones conocidas

- Las fuentes PMTiles no admiten los paquetes de descarga offline de MapLibre; aquí todo va dentro del app.
- Los cuadros por segundo son los que dibuja MapLibre mientras el mapa se mueve; en reposo no hay medida.
- Escrito sin Xcode a mano: si algo no compila, copiar el error tal cual.

## Referencias

- [Primer mapa SwiftUI con MapLibre](https://maplibre.org/maplibre-native/ios/latest/documentation/maplibre-native-for-ios/gettingstarted/)
- [PMTiles local y remoto en iOS](https://maplibre.org/maplibre-native/ios/latest/documentation/maplibre-native-for-ios/pmtiles/)
