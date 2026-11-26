import SwiftUI

// MARK: - Íconos Lucide

/// Íconos Lucide (ISC, ver Resources/LICENSE-lucide.txt) guardados como SVG en Assets › Lucide.
/// El nombre del caso es el del archivo en lucide.dev (con el prefijo «lc.» en Assets).
enum Lc: String {
    case mapa = "map"
    case pin = "map-pin"
    case bus
    case tren = "train-front"
    case cerrar = "x"
    case flecha = "chevron-right"
    case info
    case alerta = "triangle-alert"
    case ruta = "route"
    case capas = "layers"
    case edificio = "building"
    case luna = "moon"
    case sol = "sun"
    case medidor = "gauge"
    case ubicacion = "locate-fixed"
    case laboratorio = "flask-conical"
    case reloj = "timer"
    case memoria = "memory-stick"
    case monumento = "landmark"
    case brujula = "compass"
    case buscar = "search"
    case ajustes = "settings-2"
    // Rutas y navegación
    case coche = "car"
    case pasos = "footprints"
    case bici = "bike"
    case navegar = "navigation"
    case bandera = "flag"
    case vuelta = "undo-2"
    case flechaArriba = "arrow-up"
    case giroDerecha = "corner-up-right"
    case giroIzquierda = "corner-up-left"
    case diagonalDerecha = "arrow-up-right"
    case diagonalIzquierda = "arrow-up-left"
    case incorporar = "merge"
    case rotonda = "rotate-cw"
    case origen = "circle-dot"
    case invertir = "arrow-up-down"
    case vozSi = "volume-2"
    case vozNo = "volume-x"

    var imagen: Image { Image("lc.\(rawValue)") }
}

/// Un ícono Lucide como plantilla (toma el color de `foregroundStyle`) y crece con la letra del sistema.
struct Icono: View {
    let icono: Lc
    var tamano: CGFloat = 20
    @ScaledMetric private var escala: CGFloat = 1

    init(_ icono: Lc, tamano: CGFloat = 20) {
        self.icono = icono
        self.tamano = tamano
    }

    var body: some View {
        icono.imagen
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: tamano * escala, height: tamano * escala)
            .accessibilityHidden(true)
    }
}

// MARK: - Vidrio

extension View {
    /// Liquid Glass en iOS 26; material del sistema en iOS 18.
    @ViewBuilder
    func vidrio<S: Shape>(_ forma: S, interactivo: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(interactivo), in: forma)
        } else {
            self.background(.regularMaterial, in: forma)
                .overlay(forma.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }
}

/// Botón redondo de vidrio con un ícono Lucide, para los controles sobre el mapa.
struct BotonMapa: View {
    let icono: Lc
    let etiqueta: String
    var activo = false
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Icono(icono, tamano: 19)
                .foregroundStyle(activo ? Color.accentColor : Color.primary)
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .vidrio(Circle(), interactivo: true)
        .accessibilityLabel(etiqueta)
        .accessibilityAddTraits(activo ? .isSelected : [])
    }
}

// MARK: - Textos del condado

enum Texto {
    /// «SE 7 ST@S MIAMI AV» → «SE 7 St y S Miami Av». Los puntos cardinales y siglas cortas
    /// (SE, NW, US, FL…) quedan en mayúsculas; el resto, con la primera en mayúscula.
    static func bonito(_ texto: String) -> String {
        let siglas: Set<String> = ["N", "S", "E", "W", "NE", "NW", "SE", "SW", "US", "FL", "I-95", "SR", "MDC", "FIU", "UM"]
        let limpio = texto.replacingOccurrences(of: "@", with: " y ")
        return limpio.split(separator: " ", omittingEmptySubsequences: true).map { palabra in
            let p = String(palabra)
            if siglas.contains(p.uppercased()) { return p.uppercased() }
            if p.first?.isNumber == true { return p.lowercased() } // «7TH» → «7th»
            return p.lowercased().capitalized // «(WEST» → «(West»
        }.joined(separator: " ")
    }
}
