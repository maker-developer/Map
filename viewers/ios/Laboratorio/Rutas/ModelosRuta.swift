import Foundation
import CoreLocation

/// Un sitio al que ir (o desde el que salir): resultado de búsqueda, pin del mapa o «Mi ubicación».
struct Lugar: Identifiable, Equatable {
    let id = UUID()
    var nombre: String
    var subtitulo: String
    var coordenada: CLLocationCoordinate2D
    var esMiUbicacion = false

    static func == (a: Lugar, b: Lugar) -> Bool { a.id == b.id }

    static func miUbicacion(_ coordenada: CLLocationCoordinate2D) -> Lugar {
        Lugar(nombre: "Mi ubicación", subtitulo: "", coordenada: coordenada, esMiUbicacion: true)
    }
}

/// Cómo vas: como las pestañas de Apple Maps y Google Maps.
enum ModoRuta: String, CaseIterable, Identifiable {
    case coche, pie, bici

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .coche: "Coche"
        case .pie: "A pie"
        case .bici: "Bici"
        }
    }

    var icono: Lc {
        switch self {
        case .coche: .coche
        case .pie: .pasos
        case .bici: .bici
        }
    }

    /// Distancia a la que se pasa a la siguiente maniobra (más en coche: vas más rápido).
    var radioManiobra: CLLocationDistance {
        switch self {
        case .coche: 35
        case .pie: 15
        case .bici: 22
        }
    }
}

/// Un paso de la ruta: «Gira a la derecha en SW 8th St».
struct Paso: Identifiable {
    let id: Int
    let instruccion: String
    let calle: String
    /// Metros desde esta maniobra hasta la siguiente.
    let distancia: CLLocationDistance
    let duracion: TimeInterval
    let icono: Lc
    /// Dónde está la maniobra.
    let ubicacion: CLLocationCoordinate2D
}

/// Una ruta posible entre origen y destino.
struct Ruta: Identifiable {
    let id: Int
    let duracion: TimeInterval
    let distancia: CLLocationDistance
    let coordenadas: [CLLocationCoordinate2D]
    let pasos: [Paso]
    /// «por I-95 N» (las vías principales del recorrido).
    let via: String

    var minutos: Int { max(1, Int((duracion / 60).rounded())) }
    var llegada: Date { Date().addingTimeInterval(duracion) }
}

// MARK: - Formatos

enum FormatoRuta {
    /// «12 min», «1 h 5 min».
    static func duracion(_ segundos: TimeInterval) -> String {
        let minutos = max(1, Int((segundos / 60).rounded()))
        if minutos < 60 { return "\(minutos) min" }
        let h = minutos / 60, m = minutos % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// «350 ft», «2,4 mi» o «120 m», «3,1 km» según la región del iPhone.
    static func distancia(_ metros: CLLocationDistance) -> String {
        Measurement(value: metros, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    /// «10:42 a. m.» según la configuración del iPhone.
    static func hora(_ fecha: Date) -> String {
        fecha.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Maniobras en español (a partir de OSRM)

enum Maniobra {
    /// Instrucción y flecha Lucide para un paso de OSRM (`maneuver.type`, `maneuver.modifier`).
    static func describir(tipo: String, modificador: String?, calle: String, salida: Int?) -> (String, Lc) {
        let en = calle.isEmpty ? "" : " en \(calle)"
        let hacia = calle.isEmpty ? "" : " hacia \(calle)"
        let por = calle.isEmpty ? "" : " por \(calle)"
        let (giro, icono) = giro(modificador)

        switch tipo {
        case "depart":
            return ("Sal\(por.isEmpty ? "" : por)", .navegar)
        case "arrive":
            return ("Llegas a tu destino", .bandera)
        case "turn", "end of road":
            if modificador == "uturn" { return ("Da la vuelta\(en)", .vuelta) }
            if modificador == "straight" { return ("Sigue recto\(por)", .flechaArriba) }
            return ("\(giro)\(en)", icono)
        case "continue", "new name":
            if modificador == "uturn" { return ("Da la vuelta\(en)", .vuelta) }
            if let modificador, modificador.contains("left") || modificador.contains("right") {
                return ("\(giro)\(en)", icono)
            }
            return ("Sigue\(por.isEmpty ? " recto" : por)", .flechaArriba)
        case "merge":
            return ("Incorpórate\(calle.isEmpty ? "" : " a \(calle)")", .incorporar)
        case "on ramp":
            return ("Toma la rampa\(hacia)", icono == .flechaArriba ? .diagonalDerecha : icono)
        case "off ramp":
            return ("Toma la salida\(hacia)", icono == .flechaArriba ? .diagonalDerecha : icono)
        case "fork":
            let lado = (modificador ?? "").contains("left") ? "izquierda" : "derecha"
            return ("Mantente a la \(lado)\(hacia)", lado == "izquierda" ? .diagonalIzquierda : .diagonalDerecha)
        case "roundabout", "rotary", "roundabout turn":
            let numero = salida.map { "\($0).ª " } ?? ""
            return ("En la rotonda, toma la \(numero)salida\(hacia)", .rotonda)
        case "exit roundabout", "exit rotary":
            return ("Sal de la rotonda\(hacia)", .diagonalDerecha)
        default:
            return ("Sigue\(por.isEmpty ? " recto" : por)", .flechaArriba)
        }
    }

    private static func giro(_ modificador: String?) -> (String, Lc) {
        switch modificador {
        case "right": return ("Gira a la derecha", Lc.giroDerecha)
        case "sharp right": return ("Gira bruscamente a la derecha", Lc.giroDerecha)
        case "slight right": return ("Gira ligeramente a la derecha", Lc.diagonalDerecha)
        case "left": return ("Gira a la izquierda", Lc.giroIzquierda)
        case "sharp left": return ("Gira bruscamente a la izquierda", Lc.giroIzquierda)
        case "slight left": return ("Gira ligeramente a la izquierda", Lc.diagonalIzquierda)
        case "uturn": return ("Da la vuelta", Lc.vuelta)
        default: return ("Sigue recto", Lc.flechaArriba)
        }
    }
}
