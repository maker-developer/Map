# Ronda 1 · Calles, playas y agua

**Objetivo:** que el mapa se lea de un vistazo como el de Apple (jerarquía clara de vías) y tenga lo que Apple no cuida: arena en las playas, la bahía con su profundidad y los nombres del agua.

**Estado:** 🟡 en curso

## Codex (rama `codex/datos`)

- [ ] **C1. Calles con jerarquía.** Añadir a `calles` las propiedades `clase`, `puente`, `tunel` y `ref` según [`capas.md`](capas.md). Mantener `name` y `kind`. Documentar en `data/SOURCES.md` la tabla CLASS → `clase` y de dónde salen puente, túnel y número de vía.
- [ ] **C2. Playas.** Nueva capa `playas` (polígonos con `name`) en `base.pmtiles`. Documentar la fuente.
- [ ] **C3. Profundidad del agua.** Nueva capa `profundidad` con bandas `0-1`, `1-2`, `2-5`, `5-10`, `10+` desde la batimetría de NOAA, simplificada para que `base.pmtiles` no crezca más de ~10 MB.
- [ ] **C4. Nombres del agua.** `name` relleno en las masas de agua principales, o capas `agua-nombres` (puntos) y `agua-ejes` (líneas de ríos) si la fuente no los trae.
- [ ] **C5. Publicar.** Regenerar `public/data/` en `codex/datos` y subir a R2 en `v2/` (sin borrar `v1/`). Anotar abajo en «Entregado» los tamaños y cualquier nombre que cambie.
- [ ] **C6. Compilar.** Cuando Claude marque A5, fusionar `codex/datos` → `claude/laboratorio-ios` (solo `public/data/` y `data/`), compilar Map Lab y dejarlo en el iPhone. Errores de compilación: arreglo mínimo con commit `Compilación: …`.

## Claude (rama `claude/laboratorio-ios`)

- [ ] **A1. Jerarquía de calles.** Estilo por `clase` (autopista cálida con borde, avenida blanca con borde fino, local fina, servicio tenue; rampas más finas). Mientras no llegue `clase`, usar `kind` como hoy. Puentes con borde de sombra, túneles punteados. Ancho real en metros a zoom 18+.
- [ ] **A2. Escudos de autopista.** Escudos propios para `ref` (I, US, SR, Turnpike) como íconos del estilo, en iOS y web.
- [ ] **A3. Playas y agua.** Arena para `playas`; `profundidad` en degradado turquesa (claro poco profundo → oscuro profundo) en claro y oscuro; nombres de agua en cursiva siguiendo los ríos. Generar glifos de DM Sans Italic.
- [ ] **A4. Experimento «Ronda 1».** En Map Lab, un experimento con interruptor «Antes / Después» para comparar el estilo actual con el nuevo en Brickell, Miami Beach y la bahía.
- [ ] **A5. Visor web.** Los mismos cambios en `viewers/web/src/map/style.js` y paletas en `styles/`, para comparar en la Mac.

## Pedidos entre los dos

- Claude → Codex: los nombres de propiedades de [`capas.md`](capas.md). Si CLASS no permite distinguir algo (p. ej. rampas), decirlo aquí y lo resolvemos con otra regla.
- Codex → Claude: *(vacío)*

## Entregado

| Quién | Qué | Dónde | Notas |
| --- | --- | --- | --- |
| | | | |

## Probar (el dueño, en el iPhone)

En Map Lab, experimento **Ronda 1**, con el interruptor Antes / Después:

1. **Condado entero:** ¿se distinguen de un vistazo las autopistas (I-95, 836, Turnpike) de las avenidas y las calles?
2. **Brickell inclinado:** ¿se leen los puentes sobre el río y las rampas de la I-95?
3. **Miami Beach:** ¿se ve la arena de la playa de punta a punta?
4. **Bahía de Biscayne:** ¿se nota la profundidad (más claro cerca de la costa)?
5. **Nombres del agua:** ¿salen Biscayne Bay y Miami River, y el del río sigue su curva?
6. **Modo oscuro:** lo mismo de noche: ¿se lee todo?
7. **Rendimiento:** en el panel de medidas, ¿el primer dibujo y los cuadros/s son parecidos a antes?

Mandar una captura de cada punto (antes y después) y lo que guste o no. Con eso se abre la ronda 2.
