import SwiftUI
import MapLibre

/// Zonas para recorrer (las mismas del visor web, de `public/data/manifest.json`).
enum Zona: String, CaseIterable, Identifiable {
    case condado, brickell, miamiBeach, miamiLakes, bahia

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .condado: "Todo el condado"
        case .brickell: "Downtown y Brickell"
        case .miamiBeach: "Miami Beach"
        case .miamiLakes: "Miami Lakes"
        case .bahia: "Bahía de Biscayne"
        }
    }

    var centro: CLLocationCoordinate2D {
        switch self {
        case .condado: CLLocationCoordinate2D(latitude: 25.56, longitude: -80.47)
        case .brickell: CLLocationCoordinate2D(latitude: 25.770, longitude: -80.196)
        case .miamiBeach: CLLocationCoordinate2D(latitude: 25.783, longitude: -80.137)
        case .miamiLakes: CLLocationCoordinate2D(latitude: 25.914, longitude: -80.320)
        case .bahia: CLLocationCoordinate2D(latitude: 25.735, longitude: -80.185)
        }
    }

    /// Zoom del visor web (MapLibre Native usa la misma escala).
    var zoom: Double {
        switch self {
        case .condado: 8.6
        case .brickell: 15.45
        case .miamiBeach: 15.25
        case .miamiLakes: 14.85
        case .bahia: 11.6
        }
    }

    var rumbo: Double {
        switch self {
        case .condado: 0
        case .brickell: -20
        case .miamiBeach: -25
        case .miamiLakes: -21
        case .bahia: 0
        }
    }
}

/// Lo que se tocó en el mapa: un edificio o una parada.
struct ElementoTocado: Identifiable, Equatable {
    enum Tipo { case edificio, parada }
    let id = UUID()
    let tipo: Tipo
    let titulo: String
    let detalle: String
}

/// Medidas en vivo del mapa para comparar experimentos.
@Observable
final class Medidas {
    /// Desde que se crea el mapa hasta que se dibuja completo por primera vez.
    var primerDibujo: TimeInterval?
    /// Cuadros por segundo del mapa mientras se mueve (nil en reposo).
    var cuadrosPorSegundo: Int?
    /// Memoria del app en MB.
    var memoriaMB: Int = 0
    var error: String?

    // Contadores internos: no deben redibujar la interfaz en cada cuadro.
    @ObservationIgnored fileprivate var inicio = Date()
    @ObservationIgnored fileprivate var cuadros = 0
    @ObservationIgnored fileprivate var ultimoCorte = Date()

    func reiniciar() {
        primerDibujo = nil
        cuadrosPorSegundo = nil
        error = nil
        inicio = Date()
    }

    fileprivate func contarCuadro() {
        cuadros += 1
        let ahora = Date()
        let pasado = ahora.timeIntervalSince(ultimoCorte)
        if pasado >= 1 {
            cuadrosPorSegundo = Int((Double(cuadros) / pasado).rounded())
            cuadros = 0
            ultimoCorte = ahora
            memoriaMB = Self.memoria()
        }
    }

    fileprivate func enReposo() {
        cuadrosPorSegundo = nil
        cuadros = 0
        ultimoCorte = Date()
        memoriaMB = Self.memoria()
    }

    /// Memoria física que el sistema cuenta para el app (la misma que enseña Xcode).
    static func memoria() -> Int {
        var info = task_vm_info_data_t()
        var cantidad = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let resultado = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(cantidad)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &cantidad)
            }
        }
        guard resultado == KERN_SUCCESS else { return 0 }
        return Int(info.phys_footprint / 1_048_576)
    }
}

/// `MLNMapView` de MapLibre Native dentro de SwiftUI.
struct MapaMapLibre: UIViewRepresentable {
    var estilo: EstiloMapa
    var zona: Zona
    /// Inclinación al ir a una zona con edificios en 3D (el visor web usa 54°).
    var inclinacion: Double
    var medidas: Medidas
    @Binding var tocado: ElementoTocado?
    /// Sube cada vez que el usuario pide centrar en su ubicación.
    var centrarEnMi: Int

    func makeCoordinator() -> Coordinador { Coordinador(self) }

