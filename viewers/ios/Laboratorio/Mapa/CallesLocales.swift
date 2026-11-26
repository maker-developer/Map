import Foundation
import CoreLocation

/// Lee las calles del condado directamente de `base.pmtiles` del app (capa `calles`, zoom 16,
/// a todo detalle), sin depender de lo que esté dibujado en pantalla. Sirve para pegar la ruta a
/// nuestras calles en cuanto llega (ver `PegarRuta.swift`).
///
/// PMTiles v3: cabecera de 127 bytes, directorios comprimidos con gzip e IDs de tesela en curva
/// de Hilbert. Las teselas son Mapbox Vector Tiles (protobuf) comprimidas con gzip.
final class CallesLocales: @unchecked Sendable {
    static let compartidas = CallesLocales()

    private let cola = DispatchQueue(label: "map.calles.locales")
    private var datos: Data?
    private var intentado = false
    private var cabecera = Cabecera()
    private var directorios: [UInt64: [Entrada]] = [:]
    private var teselas: [UInt64: [[CLLocationCoordinate2D]]] = [:]

    private struct Cabecera {
        var raiz: (offset: UInt64, largo: UInt64) = (0, 0)
        var hojas: UInt64 = 0
        var teselas: UInt64 = 0
        var compresionInterna: UInt8 = 2
        var compresionTeselas: UInt8 = 2
        var zoomMaximo: Int = 16
    }

    private struct Entrada {
        var id: UInt64
        var offset: UInt64
        var largo: UInt64
        var repeticiones: UInt64
    }

    /// Líneas de calles (en grados) en las teselas que tocan estos puntos, con un margen de ~40 m.
    func lineas(cerca puntos: [CLLocationCoordinate2D]) -> [[CLLocationCoordinate2D]] {
        cola.sync {
            guard abrir() else { return [] }
            let z = min(16, cabecera.zoomMaximo)
            var claves = Set<SIMD2<Int>>()
            let m = 0.0004
            // Puntos cada ~100 m (los tramos largos rectos pueden cruzar teselas sin vértices).
            var muestras: [CLLocationCoordinate2D] = []
            for (k, p) in puntos.enumerated() {
                muestras.append(p)
                guard k + 1 < puntos.count else { break }
                let q = puntos[k + 1]
                let n = min(500, Int(max(abs(q.latitude - p.latitude), abs(q.longitude - p.longitude)) / 0.001))
                if n > 1 {
                    for j in 1..<n {
                        let t = Double(j) / Double(n)
                        muestras.append(CLLocationCoordinate2D(latitude: p.latitude + (q.latitude - p.latitude) * t,
                                                               longitude: p.longitude + (q.longitude - p.longitude) * t))
                    }
                }
            }
            for p in muestras {
                for dy in [-m, 0, m] {
                    for dx in [-m, 0, m] {
                        claves.insert(Self.tesela(lat: p.latitude + dy, lon: p.longitude + dx, z: z))
                    }
                }
            }
            var res: [[CLLocationCoordinate2D]] = []
            for c in claves { res += lineas(z: z, x: c.x, y: c.y) }
            return res
        }
    }

    // MARK: Archivo

    private func abrir() -> Bool {
        if intentado { return datos != nil }
        intentado = true
        let candidatos = [
            Bundle.main.url(forResource: "base", withExtension: "pmtiles", subdirectory: "data"),
            Bundle.main.url(forResource: "base", withExtension: "pmtiles"),
        ]
        guard let url = candidatos.compactMap({ $0 }).first,
              let d = try? Data(contentsOf: url, options: .alwaysMapped), d.count >= 127,
              d.prefix(7) == Data("PMTiles".utf8), d[7] == 3 else {
            print("CallesLocales: no está base.pmtiles v3 en el app")
            return false
        }
        datos = d
        cabecera.raiz = (Self.u64(d, 8), Self.u64(d, 16))
        cabecera.hojas = Self.u64(d, 40)
        cabecera.teselas = Self.u64(d, 56)
        cabecera.compresionInterna = d[97]
        cabecera.compresionTeselas = d[98]
        cabecera.zoomMaximo = Int(d[101])
        return true
    }

    private static func u64(_ d: Data, _ i: Int) -> UInt64 {
        var v: UInt64 = 0
        for k in 0..<8 { v |= UInt64(d[d.startIndex + i + k]) << (8 * UInt64(k)) }
        return v
    }

    private func trozo(_ offset: UInt64, _ largo: UInt64) -> Data? {
        guard let d = datos, offset + largo <= UInt64(d.count) else { return nil }
        let a = d.startIndex + Int(offset)
        return d.subdata(in: a..<(a + Int(largo)))
    }

