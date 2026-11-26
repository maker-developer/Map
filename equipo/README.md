# Cómo trabajamos: Claude + Codex

Dos agentes trabajan en este repositorio al mismo tiempo, cada uno en su parte, por **rondas**. El dueño del proyecto prueba en su iPhone al final de cada ronda y decide la siguiente.

## Quién hace qué

| | **Claude** (en la nube) | **Codex** (en la Mac) |
| --- | --- | --- |
| Puede | Escribir estilo, Swift, JS y documentos. Revisar capturas. | Compilar con Xcode, instalar en el iPhone, descargar datos del condado y de NOAA, correr Tippecanoe, subir a R2. |
| No puede | Compilar iOS. Descargar de los servidores del condado ni de R2 (la red de su sesión los bloquea). | — |
| Es dueño de | **Diseño y app:** `styles/`, `viewers/ios/`, `viewers/web/src/map/`, `viewers/web/src/features/` | **Datos y publicación:** `data/`, `public/data/`, el bucket R2, `viewers/web/vite.config.js`, `package*.json` |
| Compartido | `equipo/` (cada uno solo edita su sección y su línea del registro) | |

Regla de oro: **nadie edita archivos del otro.** Si hace falta un cambio en la parte del otro, se pide en la sección «Pedidos» de la ronda.

## Ramas

| Rama | Quién | Para qué |
| --- | --- | --- |
| `claude/laboratorio-ios` | Claude | Estilo, app Map Lab y visor web |
| `codex/datos` | Codex | Generador de datos, PMTiles, R2 |
| `main` | El dueño | Se fusiona al cerrar cada ronda, cuando él lo aprueba |

Excepción acordada: **arreglos de compilación.** Cuando Claude termina su parte de la ronda, Codex compila Map Lab. Si algo no compila, Codex lo corrige con el cambio mínimo **en `claude/laboratorio-ios`**, en un commit que empiece por `Compilación:` y sin tocar el diseño. Claude lo revisa en la ronda siguiente.

## El ciclo de cada ronda

1. **Cada uno hace sus tareas** de `ronda-NN.md`, en su rama, y marca ✅ al terminar.
2. **Codex sube los datos** nuevos (R2 y `public/data/`) y avisa en la ronda qué cambió.
3. **Claude ajusta el estilo** a los datos si hace falta (el contrato está en `capas.md`).
4. **Codex compila** Map Lab desde `claude/laboratorio-ios` (con sus datos ya fusionados en `public/data/`) y lo instala en el iPhone.
5. **El dueño prueba** con la lista «Probar» de la ronda y manda capturas o comentarios.
6. Se anota en `registro.md` y se abre la ronda siguiente (`ronda-NN+1.md`).

## Archivos de esta carpeta

- [`hoja-de-ruta.md`](hoja-de-ruta.md): todas las rondas previstas, en orden.
- [`capas.md`](capas.md): el contrato de datos. Qué capas y propiedades produce Codex y usa Claude.
- [`ronda-01.md`](ronda-01.md): la ronda actual, con las tareas de cada uno, pedidos y la lista para probar.
- [`registro.md`](registro.md): qué se hizo en cada ronda y qué decidió el dueño.

## Cómo compilar Map Lab

```sh
git fetch origin && git checkout claude/laboratorio-ios && git pull
cd viewers/ios && xcodegen generate && open Laboratorio.xcodeproj
```

Detalles en [`viewers/ios/README.md`](../viewers/ios/README.md).
