import Foundation

/// Todo lo que se sabe de un negocio o lugar, leído de una fila de la tabla `lugares`
/// (catálogos de Codex: `places/v1/overture.sqlite` y `places/v1/openstreetmap.sqlite`).
///
/// Cada campo es opcional: Overture suele traer teléfono, web, correo y redes, pero no horario ni
/// fotos; OpenStreetMap a veces trae horario, pagos, servicios, descripción y fotos con licencia.
/// La ficha enseña solo lo que hay.
struct FichaLugar: Equatable {
    struct Foto: Equatable {
        let url: URL
        let pagina: URL?
        let autor: String?
        let licencia: String?
    }

    struct Red: Equatable, Identifiable {
        let nombre: String
        let url: URL
        var id: String { url.absoluteString }
    }

    var nombre: String
    var marca: String?
    /// En español: «Restaurante», «Farmacia»… (o la del dato, legible).
    var categoria: String?
    var subcategoria: String?
    var descripcion: String?
    var direccion: String?
    var telefonos: [String] = []
    var correo: String?
    var webs: [URL] = []
    var redes: [Red] = []
    var horario: Horario?
    /// Formas de pago y servicios ya traducidos («Tarjetas», «Para llevar», «Accesible»…).
    var pagos: [String] = []
    var servicios: [String] = []
    /// El sitio cerró (según la fuente).
    var cerrado = false
    var fotos: [Foto] = []
    /// «© OpenStreetMap contributors (ODbL)» u «Overture Maps · Meta, Microsoft…».
    var atribucion: String?

    var tieneContacto: Bool { !telefonos.isEmpty || correo != nil || !webs.isEmpty || !redes.isEmpty }

    // MARK: - Desde una fila de SQLite

    /// Una fila de `lugares` como diccionario columna → valor (String, Double, Int o nil).
    init(fila f: [String: Any?]) {
        func texto(_ c: String) -> String? {
            guard let v = f[c] ?? nil else { return nil }
            let t = "\(v)".trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty || t == "null" ? nil : t
        }
        func json(_ c: String) -> Any? {
            texto(c).flatMap { $0.data(using: .utf8) }.flatMap { try? JSONSerialization.jsonObject(with: $0) }
        }

        nombre = texto("name") ?? "Lugar"
        marca = texto("brand").flatMap { $0 == nombre ? nil : $0 }
        categoria = texto("category").map(Traducciones.categoria)
        subcategoria = texto("subcategory").map(Traducciones.legible).flatMap { $0 == categoria ? nil : $0 }
        descripcion = texto("description")

        let calle = texto("address")
        let ciudad = [texto("locality"), [texto("region"), texto("postal_code")].compactMap { $0 }.joined(separator: " ")]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        direccion = [calle, ciudad.isEmpty ? nil : ciudad].compactMap { $0 }.joined(separator: "\n").nilSiVacio

        // Teléfonos: el principal y los demás sin repetir.
        var tels = [texto("phone")].compactMap { $0 }
        tels += (json("phones_json") as? [Any])?.compactMap { $0 as? String } ?? []
        telefonos = tels.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }

        correo = texto("email")

        var urls = [texto("website")].compactMap { $0 }
        urls += (json("websites_json") as? [Any])?.compactMap { $0 as? String } ?? []
        webs = urls.compactMap(Self.url).reduce(into: [URL]()) { if !$0.contains($1) { $0.append($1) } }

        // Redes: Overture trae una lista de URLs; OpenStreetMap, etiquetas (facebook=…, contact:instagram=…).
        var listaRedes: [Red] = []
        if let lista = json("socials_json") as? [Any] {
            listaRedes = lista.compactMap { ($0 as? String).flatMap(Self.url) }.map { Red(nombre: Self.nombreRed($0), url: $0) }
        } else if let mapa = json("socials_json") as? [String: Any] {
            for (clave, valor) in mapa {
                guard let v = valor as? String else { continue }
                let red = clave.replacingOccurrences(of: "contact:", with: "")
                if let u = Self.url(v) ?? Self.urlRed(red, usuario: v) {
                    listaRedes.append(Red(nombre: red.capitalized, url: u))
                }
            }
        }
        redes = listaRedes.sorted { $0.nombre < $1.nombre }

        horario = texto("opening_hours").map(Horario.init)

        pagos = (json("payment_json") as? [String: Any]).map(Traducciones.pagos) ?? []
        servicios = (json("services_json") as? [String: Any]).map(Traducciones.servicios) ?? []