    private func directorio(_ offset: UInt64, _ largo: UInt64) -> [Entrada] {
        if let hecho = directorios[offset] { return hecho }
        guard let crudo = trozo(offset, largo) else { return [] }
        let bytes = cabecera.compresionInterna == 2 ? (Self.gunzip(crudo) ?? Data()) : crudo
        var lector = Lector(bytes)
        let n = Int(lector.varint())
        guard n > 0, n < 10_000_000 else { return [] }
        var e = [Entrada](repeating: Entrada(id: 0, offset: 0, largo: 0, repeticiones: 0), count: n)
        var ultimo: UInt64 = 0
        for i in 0..<n { ultimo += lector.varint(); e[i].id = ultimo }
        for i in 0..<n { e[i].repeticiones = lector.varint() }
        for i in 0..<n { e[i].largo = lector.varint() }
        for i in 0..<n {
            let v = lector.varint()
            e[i].offset = (i > 0 && v == 0) ? e[i - 1].offset + e[i - 1].largo : v &- 1
        }
        directorios[offset] = e
        return e
    }

    private func datosTesela(z: Int, x: Int, y: Int) -> Data? {
        let id = Self.idTesela(z: z, x: x, y: y)
        var (offset, largo) = cabecera.raiz
        for _ in 0..<4 {
            let e = directorio(offset, largo)
            guard let entrada = Self.buscar(e, id) else { return nil }
            if entrada.repeticiones == 0 {
                offset = cabecera.hojas + entrada.offset
                largo = entrada.largo
            } else {
                guard let crudo = trozo(cabecera.teselas + entrada.offset, entrada.largo) else { return nil }
                return cabecera.compresionTeselas == 2 ? Self.gunzip(crudo) : crudo
            }
        }
        return nil
    }

    private static func buscar(_ e: [Entrada], _ id: UInt64) -> Entrada? {
        var m = 0, n = e.count - 1
        while m <= n {
            let k = (n + m) >> 1
            if id > e[k].id { m = k + 1 } else if id < e[k].id { n = k - 1 } else { return e[k] }
        }
        if n >= 0 {
            if e[n].repeticiones == 0 { return e[n] }
            if id - e[n].id < e[n].repeticiones { return e[n] }
        }
        return nil
    }

    // MARK: Teselas

    private func lineas(z: Int, x: Int, y: Int) -> [[CLLocationCoordinate2D]] {
        let clave = Self.idTesela(z: z, x: x, y: y)
        if let hecho = teselas[clave] { return hecho }
        var res: [[CLLocationCoordinate2D]] = []
        if let d = datosTesela(z: z, x: x, y: y) {
            for geo in Self.geometriasCalles(d) {
                res.append(geo.map { Self.coordenada(tx: x, ty: y, z: z, px: $0.x, py: $0.y, extension_: $0.ext) })
            }
        }
        teselas[clave] = res
        return res
    }

    /// Las líneas (en unidades de tesela) de la capa «calles» de una Mapbox Vector Tile.
    private static func geometriasCalles(_ d: Data) -> [[(x: Double, y: Double, ext: Double)]] {
        var tile = Lector(d)
        var res: [[(x: Double, y: Double, ext: Double)]] = []
        while !tile.fin {
            let (campo, tipo) = tile.etiqueta()
            guard campo == 3, tipo == 2 else { tile.saltar(tipo); continue }
            var capa = Lector(tile.bytes())
            var nombre = ""
            var extent: Double = 4096
            var geometrias: [[UInt32]] = []
            while !capa.fin {
                let (c, t) = capa.etiqueta()
                switch (c, t) {
                case (1, 2): nombre = String(decoding: capa.bytes(), as: UTF8.self)
                case (5, 0): extent = Double(capa.varint())
                case (2, 2):
                    var f = Lector(capa.bytes())
                    var tipoGeo: UInt64 = 0
                    var geo: [UInt32] = []
                    while !f.fin {
                        let (fc, ft) = f.etiqueta()
                        switch (fc, ft) {
                        case (3, 0): tipoGeo = f.varint()
                        case (4, 2):
                            var g = Lector(f.bytes())
                            while !g.fin { geo.append(UInt32(truncatingIfNeeded: g.varint())) }
                        default: f.saltar(ft)
                        }
                    }
                    if tipoGeo == 2 { geometrias.append(geo) }
                default: capa.saltar(t)
                }
            }
            guard nombre == "calles" else { continue }
            for geo in geometrias {
                var i = 0, cx: Int64 = 0, cy: Int64 = 0
                var actual: [(x: Double, y: Double, ext: Double)] = []
                while i < geo.count {
                    let cmd = geo[i] & 0x7, cuenta = Int(geo[i] >> 3)
                    i += 1
                    if cmd == 1 || cmd == 2 {
                        if cmd == 1, actual.count > 1 { res.append(actual) }
                        if cmd == 1 { actual = [] }
                        for _ in 0..<cuenta {
                            guard i + 1 < geo.count else { i = geo.count; break }
                            cx += Int64(zigzag(geo[i])); cy += Int64(zigzag(geo[i + 1]))
                            i += 2
                            actual.append((Double(cx), Double(cy), extent))
                        }
                    } else if cmd == 7 {
                        continue
                    } else {
                        break
                    }
                }
                if actual.count > 1 { res.append(actual) }
            }
        }
        return res
    }

