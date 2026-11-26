# Map

Map es un proyecto independiente para construir y mostrar el mapa de Miami-Dade. El diseño del mapa, las capas geográficas, el visor y las funciones opcionales tienen límites separados.

## Abrir el visor

El visor web funciona con los PMTiles que incluye el repositorio.

```sh
npm ci
npm run dev -- --port 4180
```

Abre `http://localhost:4180/`. Para verlo en un iPhone conectado a la misma Wi-Fi, ejecuta Vite con `--host 0.0.0.0` y abre la dirección local de la Mac.

## Estructura

```text
data/
  scripts/       Descarga, selección y compilación de fuentes geográficas
  SOURCES.md     Fuentes, cobertura y notas de licencia
styles/
  base-light.js  Colores para la representación clara
  base-dark.js   Colores para la representación oscura
viewers/
  web/           Visor web de referencia
  ios/           Notas para el visor MapLibre Native
extras/
  search/        Diseño futuro del índice de búsqueda
  routing/       Diseño futuro de rutas para caminar y conducir
public/data/     Archivos de teselas que consume el visor
docs/            Cobertura y registro del proyecto
```

El estilo base y los datos geográficos no dependen del visor web. El transporte es un complemento independiente. La búsqueda y las rutas están documentadas como módulos que todavía no se han implementado.

## Datos incluidos

| Capa | Cantidad |
| --- | ---: |
| Segmentos de calle | 116.465 |
| Polígonos de agua | 5.345 |
| Límites de parques municipales | 563 |
| Huellas de edificio | 605.762 |
| Huellas con altura publicada | 567.911 |
| Paradas del transporte público | 7.038 |
| Recorridos de transporte | 215 |

Las cantidades corresponden a la extracción inicial del 25 de noviembre de 2026. El archivo base de teselas contiene las calles, el agua, los parques y el límite del condado. Transporte y edificios se compilan como archivos PMTiles independientes. Los edificios sin altura se muestran en planta. Los modelos 3D tienen techos planos.

## Actualizar los datos

La generación completa descarga el inventario del condado y el GTFS. Requiere Python 3, Tippecanoe y un GTFS extraído en `data/gtfs/`.

```sh
python3 data/scripts/preparar.py --todo-condado --tippecanoe tippecanoe
```

Añade `--actualizar` para descargar de nuevo las fuentes. Las descargas y archivos intermedios quedan en `data/.cache/`. Las versiones listas para el visor quedan en `public/data/`.

## Visor iOS

MapLibre Native puede leer PMTiles dentro del bundle o desde un servidor compatible. Véanse las [notas de iOS](viewers/ios/README.md).

## Documentación

- [Fuentes de datos](data/SOURCES.md)
- [Diseño de búsqueda](extras/search/README.md)
- [Diseño de rutas](extras/routing/README.md)
- [Decisiones y siguiente alcance](docs/roadmap.md)