        let estado = texto("operating_status")?.lowercased() ?? ""
        cerrado = estado.contains("closed") || estado == "yes" // OSM: disused/abandoned = yes

        fotos = (json("photos_json") as? [[String: Any]])?.compactMap { d in
            guard let u = (d["url"] as? String).flatMap(URL.init(string:)) else { return nil }
            return Foto(url: u, pagina: (d["page_url"] as? String).flatMap(URL.init(string:)),
                        autor: (d["author"] as? String)?.nilSiVacio, licencia: (d["license"] as? String)?.nilSiVacio)
        } ?? []

        atribucion = Self.atribucion(fuente: texto("source"), texto: texto("attribution"), licencia: texto("license"))
    }

    private static func url(_ texto: String) -> URL? {
        let t = texto.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let conEsquema = t.lowercased().hasPrefix("http") ? t : "https://\(t)"
        guard let u = URL(string: conEsquema), u.host() != nil else { return nil }
        return u
    }

    private static func urlRed(_ red: String, usuario: String) -> URL? {
        let u = usuario.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
        switch red.lowercased() {
        case "instagram": return URL(string: "https://instagram.com/\(u)")
        case "facebook": return URL(string: "https://facebook.com/\(u)")
        case "twitter", "x": return URL(string: "https://x.com/\(u)")
        case "tiktok": return URL(string: "https://tiktok.com/@\(u)")
        case "youtube": return URL(string: "https://youtube.com/@\(u)")
        default: return nil
        }
    }

    private static func nombreRed(_ u: URL) -> String {
        let host = (u.host() ?? "").replacingOccurrences(of: "www.", with: "")
        if host.contains("instagram") { return "Instagram" }
        if host.contains("facebook") { return "Facebook" }
        if host.contains("twitter") || host == "x.com" { return "X" }
        if host.contains("tiktok") { return "TikTok" }
        if host.contains("youtube") { return "YouTube" }
        if host.contains("linkedin") { return "LinkedIn" }
        if host.contains("yelp") { return "Yelp" }
        return host
    }

    private static func atribucion(fuente: String?, texto: String?, licencia: String?) -> String? {
        switch fuente {
        case "openstreetmap": return "© OpenStreetMap contributors (ODbL)"
        case "overture": return "Overture Maps Foundation" + (licencia.map { " · \($0)" } ?? "")
        default: return texto ?? fuente
        }
    }
}

// MARK: - Horario (formato opening_hours de OpenStreetMap)

/// Horario leído del formato de OpenStreetMap: «Mo-Fr 09:00-17:00; Sa 10:00-14:00; Su off», «24/7»…
/// Si no se entiende, se enseña el texto tal cual.
struct Horario: Equatable {
    /// Por día (0 = lunes … 6 = domingo): tramos en minutos desde medianoche.
    private(set) var dias: [[ClosedRange<Int>]] = Array(repeating: [], count: 7)
    let original: String
    private(set) var entendido = false

