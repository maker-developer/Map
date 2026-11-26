import Foundation
import CoreLocation
import SQLite3

/// Busca en las bases independientes de OSM y Overture sin fundir sus licencias.
enum IndiceLugares {
    private static let cola = DispatchQueue(label: "map.indice.lugares", qos: .userInitiated)
    private static var osm: OpaquePointer?
    private static var overture: OpaquePointer?
    private static var intentoAbrir = false

    private struct Coincidencia {
        let fila: [String: Any?]
        let fuente: String
        let nombre: String
        let subtitulo: String
        let lon: Double
        let lat: Double
        let relevancia: Int
        let distancia2: Double
    }

    static func preparar() {
        cola.async { _ = abrirSiHaceFalta() }
    }

    static func buscar(_ texto: String, cerca: CLLocationCoordinate2D?, limite: Int = 12) -> [Lugar] {
        let consulta = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard consulta.count >= 2 else { return [] }
        return cola.sync { () -> [Lugar] in
            guard abrirSiHaceFalta() else { return [] }
            let match = expresionFTS(consulta)
            guard !match.isEmpty else { return [] }
            let lon = cerca?.longitude ?? -80.2
            let lat = cerca?.latitude ?? 25.78
            let candidatosOSM = osm.map {
                consultar($0, match: match, q: consulta, lon: lon, lat: lat,
                          fuente: "openstreetmap", limite: max(limite * 4, 48))
            } ?? []
            let candidatosOverture = overture.map {
                consultar($0, match: match, q: consulta, lon: lon, lat: lat,
                          fuente: "overture", limite: max(limite * 4, 48))
            } ?? []

            let porClave = Dictionary(grouping: candidatosOverture.compactMap { item -> (String, Coincidencia)? in
                guard let key = Self.texto(item.fila, "entity_key"), !key.isEmpty else { return nil }
                return (key, item)
            }, by: { $0.0 })
            var usadas = Set<String>()
            var resultados: [(lugar: Lugar, relevancia: Int, distancia2: Double, clave: String)] = []

            // OSM queda como fila principal. Solo se rellenan campos vacíos con Overture;
            // source/license/attribution y los JSON de procedencia no se combinan.
            for item in candidatosOSM {
                var fila = item.fila
                let key = Self.texto(fila, "entity_key")
                let complementaria = key.flatMap { porClave[$0]?.first?.1 }
                if let complementaria {
                    fila = completarVacios(de: fila, con: complementaria.fila)
                    usadas.insert(key ?? "")
                }
                let attribution = complementaria.flatMap { atribucion($0.fila) }
                if let lugar = crearLugar(fila: fila, atribucionComplementaria: attribution) {
                    let prioridad = min(item.relevancia, complementaria?.relevancia ?? item.relevancia)
                    let distancia = min(item.distancia2, complementaria?.distancia2 ?? item.distancia2)
                    resultados.append((lugar, prioridad, distancia, key ?? fallbackKey(item)))
                }
            }

            for item in candidatosOverture {
                let key = Self.texto(item.fila, "entity_key")
                if let key, usadas.contains(key) { continue }
                guard let lugar = crearLugar(fila: item.fila, atribucionComplementaria: nil) else { continue }
                resultados.append((lugar, item.relevancia, item.distancia2, key ?? fallbackKey(item)))
            }

            var clavesVistas = Set<String>()
            return resultados
                .sorted {
                    if $0.relevancia != $1.relevancia { return $0.relevancia < $1.relevancia }
                    return $0.distancia2 < $1.distancia2
                }
                .filter { item in
                    clavesVistas.insert(item.clave).inserted
                }
                .prefix(limite)
                .map { $0.lugar }
        }
    }

    private static func abrirSiHaceFalta() -> Bool {
        if intentoAbrir { return osm != nil || overture != nil }
        intentoAbrir = true
        osm = abrir(nombre: "openstreetmap.sqlite")
        overture = abrir(nombre: "overture.sqlite")
        return osm != nil || overture != nil
    }

