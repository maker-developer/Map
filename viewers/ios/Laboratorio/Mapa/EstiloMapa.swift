import Foundation

/// El estilo del mapa (MapLibre Style Spec) armado en código, igual que `viewers/web/src/map/style.js`
/// y con las paletas de `styles/base-light.js` y `styles/base-dark.js`.
///
/// Se escribe como JSON en Caches y MapLibre lo carga desde ahí. Los PMTiles y las letras
/// salen del propio app (o de la Mac, ver `OrigenDatos`).
struct EstiloMapa {
    enum Tema: String, CaseIterable, Identifiable {
        case claro, oscuro
        var id: String { rawValue }
    }

    var tema: Tema = .claro
    /// Los edificios se dibujan encima de calles, nombres, rutas y paradas que quedan detrás
    /// (así no parece que una parada está en el techo). Apagado = como el visor web de hoy.
    var edificiosTapan = true
    var edificios3D = true
    var transporte = false
    var origen: OrigenDatos = .app

    // MARK: - Paletas (styles/base-light.js · styles/base-dark.js)

    struct Paleta {
        let background, land, park, parkOutline, water, waterOutline, boundary: String
        let street, mainStreet, mainStreetCasing, streetLabel, cityLabel, halo: String
        let building, buildingOutline, buildingLow, buildingMid, buildingHigh: String
    }

    static let claro = Paleta(
        background: "#d9e4df", land: "#f0eee4", park: "#cdddc5", parkOutline: "#b8cdb3",
        water: "#a5cfd5", waterOutline: "#9ec7cb", boundary: "#798f87",
        street: "#fdfbf4", mainStreet: "#fffaf0", mainStreetCasing: "#c0bbaa",
        streetLabel: "#606760", cityLabel: "#243d36", halo: "#fbf8ef",
        building: "#d6c8b7", buildingOutline: "#adab9e",
        buildingLow: "#e2d1b8", buildingMid: "#adbbb1", buildingHigh: "#698f8b"
    )

    static let oscuro = Paleta(
        background: "#161b1a", land: "#202625", park: "#26372f", parkOutline: "#364a40",
        water: "#203a40", waterOutline: "#31535a", boundary: "#657d75",
        street: "#343b38", mainStreet: "#454b46", mainStreetCasing: "#101514",
        streetLabel: "#c4ccc6", cityLabel: "#e2e6dc", halo: "#202625",
        building: "#646c65", buildingOutline: "#414943",
        buildingLow: "#77776d", buildingMid: "#697b73", buildingHigh: "#4c706c"
    )

    var paleta: Paleta { tema == .claro ? Self.claro : Self.oscuro }

    // MARK: - JSON

    /// Escribe el estilo en Caches y devuelve su URL para `MLNMapView.styleURL`.
    func escribir() throws -> URL {
        let datos = try JSONSerialization.data(withJSONObject: estilo(), options: [.sortedKeys])
        let carpeta = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        // Un nombre por combinación: MapLibre recarga al cambiar la URL.
        let nombre = "estilo-\(tema.rawValue)-\(edificiosTapan ? "tapan" : "debajo")-\(origen.clave).json"
        let url = carpeta.appendingPathComponent(nombre)
        try datos.write(to: url, options: .atomic)
        return url
    }

    func estilo() -> [String: Any] {
        [
            "version": 8,
            "name": "Map · \(tema.rawValue)",
            "glyphs": origen.urlGlifos,
            "light": ["anchor": "map", "intensity": 0.45, "color": "#fff5e5", "position": [1.15, 210, 35]],
            "sources": [
                "base": ["type": "vector", "url": origen.urlPMTiles(.base)],
                "buildings": ["type": "vector", "url": origen.urlPMTiles(.edificios)],
                "transit": ["type": "vector", "url": origen.urlPMTiles(.transporte)],
                "towns": ["type": "geojson", "data": Self.pueblos],
            ],
            "layers": capas(),
        ]
    }

    // MARK: - Capas

    private func capas() -> [[String: Any]] {
        let p = paleta
        let suelo = capasSuelo(p)
        let nombresCalles = capaNombresCalles(p)
        let rutas = capasTransporte()
        let edificios = capasEdificios(p)
        let pueblos = capaPueblos(p)
        // Con «edificios tapan», todo lo que va pegado al suelo (nombres de calles, rutas, paradas)
        // se dibuja antes que los edificios, y estos lo tapan cuando queda detrás.
        // Sin él, como en el visor web: los edificios primero y lo demás flotando encima.
        if edificiosTapan {
            return suelo + [nombresCalles] + rutas + edificios + [pueblos]
        } else {
            return suelo + edificios + [nombresCalles] + rutas + [pueblos]
        }
    }

