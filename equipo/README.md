# Cómo trabajamos: Claude + Codex + Cursor

Tres agentes trabajan en este repositorio al mismo tiempo, cada uno en su parte, por **rondas**. El dueño del proyecto prueba en su iPhone (y en la web) al final de cada ronda y decide la siguiente.

## Quién hace qué

| | **Claude** (en la nube) | **Codex** (en la Mac) | **Cursor** (en la Mac) |
| --- | --- | --- | --- |
| Se ocupa de | **App iOS y estilo del mapa** | **Datos, nube y compilar iOS** | **App web y pruebas automáticas** |
| Puede | Escribir estilo, Swift, JS y documentos. Revisar capturas. | Compilar con Xcode, instalar en el iPhone, descargar datos del condado y de NOAA, correr Tippecanoe, subir a R2. | Correr el visor web, Playwright, Node; preparar GitHub Actions. |
| No puede | Compilar iOS. Descargar de los servidores del condado ni de R2 (la red de su sesión los bloquea). | — | — |
| Es dueño de | `styles/` (paletas, letras, glifos), `viewers/ios/`, `viewers/web/src/map/` (estilo y edificios, compartido con iOS) | `data/`, `public/data/`, el bucket R2 | `viewers/web/` **menos** `src/map/`: `index.html`, `src/main.js`, `src/features/`, `src/ui/`, `viewer.css`, `vite.config.js`; `package*.json`; `tests/`; `.github/` |
| Compartido | `equipo/` (cada uno solo edita su sección, sus pedidos y su línea del registro) | | |

Regla de oro: **nadie edita archivos de otro.** Si hace falta un cambio en la parte de otro, se pide en la sección «Pedidos» de la ronda.

**El estilo del mapa es uno solo:** lo diseña Claude en `viewers/web/src/map/style.js` (web) y `viewers/ios/Laboratorio/Mapa/` (iOS), con las paletas de `styles/`. Cursor lo usa tal cual en la web (`baseStyle`, `applyTheme`, `addShieldImages`, `buildingLayers`); si necesita algo distinto, lo pide.

## Ramas

| Rama | Quién | Para qué |
| --- | --- | --- |
| `claude/laboratorio-ios` | Claude | App iOS, estilo. **Es también la rama donde se juntan las tres partes** antes de probar. |
| `codex/datos` | Codex | Generador de datos, PMTiles, índices, R2 |
| `cursor/web` | Cursor | App web, pruebas automáticas, GitHub Actions |
| `main` | El dueño | Se fusiona al cerrar cada ronda, cuando él lo aprueba |

**Cómo se juntan:** al terminar sus tareas de la ronda, Codex y Cursor fusionan **solo sus propios archivos** en `claude/laboratorio-ios` (Codex: `data/`, `public/data/`; Cursor: los suyos de la tabla). Así el dueño prueba todo junto.

Excepción acordada: **arreglos de compilación.** Si el app iOS no compila, Codex lo corrige con el cambio mínimo **en `claude/laboratorio-ios`**, en un commit que empiece por `Compilación:` y sin tocar el diseño. Si la web no arranca por un cambio de estilo, Cursor avisa en «Pedidos» (no edita `src/map/`).

## El ciclo de cada ronda

1. **Cada uno hace sus tareas** de `ronda-NN.md`, en su rama, y marca ✅ al terminar.
2. **Codex sube los datos** nuevos (R2 y `public/data/`) y avisa en la ronda qué cambió.
3. **Claude ajusta el estilo** a los datos si hace falta (el contrato está en `capas.md`).
4. **Cursor** corre las pruebas automáticas (capturas de zonas fijas y validación del estilo) sobre `claude/laboratorio-ios` y deja el resultado en la ronda.
5. **Codex compila** el app iOS desde `claude/laboratorio-ios` y lo instala en el iPhone.
6. **El dueño prueba** en el iPhone y en la web con la lista «Probar» de la ronda y manda capturas o comentarios.
7. Se anota en `registro.md` y se abre la ronda siguiente (`ronda-NN+1.md`).

## Archivos de esta carpeta

- [`hoja-de-ruta.md`](hoja-de-ruta.md): todas las rondas previstas, en orden.
- [`capas.md`](capas.md): el contrato de datos. Qué capas y propiedades produce Codex y usan Claude y Cursor.
- [`cursor.md`](cursor.md): el arranque de Cursor (sus primeras tareas).
- [`ronda-01.md`](ronda-01.md), [`ronda-02.md`](ronda-02.md): las rondas, con las tareas de cada uno, pedidos y la lista para probar.
- [`registro.md`](registro.md): qué se hizo en cada ronda y qué decidió el dueño.

## Cómo compilar Map Lab

```sh
git fetch origin && git checkout claude/laboratorio-ios && git pull
cd viewers/ios && xcodegen generate && open Laboratorio.xcodeproj
```

Detalles en [`viewers/ios/README.md`](../viewers/ios/README.md).
