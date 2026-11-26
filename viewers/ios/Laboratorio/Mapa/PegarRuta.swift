import UIKit
import CoreLocation
import MapLibre

/// La ruta llega de OSRM con la geometría de OpenStreetMap, pero las calles del mapa son las del
/// condado (StreetNetwork de Miami-Dade): las dos fuentes no coinciden al metro y la línea azul
/// a veces iba por el lado de la calle (sobre un canal, por una acera…).
///
/// Arreglo provisional (hasta que el motor de rutas use nuestras mismas calles, ronda 4): cuando el
/// mapa queda quieto y cerca (zoom 14 o más), cada vértice de la ruta que se ve se pega a la calle
/// nuestra más cercana que vaya en su mismo sentido (≤ 28 m). En los giros, el vértice va al cruce
/// de la calle de entrada con la de salida. Lo pegado se guarda y se va acumulando al moverse.
/// Solo cambia el dibujo: la navegación sigue usando la geometría original.
extension MapaMapLibre.Coordinador {
    private static let radio: Double = 28        // metros
    private static let toleranciaRumbo: Double = 30 // grados
    private static let celda: Double = 60        // metros (rejilla para buscar rápido)

    private struct Segmento {
        let a: SIMD2<Double>
        let b: SIMD2<Double>
        /// Rumbo de la calle sin sentido (0…180).
        let rumbo: Double
    }

    static func firma(_ ruta: Ruta) -> String {
        guard let p = ruta.coordenadas.first, let u = ruta.coordenadas.last else { return "\(ruta.id)" }
        return "\(ruta.id)|\(ruta.coordenadas.count)|\(p.latitude),\(p.longitude)|\(u.latitude),\(u.longitude)"
    }

    /// La geometría para dibujar: la original con los vértices ya pegados a nuestras calles.
    func coordenadasDibujo(_ ruta: Ruta) -> [CLLocationCoordinate2D] {
        guard let ajustes = ajustesRuta[Self.firma(ruta)], !ajustes.isEmpty else { return ruta.coordenadas }
        var c = ruta.coordenadas
        for (i, punto) in ajustes where i < c.count { c[i] = punto }
        return c
    }