    private static let principales: [Any] = ["in", ["get", "kind"], ["literal", ["0", "1", "2", "3"]]]
    private static let lineas: [String: Any] = ["line-cap": "round", "line-join": "round"]

    private func capasSuelo(_ p: Paleta) -> [[String: Any]] {
        [
            ["id": "background", "type": "background", "paint": ["background-color": p.background]],
            ["id": "land", "type": "fill", "source": "base", "source-layer": "condado",
             "paint": ["fill-color": p.land]],
            ["id": "parks", "type": "fill", "source": "base", "source-layer": "parques",
             "paint": ["fill-color": p.park, "fill-outline-color": p.parkOutline]],
            ["id": "water", "type": "fill", "source": "base", "source-layer": "agua",
             "paint": ["fill-color": p.water, "fill-outline-color": p.waterOutline]],
            ["id": "county-line", "type": "line", "source": "base", "source-layer": "condado", "maxzoom": 12,
             "paint": ["line-color": p.boundary, "line-width": 1.1, "line-dasharray": [3, 2]]],
            ["id": "streets", "type": "line", "source": "base", "source-layer": "calles", "minzoom": 11,
             "layout": Self.lineas,
             "paint": ["line-color": p.street,
                       "line-width": ["interpolate", ["linear"], ["zoom"], 11, 0.35, 14, 1.6, 17, 5.5, 19, 10]]],
            ["id": "main-streets-casing", "type": "line", "source": "base", "source-layer": "calles", "minzoom": 8,
             "filter": Self.principales, "layout": Self.lineas,
             "paint": ["line-color": p.mainStreetCasing, "line-opacity": 0.8,
                       "line-width": ["interpolate", ["linear"], ["zoom"], 9, 1.6, 13, 2.7, 16, 5.9, 19, 15.9]]],
            ["id": "main-streets", "type": "line", "source": "base", "source-layer": "calles", "minzoom": 8,
             "filter": Self.principales, "layout": Self.lineas,
             "paint": ["line-color": p.mainStreet,
                       "line-width": ["interpolate", ["linear"], ["zoom"], 9, 0.7, 13, 1.8, 16, 5, 19, 15]]],
        ]
    }

    private func capaNombresCalles(_ p: Paleta) -> [String: Any] {
        ["id": "street-names", "type": "symbol", "source": "base", "source-layer": "calles", "minzoom": 14.4,
         "filter": ["!=", ["get", "name"], ""],
         "layout": ["symbol-placement": "line", "symbol-spacing": 185, "text-field": ["get", "name"],
                    "text-font": ["DMSans-Regular"], "text-max-angle": 38,
                    "text-size": ["interpolate", ["linear"], ["zoom"], 14.4, 10, 18, 13]],
         "paint": ["text-color": p.streetLabel, "text-halo-color": p.halo, "text-halo-width": 1.3]]
    }

    private func capaPueblos(_ p: Paleta) -> [String: Any] {
        ["id": "towns", "type": "symbol", "source": "towns", "minzoom": 8, "maxzoom": 14,
         "layout": ["text-field": ["get", "name"], "text-font": ["DMSans-SemiBold"], "text-size": 14],
         "paint": ["text-color": p.cityLabel, "text-halo-color": p.halo, "text-halo-width": 1.8]]
    }

    private func capasEdificios(_ p: Paleta) -> [[String: Any]] {
        let color: [Any] = ["interpolate", ["linear"], ["coalesce", ["get", "height"], 0],
                            0, p.buildingLow, 15, p.buildingLow, 46, p.buildingMid, 120, p.buildingHigh, 200, p.buildingHigh]
        return [
            ["id": "buildings-footprints", "type": "fill", "source": "buildings", "source-layer": "edificios", "minzoom": 13,
             "layout": ["visibility": edificios3D ? "none" : "visible"],
             "paint": ["fill-color": p.building, "fill-outline-color": p.buildingOutline]],
            ["id": "buildings-volume", "type": "fill-extrusion", "source": "buildings", "source-layer": "edificios", "minzoom": 13,
             "filter": ["!=", ["get", "height"], NSNull()],
             "layout": ["visibility": edificios3D ? "visible" : "none"],
             "paint": ["fill-extrusion-height": ["get", "height"], "fill-extrusion-base": 0,
                       "fill-extrusion-color": color, "fill-extrusion-vertical-gradient": true]],
        ]
    }

