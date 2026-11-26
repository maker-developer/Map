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
    case compartir = "share"
    case guardar = "bookmark"
    case guardado = "bookmark-check"
    case copiar = "copy"
    case abrirFuera = "external-link"
    case casa = "house"
    case trabajo = "briefcase"
    case recientes = "clock"
    case listaPasos = "list-ordered"
    // Ficha de negocios
    case telefono = "phone"
    case web = "globe"
    case correo = "mail"
    case foto = "image"
    case tarjeta = "credit-card"
    case comida = "utensils"
    case accesible = "accessibility"
    case wifi = "wifi"
    case tienda = "store"
    case etiqueta = "tag"
    case verificado = "badge-check"
    case compras = "shopping-bag"
    case entrega = "truck"
    case asiento = "armchair"
    case horario = "calendar-clock"
    case hoja = "leaf"
    case enlace = "link"
    case arroba = "at-sign"

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
    func vidrio<S: Shape>(_ forma: S, interactivo: Bool = false, tinte: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tinte).interactive(interactivo), in: forma)
        } else {
            self.background {
                ZStack {
                    forma.fill(.regularMaterial)
                    if let tinte { forma.fill(tinte.opacity(0.18)) }
                }
            }
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

// MARK: - Fluidez

/// Botón que se hunde un poco al pulsarlo, con resorte (como los controles de Apple Maps).
struct EstiloPresionable: ButtonStyle {
    var escala: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? escala : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == EstiloPresionable {
    static var presionable: EstiloPresionable { EstiloPresionable() }
}

/// Fondo de las piezas dentro de las hojas: translúcido sobre el vidrio (no bloques blancos).
extension View {
    func fondoPieza(radio: CGFloat = 16) -> some View {
        background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: radio, style: .continuous))
    }
}
