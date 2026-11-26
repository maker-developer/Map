import UIKit
import CoreLocation
import MapLibre

/// La ruta llega de OSRM con la geometría de OpenStreetMap, pero las calles del mapa son las del
/// condado (StreetNetwork de Miami-Dade): las dos fuentes no coinciden al metro y la línea azul
/// iba por el lado de la calle (sobre un canal, por una acera…).
///
/// Arreglo provisional (hasta que el motor de rutas use nuestras mismas calles, ronda 4): en cuanto
/// llega la ruta, se leen nuestras calles a lo largo de todo el recorrido directamente de
/// `base.pmtiles` (`CallesLocales`) y cada vértice se pega a la calle más cercana que vaya en su mismo
/// sentido (≤ 35 m); en los giros, al cruce de la calle por la que llega con la de salida. Va en segundo
/// plano y la línea se redibuja ya pegada. Solo cambia el dibujo: la navegación usa la geometría original.
extension MapaMapLibre.Coordinador {
    static func firma(_ ruta: Ruta) -> String {
        guard let p = ruta.coordenadas.first, let u = ruta.coordenadas.last else { return "\(ruta.id)" }
        return "\(ruta.id)|\(ruta.coordenadas.count)|\(p.latitude),\(p.longitude)|\(u.latitude),\(u.longitude)"
    }

    /// La geometría para dibujar, pegada a nuestras calles (o la original mientras se pega en
    /// segundo plano; al terminar se redibuja).
    func coordenadasDibujo(_ ruta: Ruta, mapa: MLNMapView) -> PegadoRuta.Resultado {
        let f = Self.firma(ruta)
        if let hecho = ajustesRuta[f] { return hecho }
        pegar(ruta, firma: f, mapa: mapa)
        return PegadoRuta.Resultado(puntos: ruta.coordenadas, indice: Array(ruta.coordenadas.indices))
    }

    private func pegar(_ ruta: Ruta, firma f: String, mapa: MLNMapView) {
        guard !pegando.contains(f), ruta.coordenadas.count > 1 else { return }
        pegando.insert(f)
        let coordenadas = ruta.coordenadas
        Task.detached(priority: .userInitiated) { [weak self, weak mapa] in
            let lineas = CallesLocales.compartidas.lineas(cerca: coordenadas)
            let ajustes = PegadoRuta.pegar(coordenadas, a: lineas)
            await MainActor.run {
                guard let self else { return }
                self.pegando.remove(f)
                self.ajustesRuta[f] = ajustes
                // Olvidar rutas viejas para no acumular.
                if let vigentes = self.padre.navegador?.rutas.map(Self.firma) {
                    self.ajustesRuta = self.ajustesRuta.filter { vigentes.contains($0.key) }
                }
                if let mapa { self.dibujarRutas(en: mapa) }
            }
        }
    }
}

/// El pegado en sí: geometría pura, sin MapLibre (se puede llamar desde cualquier hilo).
enum PegadoRuta {
    static let radio: Double = 35          // metros
    static let toleranciaRumbo: Double = 30 // grados
    static let celda: Double = 60          // metros (rejilla para buscar rápido)

    struct Segmento {
        let a: SIMD2<Double>
        let b: SIMD2<Double>
        /// Rumbo de la calle sin sentido (0…180).
        let rumbo: Double
    }

    /// La ruta lista para dibujar: `puntos` (con puntos intermedios cada ~12 m para seguir las curvas
    /// de la calle) e `indice[k]` = dónde quedó el vértice original `k` dentro de `puntos`.
    struct Resultado {
        let puntos: [CLLocationCoordinate2D]
        let indice: [Int]
    }