    private func capasTransporte() -> [[String: Any]] {
        let visible = transporte ? "visible" : "none"
        return [
            ["id": "transit-routes", "type": "line", "source": "transit", "source-layer": "rutas", "minzoom": 10,
             "layout": Self.lineas.merging(["visibility": visible]) { $1 },
             "paint": ["line-opacity": 0.68,
                       "line-color": ["case", ["get", "rail"], "#194d49", ["get", "color"]],
                       "line-width": ["interpolate", ["linear"], ["zoom"], 10, 0.8, 15, 2.3, 19, 4.8]]],
            ["id": "transit-stops", "type": "circle", "source": "transit", "source-layer": "paradas", "minzoom": 13.1,
             "layout": ["visibility": visible],
             "paint": ["circle-color": ["case", ["get", "rail"], "#06634e", "#087c96"],
                       "circle-stroke-color": "#fffbef", "circle-stroke-width": 1.4,
                       "circle-radius": ["interpolate", ["linear"], ["zoom"], 13.1, 1.65, 17, 5.3]]],
        ]
    }

    /// Nombres de los municipios (los mismos que el visor web).
    static let pueblos: [String: Any] = [
        "type": "FeatureCollection",
        "features": [
            ("Miami", -80.207, 25.778), ("Miami Beach", -80.132, 25.823), ("Miami Lakes", -80.324, 25.912),
            ("Hialeah", -80.291, 25.848), ("Doral", -80.356, 25.814), ("Coral Gables", -80.264, 25.749),
            ("Kendall", -80.340, 25.671), ("Homestead", -80.477, 25.469), ("Key Biscayne", -80.163, 25.693),
            ("Aventura", -80.140, 25.958), ("Everglades", -80.784, 25.545),
        ].map { nombre, lon, lat in
            ["type": "Feature", "properties": ["name": nombre],
             "geometry": ["type": "Point", "coordinates": [lon, lat]]] as [String: Any]
        },
    ]
}

/// Los tres archivos de teselas del mapa.
enum ArchivoMapa {
    case base, edificios, transporte

    /// Nombre en `public/data/` (dentro del app y en la Mac).
    var nombreLocal: String {
        switch self {
        case .base: "base.pmtiles"
        case .edificios: "edificios.pmtiles"
        case .transporte: "transit.pmtiles"
        }
    }

    /// Nombre en el bucket de la nube (Cloudflare R2, carpeta v1/).
    var nombreNube: String {
        switch self {
        case .base: "base.pmtiles"
        case .edificios: "buildings.pmtiles"
        case .transporte: "transit.pmtiles"
        }
    }
}

/// De dónde salen los PMTiles. Las letras siempre salen del app.
enum OrigenDatos: Equatable {
    /// Dentro del app (carpeta `data/` del bundle). Funciona sin internet.
    case app
    /// En la nube: bucket público de Cloudflare R2 con rangos HTTP (cada zona baja solo su parte).
    /// La URL base sale de Info.plist › MapNubeURL.
    case nube(URL)
    /// Servidos por la Mac en la misma Wi-Fi con `npm run dev` (p. ej. http://192.168.1.20:4180).
    /// Sirve para probar teselas nuevas sin volver a compilar el app.
    case mac(URL)

    /// Carpeta de la nube (Info.plist › MapNubeURL), p. ej. https://….r2.dev/v1
    static var urlNube: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "MapNubeURL") as? String)
            .flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }

    var clave: String {
        switch self {
        case .app: "app"
        case .nube(let url): "nube-\(abs(url.absoluteString.hashValue))"
        case .mac(let url): "mac-\(abs(url.absoluteString.hashValue))"
        }
    }

    var nombre: String {
        switch self {
        case .app: "Dentro del app"
        case .nube: "En la nube"
        case .mac: "Desde la Mac"
        }
    }

    func urlPMTiles(_ archivo: ArchivoMapa) -> String {
        switch self {
        case .app:
            let url = Bundle.main.resourceURL!.appendingPathComponent("data").appendingPathComponent(archivo.nombreLocal)
            return "pmtiles://" + url.absoluteString
        case .nube(let carpeta):
            return "pmtiles://" + carpeta.appendingPathComponent(archivo.nombreNube).absoluteString
        case .mac(let base):
            return "pmtiles://" + base.appendingPathComponent("data").appendingPathComponent(archivo.nombreLocal).absoluteString
        }
    }

    /// Las letras siempre del app (la Mac no las sirve en `npm run dev`).
    var urlGlifos: String {
        let carpeta = Bundle.main.resourceURL!.appendingPathComponent("glifos").absoluteString
        // MapLibre sustituye {fontstack} y {range}; las llaves no deben ir escapadas.
        return carpeta + (carpeta.hasSuffix("/") ? "" : "/") + "{fontstack}/{range}.pbf"
    }
}
