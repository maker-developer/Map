import Foundation

/// Ronda 1 del diseño (ver `equipo/ronda-01.md`): calles con jerarquía, puentes y túneles,
/// escudos de autopista, arena en las playas, la bahía por profundidad y los nombres del agua.
///
/// Usa las propiedades nuevas que entrega Codex (`clase`, `puente`, `tunel`, `ref`, `red`,
/// capas `playas`, `profundidad`, `agua-nombres`, `agua-ejes`). Mientras no lleguen, la clase sale
/// del campo `kind` (CLASS del condado) y las capas que faltan simplemente no se dibujan.
/// El mismo estilo está en `viewers/web/src/map/style.js` (`ronda1`).
extension EstiloMapa {

    // MARK: - Paleta de la ronda 1

    struct PaletaRonda1 {
        let autopista, autopistaBorde, principal, principalBorde, avenida, avenidaBorde: String
        let local, localBorde, servicio, peatonal, puenteSombra: String
        let arena, arenaBorde: String
        /// Agua de menos a más profundidad: 0-1, 1-2, 2-5, 5-10, 10+ m.
        let profundidad: [String]
        let aguaTexto, aguaHalo: String
    }

    static func paletaRonda1(_ tema: Tema) -> PaletaRonda1 {
        switch tema {
        case .claro:
            PaletaRonda1(
                autopista: "#f9d57c", autopistaBorde: "#e4b456",
                principal: "#b3b8bb", principalBorde: "#fbfbf9",
                avenida: "#bec2c5", avenidaBorde: "#fbfbf9",
                local: "#c9ccce", localBorde: "#fbfbf9",
                servicio: "#d8dadb", peatonal: "#e9dcc9", puenteSombra: "#3d4a52",
                arena: "#f6edd1", arenaBorde: "#ece0bc",
                profundidad: ["#bde5f7", "#aedcf4", "#9cd4f1", "#8bcaec", "#79bfe6"],
                aguaTexto: "#4b88ab", aguaHalo: "#c9e9f8"
            )
        case .oscuro:
            PaletaRonda1(
                autopista: "#7a6334", autopistaBorde: "#4a3b1f",
                principal: "#50555a", principalBorde: "#141618",
                avenida: "#474c51", avenidaBorde: "#141618",
                local: "#3c4044", localBorde: "#191b1d",
                servicio: "#33373a", peatonal: "#4a4237", puenteSombra: "#000000",
                arena: "#3d3827", arenaBorde: "#4a4430",
                profundidad: ["#2c5470", "#264b65", "#21435a", "#1c3a4f", "#173244"],
                aguaTexto: "#8fbad8", aguaHalo: "#172b3a"
            )
        }
    }

    // MARK: - Expresiones comunes

    /// Clase de la vía: `clase` de Codex o, mientras no llegue, el CLASS del condado (`kind`).
    /// kind: 0 rampa · 1 autopista · 2 principal · 3 avenida · 4 colectora · 5 local · 6–8 servicio · 9 peatonal.
    static let clase: [Any] = [
        "coalesce", ["get", "clase"],
        ["match", ["get", "kind"],
         "0", "rampa", "1", "autopista", "2", "principal", "3", "avenida",
         "4", "colectora", "5", "local", "9", "peatonal", "servicio"],
    ]

    private static let noTunel: [Any] = ["!=", ["get", "tunel"], true]
    private static let noPuente: [Any] = ["!=", ["get", "puente"], true]
    private static func esClase(_ valores: [String]) -> [Any] {
        ["in", clase, ["literal", valores]]
    }

    /// Ancho de una clase en píxeles según el zoom. Crece 1,6× por nivel, de modo que desde el
    /// zoom 18 las calles se acercan a su ancho real en metros (ya no parecen líneas dibujadas).
    private static func ancho(_ paradas: [(Double, Double)], extra: Double = 0) -> [Any] {
        var expresion: [Any] = ["interpolate", ["exponential", 1.6], ["zoom"]]
        for (zoom, px) in paradas {
            expresion.append(zoom)
            // El borde crece un poco con el zoom para que se siga viendo en las calles anchas.
            expresion.append(px + extra * (zoom >= 17 ? 1.6 : 1))
        }
        return expresion
    }

