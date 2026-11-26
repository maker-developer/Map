import UIKit
import MapLibre

/// Rutas en el mapa, como Apple y Google: la elegida en azul grueso con borde, las alternativas en
/// gris debajo (se tocan para elegirlas), el tiempo de cada una encima y el pin del destino.
/// Al navegar, la cámara te sigue inclinada en tu sentido de marcha.
extension MapaMapLibre.Coordinador {
    private enum ID {
        static let altFuente = "rutas-alt"
        static let altBorde = "rutas-alt-borde"
        static let altLinea = "rutas-alt-linea"
        static let selFuente = "ruta-sel"
        static let selBorde = "ruta-sel-borde"
        static let selLinea = "ruta-sel-linea"
        static let etaFuente = "rutas-eta"
        static let etaCapa = "rutas-eta-texto"
    }

    /// Capa del estilo bajo la que van las rutas (por debajo de nombres, edificios y escudos).
    private func debajoDe(_ estilo: MLNStyle) -> MLNStyleLayer? {
        estilo.layer(withIdentifier: "street-names")
    }

    /// Crea fuentes y capas de rutas en el estilo cargado (hay que repetirlo tras cada recarga de estilo).
    func prepararCapasRuta(_ estilo: MLNStyle) {
        guard estilo.source(withIdentifier: ID.selFuente) == nil else { return }
        let alt = MLNShapeSource(identifier: ID.altFuente, shape: nil, options: nil)
        let sel = MLNShapeSource(identifier: ID.selFuente, shape: nil, options: nil)
        let eta = MLNShapeSource(identifier: ID.etaFuente, shape: nil, options: nil)
        estilo.addSource(alt)
        estilo.addSource(sel)
        estilo.addSource(eta)

        func linea(_ id: String, _ fuente: MLNSource, color: UIColor, ancho: Double) -> MLNLineStyleLayer {
            let capa = MLNLineStyleLayer(identifier: id, source: fuente)
            capa.lineColor = NSExpression(forConstantValue: color)
            capa.lineWidth = NSExpression(forConstantValue: ancho)
            capa.lineCap = NSExpression(forConstantValue: "round")
            capa.lineJoin = NSExpression(forConstantValue: "round")
            return capa
        }
        let capas = [
            linea(ID.altBorde, alt, color: UIColor(white: 1, alpha: 0.95), ancho: 10),
            linea(ID.altLinea, alt, color: UIColor(red: 0.62, green: 0.68, blue: 0.75, alpha: 1), ancho: 6.5),
            linea(ID.selBorde, sel, color: UIColor(red: 0.07, green: 0.33, blue: 0.78, alpha: 1), ancho: 12),
            linea(ID.selLinea, sel, color: UIColor(red: 0.18, green: 0.52, blue: 0.98, alpha: 1), ancho: 8),
        ]
        for capa in capas {
            if let referencia = debajoDe(estilo) { estilo.insertLayer(capa, below: referencia) } else { estilo.addLayer(capa) }
        }

        // Tiempo de cada ruta en el mapa («12 min»), encima de todo.
        let textos = MLNSymbolStyleLayer(identifier: ID.etaCapa, source: eta)
        textos.text = NSExpression(forKeyPath: "eta")
        textos.textFontNames = NSExpression(forConstantValue: ["DMSans-SemiBold"])
        textos.textFontSize = NSExpression(forConstantValue: 13)
        textos.textColor = NSExpression(
            format: "TERNARY(elegida == YES, %@, %@)",
            UIColor(red: 0.07, green: 0.33, blue: 0.78, alpha: 1), UIColor.darkGray
        )
        textos.textHaloColor = NSExpression(forConstantValue: UIColor.white)
        textos.textHaloWidth = NSExpression(forConstantValue: 3)
        textos.textAllowsOverlap = NSExpression(forConstantValue: true)
        estilo.addLayer(textos)
    }

    /// Pone en el mapa las rutas del navegador (o las quita).
    func dibujarRutas(en mapa: MLNMapView) {
        guard let estilo = mapa.style, let navegador = padre.navegador else { return }
        prepararCapasRuta(estilo)
        let rutas = navegador.fase == .libre || navegador.fase == .lugar ? [] : navegador.rutas
        let elegida = navegador.elegida

        var alternativas: [MLNPolylineFeature] = []
        var seleccion: [MLNPolylineFeature] = []
        var etiquetas: [MLNPointFeature] = []
        for (i, ruta) in rutas.enumerated() where ruta.coordenadas.count > 1 {
            let linea = MLNPolylineFeature(coordinates: ruta.coordenadas, count: UInt(ruta.coordenadas.count))
            linea.attributes = ["indice": i]
            if i == elegida { seleccion.append(linea) } else { alternativas.append(linea) }
            // Durante la navegación no hacen falta los tiempos encima.
            if navegador.fase == .ruta {
                let punto = MLNPointFeature()
                punto.coordinate = ruta.coordenadas[ruta.coordenadas.count / 2]
                punto.attributes = ["eta": FormatoRuta.duracion(ruta.duracion), "elegida": i == elegida]
                etiquetas.append(punto)
            }
        }
        // En navegación solo queda la elegida.
        if navegador.fase == .navegando { alternativas = [] }

        (estilo.source(withIdentifier: ID.altFuente) as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: alternativas)
        (estilo.source(withIdentifier: ID.selFuente) as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: seleccion)
        (estilo.source(withIdentifier: ID.etaFuente) as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: etiquetas)

        // Línea a pie: puntitos, como en Apple Maps.
        if let linea = estilo.layer(withIdentifier: ID.selLinea) as? MLNLineStyleLayer {
            linea.lineDashPattern = navegador.modo == .pie ? NSExpression(forConstantValue: [0.1, 1.9]) : nil
        }
        if let borde = estilo.layer(withIdentifier: ID.selBorde) as? MLNLineStyleLayer {
            borde.isVisible = navegador.modo != .pie
        }

        // Pin del destino.
        let destino = navegador.fase == .libre ? nil : navegador.destino
        if destino?.id != pinDestinoID {
            if let anterior = pin { mapa.removeAnnotation(anterior) }
            pin = nil
            if let destino, !destino.esMiUbicacion {
                let nuevo = MLNPointAnnotation()
                nuevo.coordinate = destino.coordenada
                nuevo.title = destino.nombre
                mapa.addAnnotation(nuevo)
                pin = nuevo
            }
            pinDestinoID = destino?.id
        } else if let destino, let pin {
            pin.coordinate = destino.coordenada
            pin.title = destino.nombre
        }
    }