    private static func abrir(nombre: String) -> OpaquePointer? {
        let base = nombre.replacingOccurrences(of: ".sqlite", with: "")
        let candidatos: [URL?] = [
            Bundle.main.url(forResource: base, withExtension: "sqlite", subdirectory: "data/places"),
            Bundle.main.url(forResource: base, withExtension: "sqlite", subdirectory: "places"),
            Bundle.main.url(forResource: base, withExtension: "sqlite"),
            Bundle.main.urls(forResourcesWithExtension: "sqlite", subdirectory: "data/places")?.first { $0.lastPathComponent == nombre },
            Bundle.main.urls(forResourcesWithExtension: "sqlite", subdirectory: "places")?.first { $0.lastPathComponent == nombre },
            Bundle.main.urls(forResourcesWithExtension: "sqlite", subdirectory: nil)?.first { $0.lastPathComponent == nombre },
        ]
        guard let url = candidatos.compactMap({ $0 }).first else {
            print("IndiceLugares: no está \(nombre) en el bundle")
            return nil
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            print("IndiceLugares: no abre \(nombre)")
            return nil
        }
        return db
    }

    private static func expresionFTS(_ texto: String) -> String {
        let tokens = texto
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return "" }
        return tokens.enumerated().map { i, token in
            let seguro = token.replacingOccurrences(of: "\"", with: "")
            return i == tokens.count - 1 ? "\"\(seguro)\"*" : "\"\(seguro)\""
        }.joined(separator: " ")
    }

    private static func consultar(_ db: OpaquePointer, match: String, q: String, lon: Double, lat: Double,
                                  fuente: String, limite: Int) -> [Coincidencia] {
        let sql = """
        SELECT l.*,
          CASE WHEN lower(l.name) = lower(?) THEN 0
               WHEN lower(coalesce(l.brand, '')) = lower(?) THEN 0
               WHEN lower(l.name) LIKE lower(?) THEN 1
               ELSE 2 END AS __relevance
        FROM lugares_fts
        JOIN lugares l ON l.id = lugares_fts.rowid
        WHERE lugares_fts MATCH ?
          AND l.lon IS NOT NULL AND l.lat IS NOT NULL
        ORDER BY __relevance,
          ((l.lon - ?) * (l.lon - ?) + (l.lat - ?) * (l.lat - ?)) ASC
        LIMIT ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        func bind(_ i: Int32, _ value: String) {
            _ = value.withCString { sqlite3_bind_text(stmt, i, $0, -1, transient) }
        }
        let prefix = "\(q)%"
        bind(1, q); bind(2, q); bind(3, prefix); bind(4, match)
        sqlite3_bind_double(stmt, 5, lon)
        sqlite3_bind_double(stmt, 6, lon)
        sqlite3_bind_double(stmt, 7, lat)
        sqlite3_bind_double(stmt, 8, lat)
        sqlite3_bind_int(stmt, 9, Int32(limite))

        var output: [Coincidencia] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let cantidad = Int(sqlite3_column_count(stmt))
            var fila: [String: Any?] = [:]
            for i in 0..<cantidad {
                guard let nombreC = sqlite3_column_name(stmt, Int32(i)) else { continue }
                let nombre = String(cString: nombreC)
                if nombre == "__relevance" { continue }
                switch sqlite3_column_type(stmt, Int32(i)) {
                case SQLITE_NULL:
                    fila.updateValue(nil, forKey: nombre)
                case SQLITE_INTEGER:
                    fila[nombre] = sqlite3_column_int64(stmt, Int32(i))
                case SQLITE_FLOAT:
                    fila[nombre] = sqlite3_column_double(stmt, Int32(i))
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(stmt, Int32(i)) {
                        // Incluye *_json literalmente, sin parsearlos ni volver a serializarlos.
                        fila[nombre] = String(cString: text)
                    } else {
                        fila.updateValue(nil, forKey: nombre)
                    }
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(stmt, Int32(i)))
                    if let bytes = sqlite3_column_blob(stmt, Int32(i)), count > 0 {
                        fila[nombre] = Data(bytes: bytes, count: count)
                    } else {
                        fila.updateValue(nil, forKey: nombre)
                    }
                default:
                    fila.updateValue(nil, forKey: nombre)
                }
            }
            guard let nombre = texto(fila, "name"),
                  let x = numero(fila, "lon"), let y = numero(fila, "lat") else { continue }
            let categoria = texto(fila, "category")?.replacingOccurrences(of: "_", with: " ")
            let direccion = texto(fila, "address")
            let localidad = texto(fila, "locality")
            let subtitulo = [categoria, direccion, localidad].compactMap { $0 }.filter { !$0.isEmpty }
                .joined(separator: " · ")
            let prioridad = Int(sqlite3_column_int(stmt, Int32(cantidad - 1)))
            let distancia = (x - lon) * (x - lon) + (y - lat) * (y - lat)
            output.append(Coincidencia(fila: fila, fuente: fuente, nombre: nombre,
                                       subtitulo: subtitulo, lon: x, lat: y,
                                       relevancia: prioridad, distancia2: distancia))
        }
        return output
    }

    private static func completarVacios(de principal: [String: Any?], con otra: [String: Any?]) -> [String: Any?] {
        var resultado = principal
        let protegidos: Set<String> = [
            "id", "source_id", "entity_key", "source", "license", "attribution",
            "source_url", "source_updated", "captured_at", "details_json",
        ]
        for (columna, valor) in otra where !protegidos.contains(columna) {
            guard vacio(resultado[columna] ?? nil), !vacio(valor ?? nil) else { continue }
            resultado.updateValue(valor ?? nil, forKey: columna)
        }
        return resultado
    }

    private static func crearLugar(fila: [String: Any?], atribucionComplementaria: String?) -> Lugar? {
        guard let nombre = texto(fila, "name"), let lon = numero(fila, "lon"), let lat = numero(fila, "lat") else {
            return nil
        }
        var ficha = FichaLugar(fila: fila)
        if let atribucionComplementaria, atribucionComplementaria != ficha.atribucion {
            ficha.atribucionesComplementarias = [atribucionComplementaria]
        }
        let categoria = texto(fila, "category")?.replacingOccurrences(of: "_", with: " ")
        let direccion = texto(fila, "address")
        let localidad = texto(fila, "locality")
        let subtitulo = [categoria, direccion, localidad].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: " · ")
        return Lugar(nombre: nombre, subtitulo: subtitulo,
                     coordenada: CLLocationCoordinate2D(latitude: lat, longitude: lon), ficha: ficha)
    }

    private static func atribucion(_ fila: [String: Any?]) -> String? {
        if texto(fila, "source") == "openstreetmap" {
            return "© OpenStreetMap contributors (ODbL)"
        }
        guard texto(fila, "source") == "overture" else { return nil }
        return "Overture Maps Foundation" + (texto(fila, "license").map { " · \($0)" } ?? "")
    }

    private static func fallbackKey(_ item: Coincidencia) -> String {
        "\(item.fuente)|\(item.nombre.lowercased())|\(item.lat)|\(item.lon)"
    }

    private static func texto(_ fila: [String: Any?], _ key: String) -> String? {
        guard let value = fila[key] ?? nil else { return nil }
        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text == "null" ? nil : text
    }

    private static func numero(_ fila: [String: Any?], _ key: String) -> Double? {
        guard let value = fila[key] ?? nil else { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        return Double(String(describing: value))
    }

    private static func vacio(_ value: Any?) -> Bool {
        guard let value else { return true }
        if let text = value as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return false
    }
}