    private static let anchos: [String: [(Double, Double)]] = [
        "autopista": [(7, 0.8), (10, 1.6), (13, 3.6), (15, 7), (17, 15), (18, 26), (20, 90)],
        "rampa": [(11, 0.6), (13, 1.6), (15, 3.4), (17, 8), (18, 13), (20, 46)],
        "principal": [(8, 0.6), (11, 1.2), (13, 2.6), (15, 5.4), (17, 12), (18, 20), (20, 72)],
        "avenida": [(10, 0.5), (12, 0.9), (14, 2.4), (16, 5.6), (17, 9), (18, 16), (20, 58)],
        "colectora": [(11, 0.4), (13, 0.8), (15, 2.6), (17, 7), (18, 12), (20, 42)],
        "local": [(12, 0.3), (14, 0.9), (16, 3), (17, 5.4), (18, 9.5), (20, 34)],
        "servicio": [(14, 0.4), (16, 1.6), (18, 5), (20, 16)],
        "peatonal": [(14, 0.6), (16, 2.2), (18, 6.5), (20, 22)],
    ]

    private static let lineasR1: [String: Any] = ["line-cap": "round", "line-join": "round"]

    // MARK: - Suelo y calles

    func capasSueloRonda1(_ p: Paleta, _ r: PaletaRonda1) -> [[String: Any]] {
        var capas: [[String: Any]] = [
            ["id": "background", "type": "background", "paint": ["background-color": p.background]],
            ["id": "land", "type": "fill", "source": "base", "source-layer": "condado",
             "paint": ["fill-color": p.land]],
            // Arena: de Miami Beach a Key Biscayne.
            ["id": "playas", "type": "fill", "source": "base", "source-layer": "playas", "minzoom": 9,
             "paint": ["fill-color": r.arena, "fill-outline-color": r.arenaBorde]],
            ["id": "parks", "type": "fill", "source": "base", "source-layer": "parques",
             "paint": ["fill-color": p.park, "fill-outline-color": p.parkOutline]],
            ["id": "water", "type": "fill", "source": "base", "source-layer": "agua",
             // Turquesa intermedio de base: la capa «profundidad» pinta encima lo claro y lo hondo.
             "paint": ["fill-color": r.profundidad[2], "fill-outline-color": p.waterOutline]],
            // La bahía por profundidad: turquesa claro en lo poco profundo, más oscuro en lo hondo.
            ["id": "profundidad", "type": "fill", "source": "base", "source-layer": "profundidad",
             "paint": [
                "fill-antialias": false,
                "fill-color": ["match", ["get", "banda"],
                               "0-1", r.profundidad[0], "1-2", r.profundidad[1], "2-5", r.profundidad[2],
                               "5-10", r.profundidad[3], r.profundidad[4]],
             ]],
            ["id": "county-line", "type": "line", "source": "base", "source-layer": "condado", "maxzoom": 12,
             "paint": ["line-color": p.boundary, "line-width": 1.1, "line-dasharray": [3, 2]]],
        ]
        capas += tuneles(r)
        // De menos a más importante: las vías grandes quedan encima en los cruces.
        for clase in ["servicio", "local", "colectora", "avenida", "principal", "rampa", "autopista"] {
            capas += via(clase, r, filtro: ["all", Self.esClase([clase]), Self.noTunel, Self.noPuente])
        }
        capas.append(peatonal(r))
        capas += puentes(r)
        return capas
    }

    private func colores(_ clase: String, _ r: PaletaRonda1) -> (relleno: String, borde: String?) {
        switch clase {
        case "autopista", "rampa": return (r.autopista, r.autopistaBorde)
        case "principal": return (r.principal, r.principalBorde)
        case "avenida", "colectora": return (r.avenida, r.avenidaBorde)
        case "local": return (r.local, r.localBorde)
        default: return (r.servicio, nil)
        }
    }