    private static let nombres = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    static let nombresES = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]

    init(_ texto: String) {
        original = texto
        let t = texto.trimmingCharacters(in: .whitespaces)
        if t == "24/7" {
            dias = Array(repeating: [0...1439], count: 7)
            entendido = true
            return
        }
        var algo = false
        for regla in t.split(separator: ";") {
            let r = regla.trimmingCharacters(in: .whitespaces)
            guard !r.isEmpty else { continue }
            // «Mo-Fr 09:00-17:00» · «Sa,Su off» · «09:00-17:00» (todos los días)
            let partes = r.split(separator: " ", maxSplits: 1).map(String.init)
            let (diasTexto, horasTexto): (String, String) = partes.count == 2 && Self.esDias(partes[0])
                ? (partes[0], partes[1]) : ("Mo-Su", r)
            guard let indices = Self.dias(diasTexto) else { continue }
            if horasTexto.lowercased() == "off" || horasTexto.lowercased() == "closed" {
                for i in indices { dias[i] = [] }
                algo = true
                continue
            }
            let tramos = horasTexto.split(separator: ",").compactMap { Self.tramo(String($0)) }
            guard !tramos.isEmpty else { continue }
            for i in indices { dias[i] = tramos }
            algo = true
        }
        entendido = algo
    }

    private static func esDias(_ t: String) -> Bool {
        t.split(whereSeparator: { $0 == "," || $0 == "-" }).allSatisfy { nombres.contains(String($0)) || $0 == "PH" }
    }

    private static func dias(_ t: String) -> [Int]? {
        var res: [Int] = []
        for parte in t.split(separator: ",") {
            let lim = parte.split(separator: "-").map(String.init)
            if lim.count == 2, let a = nombres.firstIndex(of: lim[0]), let b = nombres.firstIndex(of: lim[1]) {
                var i = a
                while true { res.append(i); if i == b { break }; i = (i + 1) % 7 }
            } else if let a = nombres.firstIndex(of: String(parte)) {
                res.append(a)
            } else if parte == "PH" {
                continue
            } else {
                return nil
            }
        }
        return res.isEmpty ? nil : res
    }

    private static func tramo(_ t: String) -> ClosedRange<Int>? {
        let lim = t.trimmingCharacters(in: .whitespaces).split(separator: "-").map(String.init)
        guard lim.count == 2, let a = minutos(lim[0]), var b = minutos(lim[1]) else { return nil }
        if b <= a { b = 1439 } // cruza la medianoche: se corta a las 23:59
        return a...b
    }

    private static func minutos(_ t: String) -> Int? {
        let hm = t.split(separator: ":").compactMap { Int($0) }
        guard hm.count == 2, (0...24).contains(hm[0]), (0...59).contains(hm[1]) else { return nil }
        return min(hm[0] * 60 + hm[1], 1439)
    }

    /// Día de hoy en el horario (0 = lunes).
    static func hoy(_ fecha: Date = .now) -> Int {
        (Calendar(identifier: .gregorian).component(.weekday, from: fecha) + 5) % 7
    }

    /// «Abierto · cierra a las 9:00 p. m.» o «Cerrado · abre a las 9:00 a. m.» (nil si no se entiende).
    func estado(_ fecha: Date = .now) -> (abierto: Bool, texto: String)? {
        guard entendido else { return nil }
        let cal = Calendar.current
        let ahora = cal.component(.hour, from: fecha) * 60 + cal.component(.minute, from: fecha)
        let d = Self.hoy(fecha)
        if let tramo = dias[d].first(where: { $0.contains(ahora) }) {
            if tramo == 0...1439 { return (true, "Abierto las 24 horas") }
            return (true, "Abierto · cierra a las \(Self.hora(tramo.upperBound))")
        }
        if let siguiente = dias[d].first(where: { $0.lowerBound > ahora }) {
            return (false, "Cerrado · abre a las \(Self.hora(siguiente.lowerBound))")
        }
        for i in 1...7 {
            let otro = (d + i) % 7
            if let primero = dias[otro].first {
                let cuando = i == 1 ? "mañana" : Self.nombresES[otro].lowercased()
                return (false, "Cerrado · abre \(cuando) a las \(Self.hora(primero.lowerBound))")
            }
        }
        return (false, "Cerrado")
    }

    /// Las horas de un día para la lista («9:00 a. m. – 5:00 p. m.», «Cerrado»).
    func texto(dia: Int) -> String {
        let tramos = dias[dia]
        if tramos.isEmpty { return "Cerrado" }
        if tramos == [0...1439] { return "24 horas" }
        return tramos.map { "\(Self.hora($0.lowerBound)) – \(Self.hora($0.upperBound))" }.joined(separator: ", ")
    }

    private static func hora(_ minutos: Int) -> String {
        let fecha = Calendar.current.date(bySettingHour: minutos / 60, minute: minutos % 60, second: 0, of: .now) ?? .now
        return fecha.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Traducciones de categorías, pagos y servicios

enum Traducciones {
    private static let categorias: [String: String] = [
        "restaurant": "Restaurante", "fast_food": "Comida rápida", "cafe": "Cafetería", "coffee_shop": "Cafetería",
        "bar": "Bar", "pub": "Bar", "bakery": "Panadería", "ice_cream": "Heladería", "pharmacy": "Farmacia",
        "supermarket": "Supermercado", "grocery_store": "Tienda de comestibles", "convenience": "Tienda de conveniencia",
        "convenience_store": "Tienda de conveniencia", "fuel": "Gasolinera", "gas_station": "Gasolinera",
        "bank": "Banco", "atm": "Cajero automático", "hospital": "Hospital", "clinic": "Clínica", "doctors": "Médico",
        "dentist": "Dentista", "school": "Escuela", "university": "Universidad", "college": "Universidad",
        "library": "Biblioteca", "post_office": "Oficina de correos", "police": "Policía", "fire_station": "Bomberos",
        "hotel": "Hotel", "motel": "Motel", "parking": "Estacionamiento", "place_of_worship": "Iglesia o templo",
        "hairdresser": "Peluquería", "beauty": "Salón de belleza", "beauty_salon": "Salón de belleza",
        "clothes": "Ropa", "clothing_store": "Tienda de ropa", "shoes": "Zapatería", "electronics": "Electrónica",
        "electronics_store": "Tienda de electrónica", "mobile_phone": "Telefonía móvil", "hardware": "Ferretería",
        "furniture": "Muebles", "car_repair": "Taller mecánico", "car": "Concesionario", "car_wash": "Lavado de autos",
        "gym": "Gimnasio", "fitness_centre": "Gimnasio", "veterinary": "Veterinario", "pet": "Tienda de mascotas",
        "florist": "Floristería", "jewelry": "Joyería", "department_store": "Grandes almacenes", "mall": "Centro comercial",
        "shopping_center": "Centro comercial", "laundry": "Lavandería", "dry_cleaning": "Tintorería",
        "cinema": "Cine", "theatre": "Teatro", "museum": "Museo", "park": "Parque", "attraction": "Atracción",
        "pizza_restaurant": "Pizzería", "mexican_restaurant": "Restaurante mexicano", "cuban_restaurant": "Restaurante cubano",
        "chinese_restaurant": "Restaurante chino", "italian_restaurant": "Restaurante italiano",
        "seafood_restaurant": "Marisquería", "insurance_agency": "Aseguradora", "real_estate": "Inmobiliaria",
        "real_estate_agent": "Inmobiliaria", "lawyer": "Abogado", "accountant": "Contador",
    ]

    /// «electronics_store» → «Tienda de electrónica» (o «Electronics store» si no está en la lista).
    static func categoria(_ c: String) -> String {
        categorias[c.lowercased()] ?? legible(c)
    }

    static func legible(_ c: String) -> String {
        let t = c.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ";", with: ", ")
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    /// payment:cards=yes, payment:cash=yes, payment:apple_pay=yes… → «Tarjetas», «Efectivo», «Apple Pay».
    static func pagos(_ d: [String: Any]) -> [String] {
        let nombres = ["cash": "Efectivo", "cards": "Tarjetas", "credit_cards": "Tarjeta de crédito",
                       "debit_cards": "Tarjeta de débito", "contactless": "Sin contacto", "apple_pay": "Apple Pay",
                       "google_pay": "Google Pay", "visa": "Visa", "mastercard": "Mastercard",
                       "american_express": "American Express", "discover_card": "Discover", "ebt": "EBT", "cheque": "Cheque"]
        return d.compactMap { k, v in
            guard "\(v)".lowercased() == "yes" else { return nil }
            let clave = k.replacingOccurrences(of: "payment:", with: "")
            return nombres[clave] ?? legible(clave)
        }.sorted()
    }

    /// takeaway, delivery, wheelchair, outdoor_seating, internet_access, diet:vegan… → textos en español.
    static func servicios(_ d: [String: Any]) -> [String] {
        let si: [String: String] = [
            "takeaway": "Para llevar", "delivery": "Entrega a domicilio", "dine_in": "Comer en el local",
            "drive_through": "Autoservicio en el auto", "reservation": "Reservas", "outdoor_seating": "Terraza",
            "wheelchair": "Accesible en silla de ruedas", "diet:vegan": "Opciones veganas",
            "diet:vegetarian": "Opciones vegetarianas", "diet:gluten_free": "Sin gluten", "diet:halal": "Halal",
            "diet:kosher": "Kosher",
        ]
        var res: [String] = []
        for (k, v) in d {
            let valor = "\(v)".lowercased()
            if k == "internet_access" {
                if ["wlan", "yes", "wifi"].contains(valor) { res.append("Wi-Fi") }
            } else if k == "wheelchair" {
                if valor == "yes" { res.append("Accesible en silla de ruedas") }
                else if valor == "limited" { res.append("Accesibilidad limitada") }
            } else if k == "reservation" {
                if ["yes", "recommended", "required"].contains(valor) { res.append("Reservas") }
            } else if valor == "yes" || valor == "only", let texto = si[k] {
                res.append(texto)
            }
        }
        return Array(Set(res)).sorted()
    }
}

private extension String {
    var nilSiVacio: String? { isEmpty ? nil : self }
}
