import Foundation
import CoreLocation
import Observation

/// Casa, Trabajo, lugares guardados y recientes, como en Apple Maps y Google Maps.
/// Se guardan en el iPhone (UserDefaults) y sobreviven al cerrar el app.
@MainActor
@Observable
final class Favoritos {
    /// Un lugar guardado (Lugar no se guarda tal cual: su id cambia en cada sesión).
    struct Guardado: Codable, Equatable {
        var nombre: String
        var subtitulo: String
        var lat: Double
        var lon: Double

        init(_ lugar: Lugar) {
            nombre = lugar.nombre
            subtitulo = lugar.subtitulo
            lat = lugar.coordenada.latitude
            lon = lugar.coordenada.longitude
        }

        var lugar: Lugar {
            Lugar(nombre: nombre, subtitulo: subtitulo, coordenada: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        /// Mismo sitio (a menos de ~15 m), aunque el nombre cambie.
        func esElMismo(que otro: Lugar) -> Bool {
            abs(lat - otro.coordenada.latitude) < 0.00015 && abs(lon - otro.coordenada.longitude) < 0.00015
        }
    }

    private struct Datos: Codable {
        var casa: Guardado?
        var trabajo: Guardado?
        var guardados: [Guardado] = []
        var recientes: [Guardado] = []
    }

    private static let clave = "favoritosMapa"
    private static let maximoRecientes = 8

    private(set) var casa: Guardado?
    private(set) var trabajo: Guardado?
    private(set) var guardados: [Guardado] = []
    private(set) var recientes: [Guardado] = []

    init() {
        if let datos = UserDefaults.standard.data(forKey: Self.clave),
           let d = try? JSONDecoder().decode(Datos.self, from: datos) {
            casa = d.casa
            trabajo = d.trabajo
            guardados = d.guardados
            recientes = d.recientes
        }
    }

    func esGuardado(_ lugar: Lugar) -> Bool { guardados.contains { $0.esElMismo(que: lugar) } }

    func alternarGuardado(_ lugar: Lugar) {
        if let i = guardados.firstIndex(where: { $0.esElMismo(que: lugar) }) {
            guardados.remove(at: i)
        } else {
            guardados.insert(Guardado(lugar), at: 0)
        }
        persistir()
    }

    func ponerCasa(_ lugar: Lugar) { casa = Guardado(lugar); persistir() }
    func ponerTrabajo(_ lugar: Lugar) { trabajo = Guardado(lugar); persistir() }

    /// Cada lugar elegido pasa al principio de los recientes (sin repetir).
    func registrar(_ lugar: Lugar) {
        guard !lugar.esMiUbicacion else { return }
        recientes.removeAll { $0.esElMismo(que: lugar) }
        recientes.insert(Guardado(lugar), at: 0)
        if recientes.count > Self.maximoRecientes { recientes.removeLast(recientes.count - Self.maximoRecientes) }
        persistir()
    }

    func borrarRecientes() { recientes = []; persistir() }

    private func persistir() {
        let d = Datos(casa: casa, trabajo: trabajo, guardados: guardados, recientes: recientes)
        if let datos = try? JSONEncoder().encode(d) { UserDefaults.standard.set(datos, forKey: Self.clave) }
    }
}
