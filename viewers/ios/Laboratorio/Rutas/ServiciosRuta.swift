import Foundation
import CoreLocation

/// Búsqueda de lugares y cálculo de rutas.
///
/// **Provisional, solo para probar la experiencia:** usa servicios públicos basados en
/// OpenStreetMap: Photon (komoot) para buscar y OSRM de FOSSGIS (routing.openstreetmap.de) para
/// las rutas. Tienen un uso justo limitado y no sirven para un app publicada.
/// Se sustituyen por el índice propio (ronda 2) y el motor de rutas propio (rondas 3 y 4)
/// cambiando solo este archivo: la experiencia (Navegador y hojas) no cambia.
enum ServiciosRuta {
    /// Caja de Miami-Dade (y un poco alrededor) para que la búsqueda no salga de aquí.
    private static let caja = "-80.95,25.10,-80.00,26.05"
    private static let agente = "Map-Laboratorio/0.1 (prueba de experiencia; iOS)"

    enum Fallo: LocalizedError {
        case sinRuta
        case servicio(String)

        var errorDescription: String? {
            switch self {
            case .sinRuta: "No encontramos una ruta hasta ahí."
            case .servicio(let detalle): "El servicio de rutas no respondió (\(detalle))."
            }
        }
    }

    // MARK: - Búsqueda (Photon)

    static func buscar(_ texto: String, cerca: CLLocationCoordinate2D?) async throws -> [Lugar] {
        var c = URLComponents(string: "https://photon.komoot.io/api/")!
        var items = [
            URLQueryItem(name: "q", value: texto),
            URLQueryItem(name: "limit", value: "8"),
            URLQueryItem(name: "bbox", value: caja),
        ]
        if let cerca {
            items += [URLQueryItem(name: "lat", value: String(cerca.latitude)),
                      URLQueryItem(name: "lon", value: String(cerca.longitude))]
        }
        c.queryItems = items
        let datos = try await pedir(c.url!)
        return lugares(de: datos)
    }

    /// El lugar en un punto del mapa (mantener pulsado): su dirección o, si no hay, las coordenadas.
    static func lugar(en coordenada: CLLocationCoordinate2D) async -> Lugar {
        var c = URLComponents(string: "https://photon.komoot.io/reverse")!
        c.queryItems = [URLQueryItem(name: "lat", value: String(coordenada.latitude)),
                        URLQueryItem(name: "lon", value: String(coordenada.longitude))]
        let encontrado = (try? await pedir(c.url!)).flatMap { lugares(de: $0).first }
        // El pin queda donde se pulsó, aunque la dirección más cercana esté un poco más allá.
        return Lugar(
            nombre: encontrado?.nombre ?? "Punto en el mapa",
            subtitulo: encontrado?.subtitulo ?? String(format: "%.5f, %.5f", coordenada.latitude, coordenada.longitude),
            coordenada: coordenada
        )
    }

    private static func lugares(de datos: Data) -> [Lugar] {
        guard let json = try? JSONSerialization.jsonObject(with: datos) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else { return [] }
        return features.compactMap { f in
            guard let geometria = f["geometry"] as? [String: Any],
                  let c = geometria["coordinates"] as? [Double], c.count == 2,
                  let p = f["properties"] as? [String: Any] else { return nil }
            let calle = [p["housenumber"] as? String, p["street"] as? String].compactMap { $0 }.joined(separator: " ")
            let nombre = (p["name"] as? String) ?? (calle.isEmpty ? nil : calle) ?? "Lugar"
            let ciudad = [p["city"] as? String ?? p["district"] as? String, p["postcode"] as? String]
                .compactMap { $0 }.joined(separator: " ")
            let subtitulo = [calle == nombre ? nil : (calle.isEmpty ? nil : calle), ciudad.isEmpty ? nil : ciudad]
                .compactMap { $0 }.joined(separator: " · ")
            return Lugar(nombre: nombre, subtitulo: subtitulo,
                         coordenada: CLLocationCoordinate2D(latitude: c[1], longitude: c[0]))
        }
    }

    // MARK: - Rutas (OSRM de FOSSGIS)

    private static func servidor(_ modo: ModoRuta) -> String {
        switch modo {
        case .coche: "https://routing.openstreetmap.de/routed-car/route/v1/driving/"
        case .pie: "https://routing.openstreetmap.de/routed-foot/route/v1/foot/"
        case .bici: "https://routing.openstreetmap.de/routed-bike/route/v1/bike/"
        }
    }