    /// Encuadra la ruta (o el destino) dejando sitio a la hoja de abajo, en plano como Apple y Google.
    func encuadrar(en mapa: MLNMapView) {
        guard let navegador = padre.navegador else { return }
        let relleno = UIEdgeInsets(top: 110, left: 50, bottom: 430, right: 70)
        if let ruta = navegador.rutaElegida, ruta.coordenadas.count > 1,
           navegador.fase == .ruta || navegador.fase == .navegando {
            // Resumen al navegar: la ruta entera, sin el hueco de la flecha abajo.
            if navegador.fase == .navegando { mapa.contentInset = .zero }
            let forma = MLNPolyline(coordinates: ruta.coordenadas, count: UInt(ruta.coordenadas.count))
            let camara = mapa.cameraThatFitsShape(forma, direction: 0, edgePadding: relleno)
            camara.pitch = 0
            mapa.setCamera(camara, withDuration: 0.7, animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut))
        } else if let destino = navegador.destino, navegador.fase == .lugar {
            mapa.setCenter(destino.coordenada, zoomLevel: max(mapa.zoomLevel, 15), animated: true)
        }
    }

    /// Cámara según la fase. Al navegar, la flecha va en el tercio de abajo (se ve más camino
    /// por delante, como en Apple y Google) y la cámara la sigue sola; fuera de la navegación, normal.
    func aplicarFase(en mapa: MLNMapView) {
        guard let navegador = padre.navegador else { return }
        let navegando = navegador.fase == .navegando
        mapa.showsUserHeadingIndicator = navegando
        if mapa.userTrackingMode != .none { mapa.userTrackingMode = .none }
        mapa.contentInset = navegando
            ? UIEdgeInsets(top: mapa.bounds.height * 0.42, left: 0, bottom: 120, right: 0)
            : .zero
        if navegando { seguir(en: mapa, duracion: 0.8) }
    }

    /// La cámara vuelve a seguirte («Volver a centrar» o al empezar).
    func seguir(en mapa: MLNMapView, duracion: TimeInterval = 0.6) {
        mapa.contentInset = UIEdgeInsets(top: mapa.bounds.height * 0.42, left: 0, bottom: 120, right: 0)
        camaraNavegacion(en: mapa, duracion: duracion)
    }

    /// Cada posición nueva: la cámara se desliza (sin saltos) a tu sitio, en tu rumbo,
    /// inclinada y al zoom que pide la velocidad. Lo hacemos nosotros (y no el seguimiento de
    /// MapLibre) para controlar el zoom y que el mapa nunca quede bloqueado.
    func camaraNavegacion(en mapa: MLNMapView, duracion: TimeInterval = 1.0) {
        guard let navegador = padre.navegador, navegador.fase == .navegando, navegador.siguiendo,
              let aqui = navegador.ubicacion?.coordinate ?? mapa.userLocation?.location?.coordinate else { return }
        let zoom = navegador.zoomNavegacion
        // Metros que caben a lo ancho de la pantalla a ese zoom (teselas de 512 px).
        let metrosPorPunto = 78_271.517 * cos(aqui.latitude * .pi / 180) / pow(2, zoom)
        let ancho = max(mapa.bounds.width, 320) * metrosPorPunto
        let camara = MLNMapCamera(lookingAtCenter: aqui, acrossDistance: ancho, pitch: 55, heading: navegador.rumbo)
        moviendoPorApp = true
        mapa.setCamera(camara, withDuration: duracion, animationTimingFunction: CAMediaTimingFunction(name: .linear)) { [weak self] in
            self?.moviendoPorApp = false
        }
    }

    /// Ya no hace falta: el zoom va dentro de la cámara de navegación.
    func ajustarZoom(en mapa: MLNMapView) {}

    /// Mantener pulsado: pin y ficha de ese punto (como Apple Maps).
    @objc func mantener(_ gesto: UILongPressGestureRecognizer) {
        guard gesto.state == .began, let mapa = gesto.view as? MLNMapView, let navegador = padre.navegador,
              navegador.fase != .navegando else { return }
        let coordenada = mapa.convert(gesto.location(in: mapa), toCoordinateFrom: mapa)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        navegador.elegir(en: coordenada)
    }

    /// Tocar una ruta gris la elige.
    func tocarRuta(en punto: CGPoint, mapa: MLNMapView) -> Bool {
        guard let navegador = padre.navegador, navegador.fase == .ruta else { return false }
        let caja = CGRect(x: punto.x - 14, y: punto.y - 14, width: 28, height: 28)
        guard let tocada = mapa.visibleFeatures(in: caja, styleLayerIdentifiers: [ID.altLinea]).first,
              let indice = (tocada.attribute(forKey: "indice") as? NSNumber)?.intValue else { return false }
        navegador.elegirRuta(indice)
        return true
    }
}