    private func minimoZoom(_ clase: String) -> Double {
        Self.anchos[clase]?.first?.0 ?? 12
    }

    /// Una clase de vía: borde (si tiene) y relleno.
    private func via(_ clase: String, _ r: PaletaRonda1, filtro: [Any], sufijo: String = "") -> [[String: Any]] {
        guard let paradas = Self.anchos[clase] else { return [] }
        let (relleno, borde) = colores(clase, r)
        var capas: [[String: Any]] = []
        if let borde {
            capas.append([
                "id": "via-\(clase)-borde\(sufijo)", "type": "line", "source": "base", "source-layer": "calles",
                "minzoom": max(minimoZoom(clase), clase == "local" ? 14 : 9), "filter": filtro, "layout": Self.lineasR1,
                "paint": ["line-color": borde, "line-width": Self.ancho(paradas, extra: clase == "autopista" ? 2.2 : 1.6)],
            ])
        }
        capas.append([
            "id": "via-\(clase)\(sufijo)", "type": "line", "source": "base", "source-layer": "calles",
            "minzoom": minimoZoom(clase), "filter": filtro, "layout": Self.lineasR1,
            "paint": ["line-color": relleno, "line-width": Self.ancho(paradas)],
        ])
        return capas
    }

    /// Calles peatonales (Lincoln Road): trazo suave y discontinuo.
    private func peatonal(_ r: PaletaRonda1) -> [String: Any] {
        ["id": "via-peatonal", "type": "line", "source": "base", "source-layer": "calles", "minzoom": 14,
         "filter": ["all", Self.esClase(["peatonal"]), Self.noTunel],
         "layout": ["line-cap": "butt", "line-join": "round"],
         "paint": ["line-color": r.peatonal, "line-width": Self.ancho(Self.anchos["peatonal"]!),
                   "line-dasharray": [1.2, 0.8]]]
    }

    /// Túneles: debajo de todo, borde punteado y relleno apagado.
    private func tuneles(_ r: PaletaRonda1) -> [[String: Any]] {
        let filtro: [Any] = ["==", ["get", "tunel"], true]
        return [
            ["id": "tuneles-borde", "type": "line", "source": "base", "source-layer": "calles", "minzoom": 12,
             "filter": filtro, "layout": ["line-cap": "butt", "line-join": "round"],
             "paint": ["line-color": r.autopistaBorde, "line-opacity": 0.6, "line-dasharray": [1.5, 1],
                       "line-width": Self.ancho(Self.anchos["principal"]!, extra: 1.6)]],
            ["id": "tuneles", "type": "line", "source": "base", "source-layer": "calles", "minzoom": 12,
             "filter": filtro, "layout": Self.lineasR1,
             "paint": ["line-color": r.local, "line-opacity": 0.55,
                       "line-width": Self.ancho(Self.anchos["principal"]!)]],
        ]
    }

    /// Puentes: encima de todo, con una sombra suave debajo que los levanta del agua.
    private func puentes(_ r: PaletaRonda1) -> [[String: Any]] {
        let sombra: [String: Any] = [
            "id": "puentes-sombra", "type": "line", "source": "base", "source-layer": "calles", "minzoom": 13,
            "filter": ["==", ["get", "puente"], true], "layout": Self.lineasR1,
            "paint": ["line-color": r.puenteSombra, "line-opacity": 0.18, "line-blur": 3, "line-translate": [0, 2],
                      "line-width": Self.ancho(Self.anchos["principal"]!, extra: 5)],
        ]
        var capas = [sombra]
        for clase in ["local", "colectora", "avenida", "principal", "rampa", "autopista"] {
            capas += via(clase, r, filtro: ["all", Self.esClase([clase]), ["==", ["get", "puente"], true]], sufijo: "-puente")
        }
        return capas
    }

    // MARK: - Nombres y escudos