    private struct Respuesta: Decodable {
        struct R: Decodable {
            struct G: Decodable { let coordinates: [[Double]] }
            struct Tramo: Decodable {
                struct P: Decodable {
                    struct M: Decodable {
                        let type: String
                        let modifier: String?
                        let location: [Double]
                        let exit: Int?
                    }
                    struct I: Decodable {
                        struct L: Decodable {
                            let indications: [String]
                            let valid: Bool
                        }
                        let lanes: [L]?
                    }
                    let distance: Double
                    let duration: Double
                    let name: String?
                    let ref: String?
                    let exits: String?
                    let destinations: String?
                    let maneuver: M
                    let intersections: [I]?
                }
                let summary: String?
                let steps: [P]
            }
            let duration: Double
            let distance: Double
            let geometry: G
            let legs: [Tramo]
        }
        let code: String
        let routes: [R]?
    }

    /// Hasta 3 rutas (la mejor primero) con pasos y trazado completo.
    static func rutas(desde origen: CLLocationCoordinate2D, hasta destino: CLLocationCoordinate2D,
                      modo: ModoRuta) async throws -> [Ruta] {
        let puntos = "\(origen.longitude),\(origen.latitude);\(destino.longitude),\(destino.latitude)"
        var c = URLComponents(string: servidor(modo) + puntos)!
        c.queryItems = [
            URLQueryItem(name: "overview", value: "full"),
            URLQueryItem(name: "geometries", value: "geojson"),
            URLQueryItem(name: "steps", value: "true"),
            URLQueryItem(name: "alternatives", value: "3"),
        ]
        let datos = try await pedir(c.url!)
        let r: Respuesta
        do {
            r = try JSONDecoder().decode(Respuesta.self, from: datos)
        } catch {
            throw Fallo.servicio("respuesta inesperada")
        }
        guard r.code == "Ok", let rutas = r.routes, !rutas.isEmpty else { throw Fallo.sinRuta }

        return rutas.prefix(3).enumerated().map { i, ruta in
            var pasos: [Paso] = []
            for tramo in ruta.legs {
                for p in tramo.steps {
                    let calle = Texto.bonito([p.ref, p.name].compactMap { $0?.isEmpty == false ? $0 : nil }.first ?? "")
                    let destinos = p.destinations.map { Texto.bonito($0) }
                    let (texto, icono) = Maniobra.describir(tipo: p.maneuver.type, modificador: p.maneuver.modifier,
                                                            calle: calle, salida: p.maneuver.exit,
                                                            numeroSalida: p.exits, destinos: destinos)
                    // Carriles de la maniobra: los del primer cruce del paso (donde se hace el giro).
                    let carriles = (p.intersections?.first?.lanes ?? []).enumerated().map { i, l in
                        Carril(id: i, indicaciones: l.indications, valido: l.valid)
                    }
                    let lugar = p.maneuver.location.count == 2
                        ? CLLocationCoordinate2D(latitude: p.maneuver.location[1], longitude: p.maneuver.location[0])
                        : destino
                    pasos.append(Paso(id: pasos.count, instruccion: texto, calle: calle,
                                      distancia: p.distance, duracion: p.duration, icono: icono, ubicacion: lugar,
                                      carriles: carriles, salida: p.exits, destinos: destinos))
                }
            }
            let resumen = ruta.legs.compactMap(\.summary).filter { !$0.isEmpty }.joined(separator: ", ")
            return Ruta(
                id: i,
                duracion: ruta.duration,
                distancia: ruta.distance,
                coordenadas: ruta.geometry.coordinates.compactMap {
                    $0.count >= 2 ? CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) : nil
                },
                pasos: pasos,
                via: resumen.isEmpty ? "" : "por \(Texto.bonito(resumen))"
            )
        }
    }

    // MARK: - Red

    private static func pedir(_ url: URL) async throws -> Data {
        var peticion = URLRequest(url: url, timeoutInterval: 15)
        peticion.setValue(agente, forHTTPHeaderField: "User-Agent")
        peticion.setValue("es", forHTTPHeaderField: "Accept-Language")
        let (datos, respuesta) = try await URLSession.shared.data(for: peticion)
        if let http = respuesta as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // OSRM responde 400 con code «NoRoute» cuando no hay camino: se trata como «sin ruta».
            if http.statusCode == 400 { return datos }
            throw Fallo.servicio("HTTP \(http.statusCode)")
        }
        return datos
    }
}