    private static func zigzag(_ v: UInt32) -> Int32 { Int32(bitPattern: (v >> 1) ^ (0 &- (v & 1))) }

    private static func coordenada(tx: Int, ty: Int, z: Int, px: Double, py: Double, extension_ e: Double) -> CLLocationCoordinate2D {
        let n = Double(1 << z)
        let x = (Double(tx) + px / e) / n
        let y = (Double(ty) + py / e) / n
        let lon = x * 360 - 180
        let lat = atan(sinh(.pi * (1 - 2 * y))) * 180 / .pi
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    static func tesela(lat: Double, lon: Double, z: Int) -> SIMD2<Int> {
        let n = Double(1 << z)
        let x = Int((lon + 180) / 360 * n)
        let r = lat * .pi / 180
        let y = Int((1 - log(tan(r) + 1 / cos(r)) / .pi) / 2 * n)
        return SIMD2(x, y)
    }

    /// ID de tesela de PMTiles (curva de Hilbert), igual que `zxy_to_tileid` de la referencia.
    static func idTesela(z: Int, x: Int, y: Int) -> UInt64 {
        var acc = (UInt64(1) << UInt64(z * 2) - 1) / 3
        var x = UInt64(x), y = UInt64(y)
        var a = z - 1
        while a >= 0 {
            let s = UInt64(1) << UInt64(a)
            let rx = s & x, ry = s & y
            acc += ((3 * rx) ^ ry) << UInt64(a)
            if ry == 0 {
                if rx != 0 { x = s - 1 - x; y = s - 1 - y }
                swap(&x, &y)
            }
            a -= 1
        }
        return acc
    }

    // MARK: gzip

    /// gzip → bytes (quita la cabecera y el pie de gzip y descomprime el DEFLATE crudo).
    static func gunzip(_ d: Data) -> Data? {
        let b = [UInt8](d)
        guard b.count > 18, b[0] == 0x1f, b[1] == 0x8b, b[2] == 8 else { return nil }
        let flags = b[3]
        var i = 10
        if flags & 4 != 0, i + 2 <= b.count { i += 2 + Int(b[i]) | (Int(b[i + 1]) << 8) }
        if flags & 8 != 0 { while i < b.count, b[i] != 0 { i += 1 }; i += 1 }
        if flags & 16 != 0 { while i < b.count, b[i] != 0 { i += 1 }; i += 1 }
        if flags & 2 != 0 { i += 2 }
        guard i < b.count - 8 else { return nil }
        let crudo = Data(b[i..<(b.count - 8)])
        return try? (crudo as NSData).decompressed(using: .zlib) as Data
    }
}

/// Lector mínimo de protobuf y varints.
private struct Lector {
    let d: [UInt8]
    var i = 0
    init(_ datos: Data) { d = [UInt8](datos) }
    init(_ bytes: [UInt8]) { d = bytes }
    var fin: Bool { i >= d.count }

    mutating func varint() -> UInt64 {
        var v: UInt64 = 0, s: UInt64 = 0
        while i < d.count {
            let b = d[i]; i += 1
            v |= UInt64(b & 0x7f) << s
            if b & 0x80 == 0 { break }
            s += 7
            if s > 63 { break }
        }
        return v
    }

    mutating func etiqueta() -> (Int, Int) {
        let v = varint()
        return (Int(v >> 3), Int(v & 7))
    }

    mutating func bytes() -> [UInt8] {
        let n = Int(varint())
        let fin = min(d.count, i + n)
        let r = Array(d[i..<fin])
        i = fin
        return r
    }

    mutating func saltar(_ tipo: Int) {
        switch tipo {
        case 0: _ = varint()
        case 1: i += 8
        case 2:
            let n = Int(varint()) // primero el largo (mueve `i`), luego saltar
            i = min(d.count, i + n)
        case 5: i += 4
        default: i = d.count
        }
    }
}