    func makeUIView(context: Context) -> MLNMapView {
        // Nace con nuestro estilo (sin él, MapLibre pediría su mapa de demostración a internet).
        let url: URL?
        do {
            url = try estilo.escribir()
        } catch {
            url = nil
            medidas.error = "No se pudo escribir el estilo: \(error.localizedDescription)"
        }
        let mapa = MLNMapView(frame: .zero, styleURL: url)
        mapa.delegate = context.coordinator
        mapa.logoView.isHidden = true
        mapa.attributionButton.isHidden = true
        mapa.showsUserLocation = true
        mapa.compassViewPosition = .topRight
        mapa.minimumZoomLevel = 7
        mapa.maximumZoomLevel = 20
        mapa.setCenter(zona.centro, zoomLevel: zona.zoom, direction: zona.rumbo, animated: false)

        let toque = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinador.tocar(_:)))
        // Que no compita con el doble toque para acercar.
        for gesto in mapa.gestureRecognizers ?? [] where (gesto as? UITapGestureRecognizer)?.numberOfTapsRequired == 2 {
            toque.require(toFail: gesto)
        }
        mapa.addGestureRecognizer(toque)
        return mapa
    }

    func updateUIView(_ mapa: MLNMapView, context: Context) {
        let c = context.coordinator
        c.padre = self

        // Tema, orden de capas u origen de datos: hace falta otro JSON de estilo.
        if estilo.tema != c.estilo.tema || estilo.edificiosTapan != c.estilo.edificiosTapan
            || estilo.origen != c.estilo.origen || estilo.ronda1 != c.estilo.ronda1 {
            c.cargarEstilo(en: mapa, estilo)
        } else if estilo.edificios3D != c.estilo.edificios3D || estilo.transporte != c.estilo.transporte {
            // Solo visibilidad: se cambia en el estilo ya cargado, sin recargar.
            c.estilo = estilo
            c.aplicarVisibilidad(mapa)
        }

        if zona != c.zona {
            c.zona = zona
            c.ir(a: zona, en: mapa)
        } else if inclinacion != c.inclinacion {
            // Nueva inclinación elegida en el menú: se aplica ya si el mapa está en 3D.
            c.inclinacion = inclinacion
            if estilo.edificios3D, mapa.camera.pitch > 0 { c.inclinar(mapa, a: inclinacion) }
        }

        if centrarEnMi != c.centrarEnMi {
            c.centrarEnMi = centrarEnMi
            if let aqui = mapa.userLocation?.location?.coordinate, CLLocationCoordinate2DIsValid(aqui) {
                mapa.setCenter(aqui, zoomLevel: max(mapa.zoomLevel, 16), animated: true)
            }
        }
    }

    final class Coordinador: NSObject, MLNMapViewDelegate {
        var padre: MapaMapLibre
        var estilo: EstiloMapa
        var zona: Zona
        var inclinacion: Double
        var centrarEnMi: Int

        init(_ padre: MapaMapLibre) {
            self.padre = padre
            self.estilo = padre.estilo
            self.zona = padre.zona
            self.inclinacion = padre.inclinacion
            self.centrarEnMi = padre.centrarEnMi
        }

        func cargarEstilo(en mapa: MLNMapView, _ nuevo: EstiloMapa) {
            estilo = nuevo
            do {
                mapa.styleURL = try nuevo.escribir()
            } catch {
                padre.medidas.error = "No se pudo escribir el estilo: \(error.localizedDescription)"
            }
        }

        func aplicarVisibilidad(_ mapa: MLNMapView) {
            guard let style = mapa.style else { return }
            style.layer(withIdentifier: "buildings-volume")?.isVisible = estilo.edificios3D
            style.layer(withIdentifier: "buildings-footprints")?.isVisible = !estilo.edificios3D
            style.layer(withIdentifier: "transit-routes")?.isVisible = estilo.transporte
            style.layer(withIdentifier: "transit-stops")?.isVisible = estilo.transporte
            if estilo.edificios3D, zona != .condado, mapa.camera.pitch < 1 {
                inclinar(mapa, a: padre.inclinacion)
            } else if !estilo.edificios3D, mapa.camera.pitch > 0 {
                inclinar(mapa, a: 0)
            }
        }

        /// Vuela a la zona y, con 3D, la inclina como el visor web.
        func ir(a zona: Zona, en mapa: MLNMapView) {
            let inclinar3D = estilo.edificios3D && zona != .condado && zona != .bahia
            mapa.setCenter(zona.centro, zoomLevel: zona.zoom, direction: inclinar3D ? zona.rumbo : 0, animated: true) { [weak self] in
                guard let self else { return }
                self.inclinar(mapa, a: inclinar3D ? self.padre.inclinacion : 0)
            }
        }

        func inclinar(_ mapa: MLNMapView, a grados: Double) {
            let camara = mapa.camera
            camara.pitch = grados
            mapa.setCamera(camara, withDuration: 0.45, animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut))
        }

        // MARK: Toques

        @objc func tocar(_ gesto: UITapGestureRecognizer) {
            guard let mapa = gesto.view as? MLNMapView else { return }
            let punto = gesto.location(in: mapa)
            // Primero las paradas (son pequeñas y van encima); luego los edificios.
            if estilo.transporte,
               let parada = mapa.visibleFeatures(at: punto, styleLayerIdentifiers: ["transit-stops"]).first {
                let nombre = parada.attribute(forKey: "name") as? String ?? "Parada"
                let rutas = parada.attribute(forKey: "routes") as? String ?? ""
                padre.tocado = ElementoTocado(tipo: .parada, titulo: Texto.bonito(nombre),
                                              detalle: rutas.isEmpty ? "Parada de transporte" : "Rutas: \(rutas)")
                return
            }
            let capas: Set<String> = estilo.edificios3D ? ["buildings-volume"] : ["buildings-footprints"]
            if let edificio = mapa.visibleFeatures(at: punto, styleLayerIdentifiers: capas).first {
                let direccion = (edificio.attribute(forKey: "address") as? String).flatMap { $0.isEmpty ? nil : $0 }
                let altura = (edificio.attribute(forKey: "height") as? NSNumber)?.doubleValue
                padre.tocado = ElementoTocado(
                    tipo: .edificio,
                    titulo: direccion.map(Texto.bonito) ?? "Edificio",
                    detalle: altura.map { "Altura en el inventario: \(Int($0.rounded())) m" } ?? "Altura sin publicar"
                )
                return
            }
            padre.tocado = nil
        }

        // MARK: MLNMapViewDelegate

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            padre.medidas.error = nil
            Escudos.registrar(en: style)
            aplicarVisibilidad(mapView)
        }

        func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
            padre.medidas.error = error.localizedDescription
        }

        func mapViewDidFinishRenderingMap(_ mapView: MLNMapView, fullyRendered: Bool) {
            guard fullyRendered, padre.medidas.primerDibujo == nil else { return }
            padre.medidas.primerDibujo = Date().timeIntervalSince(padre.medidas.inicio)
            padre.medidas.memoriaMB = Medidas.memoria()
        }

        func mapViewDidFinishRenderingFrame(_ mapView: MLNMapView, fullyRendered: Bool) {
            padre.medidas.contarCuadro()
        }

        func mapViewDidBecomeIdle(_ mapView: MLNMapView) {
            padre.medidas.enReposo()
        }
    }
}