    func capasNombresRonda1(_ p: Paleta, _ r: PaletaRonda1) -> [[String: Any]] {
        let tamanoAgua: [Any] = ["interpolate", ["linear"], ["zoom"], 9, 11, 13, 14, 16, 17]
        let textoAgua: [String: Any] = [
            "text-color": r.aguaTexto, "text-halo-color": r.aguaHalo, "text-halo-width": 1.2,
        ]
        return [
            // Calles: las grandes ganan sitio a las pequeñas cuando no caben todas.
            ["id": "street-names", "type": "symbol", "source": "base", "source-layer": "calles", "minzoom": 13.5,
             "filter": ["all", ["!=", ["get", "name"], ""], ["!", Self.esClase(["rampa", "servicio"])]],
             "layout": [
                "symbol-placement": "line", "symbol-spacing": 220, "text-field": ["get", "name"],
                "text-font": ["match", Self.clase, ["autopista", "principal"], ["literal", ["DMSans-SemiBold"]],
                              ["literal", ["DMSans-Regular"]]],
                "text-max-angle": 35, "text-transform": "uppercase", "text-letter-spacing": 0.06,
                "symbol-sort-key": ["match", Self.clase, "autopista", 1, "principal", 2, "avenida", 3, "colectora", 4, 5],
                "text-size": ["interpolate", ["linear"], ["zoom"],
                              13.5, ["match", Self.clase, ["autopista", "principal"], 10.5, 9.5],
                              18, ["match", Self.clase, ["autopista", "principal"], 14, 12.5]],
             ],
             "paint": ["text-color": p.streetLabel, "text-halo-color": p.halo, "text-halo-width": 1.4]],
            // Escudos de autopista (I-95, US-1, SR-836, Turnpike): el número dentro de su forma.
            ["id": "escudos", "type": "symbol", "source": "base", "source-layer": "calles", "minzoom": 9,
             "filter": ["all", ["has", "ref"], ["!=", ["get", "ref"], ""], Self.esClase(["autopista", "principal"])],
             "layout": [
                "symbol-placement": "line", "symbol-spacing": ["interpolate", ["linear"], ["zoom"], 9, 260, 15, 520],
                "icon-image": ["concat", "escudo-", ["coalesce", ["get", "red"], "otro"]],
                "icon-text-fit": "both", "icon-text-fit-padding": [2, 5, 2, 5],
                "icon-rotation-alignment": "viewport", "text-rotation-alignment": "viewport",
                "text-field": ["get", "ref"], "text-font": ["literal", ["DMSans-SemiBold"]], "text-size": 10.5,
                "symbol-sort-key": 0,
             ],
             "paint": ["text-color": ["match", ["get", "red"], ["I", "TP"], "#ffffff", "#1d2421"]]],
            // Agua: los ríos siguen su curva; la bahía y el océano, en cursiva y espaciados.
            ["id": "agua-ejes", "type": "symbol", "source": "base", "source-layer": "agua-ejes", "minzoom": 12,
             "layout": ["symbol-placement": "line", "symbol-spacing": 320, "text-field": ["get", "name"],
                        "text-font": ["literal", ["DMSans-Italic"]], "text-size": tamanoAgua,
                        "text-letter-spacing": 0.08, "text-max-angle": 30],
             "paint": textoAgua],
            ["id": "agua-nombres", "type": "symbol", "source": "base", "source-layer": "agua-nombres", "minzoom": 8,
             "layout": ["text-field": ["get", "name"], "text-font": ["literal", ["DMSans-Italic"]],
                        "text-size": tamanoAgua, "text-letter-spacing": 0.12, "text-max-width": 7],
             "paint": textoAgua],
            // Lagos y canales con nombre, solo de cerca (de lejos se repetirían por cada tesela).
            ["id": "agua-poligonos-nombres", "type": "symbol", "source": "base", "source-layer": "agua", "minzoom": 14,
             "filter": ["!=", ["coalesce", ["get", "name"], ""], ""],
             "layout": ["text-field": ["get", "name"], "text-font": ["literal", ["DMSans-Italic"]],
                        "text-size": 12, "text-letter-spacing": 0.06, "text-max-width": 7],
             "paint": textoAgua],
        ]
    }
}