    func pegarRutasACalles(en mapa: MLNMapView) {
        guard let navegador = padre.navegador, navegador.fase == .ruta || navegador.fase == .navegando,
              !navegador.rutas.isEmpty, mapa.zoomLevel >= 14, let estilo = mapa.style else { return }

        // Olvidar ajustes de rutas que ya no están.
        let vigentes = Set(navegador.rutas.map(Self.firma))
        ajustesRuta = ajustesRuta.filter { vigentes.contains($0.key) }

        // Nuestras calles tal como se ven ahora (teselas a todo detalle).
        let capas = Set(estilo.layers.compactMap { capa -> String? in
            guard let linea = capa as? MLNLineStyleLayer, linea.sourceLayerIdentifier == "calles",
                  !linea.identifier.contains("sombra") else { return nil }
            return linea.identifier
        })
        guard !capas.isEmpty else { return }
        let rasgos = mapa.visibleFeatures(in: mapa.bounds, styleLayerIdentifiers: capas)
        guard !rasgos.isEmpty else { return }

        // Metros locales alrededor del centro.
        let centro = mapa.centerCoordinate
        let mLat = 111_320.0
        let mLon = 111_320.0 * cos(centro.latitude * .pi / 180)
        func local(_ c: CLLocationCoordinate2D) -> SIMD2<Double> {
            SIMD2((c.longitude - centro.longitude) * mLon, (c.latitude - centro.latitude) * mLat)
        }
        func geo(_ p: SIMD2<Double>) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: centro.latitude + p.y / mLat, longitude: centro.longitude + p.x / mLon)
        }

        // Segmentos en una rejilla.
        var rejilla: [SIMD2<Int>: [Segmento]] = [:]
        func clave(_ p: SIMD2<Double>) -> SIMD2<Int> { SIMD2(Int(floor(p.x / Self.celda)), Int(floor(p.y / Self.celda))) }
        func agregar(_ linea: MLNPolyline) {
            let n = Int(linea.pointCount)
            guard n > 1 else { return }
            let pts = linea.coordinates
            for k in 0..<(n - 1) {
                let a = local(pts[k]), b = local(pts[k + 1])
                let d = b - a
                guard d.x * d.x + d.y * d.y > 0.25 else { continue }
                let seg = Segmento(a: a, b: b, rumbo: Self.rumboSinSentido(d))
                let ka = clave(a), kb = clave(b)
                for x in min(ka.x, kb.x)...max(ka.x, kb.x) {
                    for y in min(ka.y, kb.y)...max(ka.y, kb.y) { rejilla[SIMD2(x, y), default: []].append(seg) }
                }
            }
        }
        for rasgo in rasgos {
            if let multi = rasgo as? MLNMultiPolylineFeature {
                multi.polylines.forEach(agregar)
            } else if let linea = rasgo as? MLNPolylineFeature {
                agregar(linea)
            }
        }
        guard !rejilla.isEmpty else { return }

        /// La proyección más cercana sobre una calle con el rumbo pedido (o nil).
        func mejor(_ p: SIMD2<Double>, rumbo: Double) -> (punto: SIMD2<Double>, seg: Segmento)? {
            let k = clave(p)
            var res: (SIMD2<Double>, Segmento, Double)?
            for x in (k.x - 1)...(k.x + 1) {
                for y in (k.y - 1)...(k.y + 1) {
                    for s in rejilla[SIMD2(x, y)] ?? [] {
                        guard Self.diferencia(s.rumbo, rumbo) <= Self.toleranciaRumbo else { continue }
                        let q = Self.proyectar(p, s.a, s.b)
                        let d = q - p
                        let dist = (d.x * d.x + d.y * d.y).squareRoot()
                        if dist <= Self.radio, dist < (res?.2 ?? .infinity) { res = (q, s, dist) }
                    }
                }
            }
            guard let r = res else { return nil }
            return (punto: r.0, seg: r.1)
        }

        let visibles = mapa.visibleCoordinateBounds
        let margen = 0.002
        var cambio = false
        for ruta in navegador.rutas {
            let c = ruta.coordenadas
            guard c.count > 1 else { continue }
            let f = Self.firma(ruta)
            var ajustes = ajustesRuta[f] ?? [:]
            for i in c.indices where ajustes[i] == nil {
                let v = c[i]
                guard v.latitude >= visibles.sw.latitude - margen, v.latitude <= visibles.ne.latitude + margen,
                      v.longitude >= visibles.sw.longitude - margen, v.longitude <= visibles.ne.longitude + margen
                else { continue }
                let p = local(v)
                let antes = i > 0 ? local(c[i - 1]) : nil
                let despues = i < c.count - 1 ? local(c[i + 1]) : nil
                let rEntra = antes.map { Self.rumboSinSentido(p - $0) }
                let rSale = despues.map { Self.rumboSinSentido($0 - p) }

                if let rEntra, let rSale, Self.diferencia(rEntra, rSale) > Self.toleranciaRumbo {
                    // Giro: al cruce de la calle por la que llega con la calle por la que sale.
                    if let entra = mejor(p, rumbo: rEntra), let sale = mejor(p, rumbo: rSale),
                       let cruce = Self.cruce(entra.seg, sale.seg) {
                        let d = cruce - p
                        if (d.x * d.x + d.y * d.y).squareRoot() <= Self.radio * 1.3 {
                            ajustes[i] = geo(cruce); cambio = true
                        }
                    }
                } else if let rumbo = rEntra ?? rSale {
                    if let m = mejor(p, rumbo: rumbo) { ajustes[i] = geo(m.punto); cambio = true }
                }
            }
            ajustesRuta[f] = ajustes
        }
        if cambio { dibujarRutas(en: mapa) }
    }

    // MARK: Geometría

    private static func rumboSinSentido(_ d: SIMD2<Double>) -> Double {
        var r = atan2(d.x, d.y) * 180 / .pi
        if r < 0 { r += 180 }
        if r >= 180 { r -= 180 }
        return r
    }

    private static func diferencia(_ a: Double, _ b: Double) -> Double {
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