    static func pegar(_ original: [CLLocationCoordinate2D], a lineas: [[CLLocationCoordinate2D]]) -> Resultado {
        let sinCambios = Resultado(puntos: original, indice: Array(original.indices))
        guard let origen = original.first, original.count > 1, !lineas.isEmpty else { return sinCambios }
        let mLat = 111_320.0
        let mLon = 111_320.0 * cos(origen.latitude * .pi / 180)
        func local(_ c: CLLocationCoordinate2D) -> SIMD2<Double> {
            SIMD2((c.longitude - origen.longitude) * mLon, (c.latitude - origen.latitude) * mLat)
        }
        func geo(_ p: SIMD2<Double>) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: origen.latitude + p.y / mLat, longitude: origen.longitude + p.x / mLon)
        }
        func clave(_ p: SIMD2<Double>) -> SIMD2<Int> { SIMD2(Int(floor(p.x / celda)), Int(floor(p.y / celda))) }

        // Segmentos de nuestras calles en una rejilla.
        var rejilla: [SIMD2<Int>: [Segmento]] = [:]
        for linea in lineas where linea.count > 1 {
            for k in 0..<(linea.count - 1) {
                let a = local(linea[k]), b = local(linea[k + 1])
                let d = b - a
                guard d.x * d.x + d.y * d.y > 0.25 else { continue }
                let seg = Segmento(a: a, b: b, rumbo: rumboSinSentido(d))
                let ka = clave(a), kb = clave(b)
                guard abs(ka.x - kb.x) < 50, abs(ka.y - kb.y) < 50 else { continue }
                for x in min(ka.x, kb.x)...max(ka.x, kb.x) {
                    for y in min(ka.y, kb.y)...max(ka.y, kb.y) { rejilla[SIMD2(x, y), default: []].append(seg) }
                }
            }
        }

        /// La proyección más cercana sobre una calle con el rumbo pedido (o nil).
        func mejor(_ p: SIMD2<Double>, rumbo: Double) -> (punto: SIMD2<Double>, seg: Segmento)? {
            let k = clave(p)
            var res: (SIMD2<Double>, Segmento, Double)?
            for x in (k.x - 1)...(k.x + 1) {
                for y in (k.y - 1)...(k.y + 1) {
                    for s in rejilla[SIMD2(x, y)] ?? [] {
                        guard diferencia(s.rumbo, rumbo) <= toleranciaRumbo else { continue }
                        let q = proyectar(p, s.a, s.b)
                        let dist = largo(q - p)
                        if dist <= radio, dist < (res?.2 ?? .infinity) { res = (q, s, dist) }
                    }
                }
            }
            guard let r = res else { return nil }
            return (punto: r.0, seg: r.1)
        }

        // Puntos intermedios cada ~12 m: así la línea sigue las curvas de nuestra calle entre vértices.
        var p: [SIMD2<Double>] = []
        var indice: [Int] = []
        let o = original.map(local)
        for k in o.indices {
            indice.append(p.count)
            p.append(o[k])
            guard k + 1 < o.count else { break }
            let n = min(200, Int(largo(o[k + 1] - o[k]) / 12))
            if n > 1 { for j in 1..<n { p.append(o[k] + (o[k + 1] - o[k]) * (Double(j) / Double(n))) } }
        }

        var salida = p
        for i in p.indices {
            // Rumbo de llegada y de salida (mirando unos metros, no el vértice de al lado, que puede
            // estar a centímetros y dar un rumbo cualquiera).
            let rEntra = rumboHacia(p, desde: i, paso: -1)
            let rSale = rumboHacia(p, desde: i, paso: 1)
            if let rEntra, let rSale, diferencia(rEntra, rSale) > toleranciaRumbo {
                // Giro: al cruce de la calle por la que llega con la calle por la que sale.
                if let entra = mejor(p[i], rumbo: rEntra), let sale = mejor(p[i], rumbo: rSale),
                   let x = cruce(entra.seg, sale.seg), largo(x - p[i]) <= radio * 1.3 {
                    salida[i] = x
                } else if let m = mejor(p[i], rumbo: rEntra) ?? mejor(p[i], rumbo: rSale) {
                    salida[i] = m.punto
                }
            } else if let rumbo = rEntra ?? rSale, let m = mejor(p[i], rumbo: rumbo) {
                salida[i] = m.punto
            }
        }
        return Resultado(puntos: salida.map(geo), indice: indice)
    }

    /// Rumbo desde el vértice `i` hacia el primer vértice a ≥ 8 m (hacia atrás o hacia delante).
    private static func rumboHacia(_ p: [SIMD2<Double>], desde i: Int, paso: Int) -> Double? {
        var j = i + paso
        while j >= 0, j < p.count {
            let d = paso > 0 ? p[j] - p[i] : p[i] - p[j]
            if largo(d) >= 8 { return rumboSinSentido(d) }
            j += paso
        }
        return nil
    }

    private static func largo(_ d: SIMD2<Double>) -> Double { (d.x * d.x + d.y * d.y).squareRoot() }

    static func rumboSinSentido(_ d: SIMD2<Double>) -> Double {
        var r = atan2(d.x, d.y) * 180 / .pi
        if r < 0 { r += 180 }
        if r >= 180 { r -= 180 }
        return r
    }

    static func diferencia(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 180)
        return min(d, 180 - d)
    }

    private static func proyectar(_ p: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> SIMD2<Double> {
        let ab = b - a
        let largo2 = ab.x * ab.x + ab.y * ab.y
        guard largo2 > 0 else { return a }
        let t = max(0, min(1, ((p - a).x * ab.x + (p - a).y * ab.y) / largo2))
        return a + ab * t
    }

    /// Cruce de las rectas de dos segmentos (nil si son casi paralelas).
    private static func cruce(_ s: Segmento, _ t: Segmento) -> SIMD2<Double>? {
        let r = s.b - s.a, q = t.b - t.a
        let den = r.x * q.y - r.y * q.x
        guard abs(den) > 1e-6 else { return nil }
        let w = t.a - s.a
        let u = (w.x * q.y - w.y * q.x) / den
        return s.a + r * u
    }
}
