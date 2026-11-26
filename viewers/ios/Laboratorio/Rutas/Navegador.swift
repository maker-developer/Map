import Foundation
import CoreLocation
import AVFoundation
import Observation

/// Lo que pasa entre buscar un sitio y llegar, como en Apple Maps y Google Maps:
///
/// 1. **libre:** el mapa y la búsqueda.
/// 2. **lugar:** pin en el mapa y su ficha con «Cómo llegar» (ya dice cuánto tardas en coche).
/// 3. **ruta:** origen y destino, pestañas de modo con su tiempo, rutas alternativas en el mapa
///    (la elegida en azul, las demás en gris) y tarjetas con duración, llegada, distancia y «por…».
/// 4. **navegando:** banner con la maniobra, barra con llegada / minutos / distancia, cámara que te
///    sigue, voz, avance paso a paso y recálculo si te sales.
@MainActor
@Observable
final class Navegador {
    enum Fase: Equatable { case libre, lugar, ruta, navegando }

    private(set) var fase: Fase = .libre
    private(set) var destino: Lugar?
    /// nil = «Mi ubicación».
    private(set) var origen: Lugar?
    private(set) var modo: ModoRuta = .coche
    private(set) var rutas: [Ruta] = []
    private(set) var elegida = 0
    /// Minutos de la mejor ruta en cada modo (para las pestañas y el botón «Cómo llegar»).
    private(set) var duracionPorModo: [ModoRuta: TimeInterval] = [:]
    private(set) var cargando = false
    private(set) var error: String?
    private(set) var resultados: [Lugar] = []
    private(set) var buscando = false

    // Navegación
    private(set) var pasoActual = 0
    private(set) var distanciaAlPaso: CLLocationDistance?
    private(set) var restante: (distancia: CLLocationDistance, duracion: TimeInterval)?
    private(set) var llegaste = false
    /// Hora a la que llegaste (para la pantalla de llegada).
    private(set) var horaLlegada: Date?
    var voz = true
    /// La cámara te sigue. Si mueves el mapa con el dedo deja de seguirte y aparece «Volver a centrar».
    private(set) var siguiendo = true
    /// Zoom que pide la navegación según la velocidad y la cercanía al giro.
    private(set) var zoomNavegacion: Double = 17
    /// Sube al pedir «Volver a centrar».
    private(set) var versionCentrar = 0
    /// Rumbo de marcha (último válido) y velocidad, para la cámara y la burbuja de velocidad.
    private(set) var rumbo: CLLocationDirection = 0
    private(set) var velocidad: CLLocationSpeed = 0

    /// Casa, Trabajo, guardados y recientes.
    let favoritos = Favoritos()

    /// Suben para que el mapa redibuje las rutas o encuadre (el mapa compara con lo último que vio).
    private(set) var versionRutas = 0
    private(set) var versionEncuadre = 0

    private(set) var ubicacion: CLLocation?
    private var rutasPorModo: [ModoRuta: [Ruta]] = [:]
    private var fueraDeRuta = 0
    private var anunciado: Set<Int> = []
    /// Último cálculo de progreso: como mucho uno por segundo, para que no se trabe.
    private var ultimoProgreso = Date.distantPast
    /// Vértice del trazado más cercano la última vez: se busca solo alrededor de él.
    private var indiceTrazado = 0
    /// Hasta qué vértice del trazado ya recorriste (lo de atrás se pinta gris claro).
    private(set) var indiceRecorrido = 0
    private let hablador = AVSpeechSynthesizer()

    var rutaElegida: Ruta? { rutas.indices.contains(elegida) ? rutas[elegida] : nil }
    var pasoSiguiente: Paso? {
        guard let ruta = rutaElegida else { return nil }
        let i = pasoActual + 1
        return ruta.pasos.indices.contains(i) ? ruta.pasos[i] : nil
    }

    // MARK: - Búsqueda

    func buscar(_ texto: String) async {
        let limpio = texto.trimmingCharacters(in: .whitespaces)
        guard limpio.count >= 2 else { resultados = []; return }
        buscando = true
        defer { buscando = false }
        let encontrados = (try? await ServiciosRuta.buscar(limpio, cerca: ubicacion?.coordinate)) ?? []
        guard !Task.isCancelled else { return }
        resultados = encontrados
    }

    func limpiarBusqueda() { resultados = [] }

    // MARK: - Lugar

    func elegir(_ lugar: Lugar) {
        favoritos.registrar(lugar)
        destino = lugar
        origen = nil
        rutas = []
        rutasPorModo = [:]
        duracionPorModo = [:]
        error = nil
        fase = .lugar
        versionRutas += 1
        Task { await calcularTodos() }
    }

    /// Mantener pulsado el mapa: pin y su ficha.
    func elegir(en coordenada: CLLocationCoordinate2D) {
        elegir(Lugar(nombre: "Punto en el mapa", subtitulo: "Buscando dirección…", coordenada: coordenada))
        Task {
            let lugar = await ServiciosRuta.lugar(en: coordenada)
            guard destino?.coordenada.latitude == coordenada.latitude,
                  destino?.coordenada.longitude == coordenada.longitude else { return }
            destino?.nombre = lugar.nombre
            destino?.subtitulo = lugar.subtitulo
            // Recientes con el nombre real (sustituye al «Punto en el mapa» provisional).
            if let destino { favoritos.registrar(destino) }
        }
    }

    // MARK: - Ruta

    func comoLlegar() {
        fase = .ruta
        mostrarModo(modo)
        versionEncuadre += 1
        if rutasPorModo.isEmpty { Task { await calcularTodos() } }
    }

    func cambiarModo(_ nuevo: ModoRuta) {
        modo = nuevo
        mostrarModo(nuevo)
        versionEncuadre += 1
    }

    func elegirRuta(_ indice: Int) {
        guard rutas.indices.contains(indice), indice != elegida else { return }
        elegida = indice
        versionRutas += 1
    }

    /// Invierte origen y destino (como el botón ⇅ de Apple y Google).
    func invertir() {
        guard let destinoAnterior = destino else { return }
        // El origen anterior (o «Mi ubicación») pasa a ser el destino, y el destino, el origen.
        let origenAnterior: Lugar
        if let origen {
            origenAnterior = origen
        } else if let aqui = ubicacion?.coordinate {
            origenAnterior = Lugar.miUbicacion(aqui)
        } else {
            return
        }
        origen = destinoAnterior.esMiUbicacion ? nil : destinoAnterior
        destino = origenAnterior
        rutasPorModo = [:]
        duracionPorModo = [:]
        Task { await calcularTodos() }
    }

    /// Texto del campo «Desde».
    var nombreOrigen: String { origen?.nombre ?? "Mi ubicación" }

    /// Calcula a la vez coche, a pie y bici (para las pestañas con su tiempo).
    func calcularTodos() async {
        guard let destino else { return }
        guard let desde = origen?.coordenada ?? ubicacion?.coordinate else {
            error = "Activa tu ubicación para calcular la ruta."
            return
        }
        cargando = true
        error = nil
        defer { cargando = false }
        await withTaskGroup(of: (ModoRuta, Result<[Ruta], Error>).self) { grupo in
            for m in ModoRuta.allCases {
                grupo.addTask {
                    do {
                        return (m, .success(try await ServiciosRuta.rutas(desde: desde, hasta: destino.coordenada, modo: m)))
                    } catch {
                        return (m, .failure(error))
                    }
                }
            }
            for await (m, resultado) in grupo {
                switch resultado {
                case .success(let lista):
                    rutasPorModo[m] = lista
                    duracionPorModo[m] = lista.first?.duracion
                case .failure(let fallo):
                    if m == modo { error = fallo.localizedDescription }
                }
            }
        }
        // Si el destino cambió mientras se calculaba, no se pisa.
        guard self.destino == destino else { return }
        if fase == .ruta || fase == .navegando { mostrarModo(modo) }
        if fase == .ruta { versionEncuadre += 1 }
    }

    private func mostrarModo(_ m: ModoRuta) {
        rutas = rutasPorModo[m] ?? []
        elegida = 0
        if rutas.isEmpty, rutasPorModo[m] != nil { error = ServiciosRuta.Fallo.sinRuta.localizedDescription }
        versionRutas += 1
    }

    // MARK: - Navegación

    func iniciar() {
        guard rutaElegida != nil else { return }
        fase = .navegando
        pasoActual = 0
        llegaste = false
        horaLlegada = nil
        anunciado = []
        fueraDeRuta = 0
        indiceTrazado = 0
        indiceRecorrido = 0
        siguiendo = true
        ultimoProgreso = .distantPast
        actualizarProgreso()
        if let paso = rutaElegida?.pasos.first { decir(paso.instruccion) }
    }

    func finalizar() {
        hablador.stopSpeaking(at: .immediate)
        if llegaste {
            cerrar()
        } else {
            fase = .ruta
            versionEncuadre += 1
        }
    }

    /// «Resumen»: ver la ruta entera (deja de seguir; «Volver a centrar» vuelve).
    func resumen() {
        siguiendo = false
        versionEncuadre += 1
    }

    /// Rumbo aproximado entre dos puntos (para orientar la cámara antes de moverse).
    static func rumbo(de a: CLLocationCoordinate2D, a b: CLLocationCoordinate2D) -> CLLocationDirection {
        let la1 = a.latitude * .pi / 180, la2 = b.latitude * .pi / 180
        let dl = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dl) * cos(la2)
        let x = cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dl)
        let grados = atan2(y, x) * 180 / .pi
        return grados < 0 ? grados + 360 : grados
    }

    /// El usuario movió el mapa con el dedo: se deja de seguir.
    func dejarDeSeguir() {
        guard fase == .navegando, siguiendo else { return }
        siguiendo = false
    }

    /// «Volver a centrar»: la cámara vuelve a seguirte.
    func recentrar() {
        siguiendo = true
        versionCentrar += 1
    }

    /// «Ir a casa» / «Ir al trabajo» con un toque: directo a la pantalla de ruta.
    func irA(_ lugar: Lugar) {
        elegir(lugar)
        comoLlegar()
    }

    /// Cierra todo y vuelve al mapa libre.
    func cerrar() {
        hablador.stopSpeaking(at: .immediate)
        fase = .libre
        destino = nil
        origen = nil
        rutas = []
        rutasPorModo = [:]
        duracionPorModo = [:]
        error = nil
        versionRutas += 1
    }

    /// Cada posición nueva del usuario (desde el mapa).
    func actualizar(ubicacion nueva: CLLocation?) {
        guard let nueva, nueva.horizontalAccuracy >= 0 else { return }
        ubicacion = nueva
        velocidad = max(0, nueva.speed)
        // El rumbo solo vale si te mueves; parado se mantiene el último (si no, la cámara gira sola).
        if nueva.course >= 0, nueva.speed > 1 {
            rumbo = nueva.course
        } else if rumbo == 0, let siguiente = pasoSiguiente {
            rumbo = Self.rumbo(de: nueva.coordinate, a: siguiente.ubicacion)
        }
        // Como mucho un cálculo por segundo: suficiente para la voz y el banner, y no se traba.
        guard fase == .navegando, Date().timeIntervalSince(ultimoProgreso) >= 1 else { return }
        actualizarProgreso()
    }

    private func actualizarProgreso() {
        guard let ruta = rutaElegida, let aqui = ubicacion else { return }
        ultimoProgreso = Date()

        // ¿Llegaste a la siguiente maniobra? Se pasa a la que sigue.
        while let siguiente = pasoSiguiente,
              aqui.distance(from: CLLocation(latitude: siguiente.ubicacion.latitude, longitude: siguiente.ubicacion.longitude))
                < modo.radioManiobra {
            pasoActual += 1
            if pasoActual >= ruta.pasos.count - 1 { break }
        }

        let siguiente = pasoSiguiente
        let distancia = siguiente.map {
            aqui.distance(from: CLLocation(latitude: $0.ubicacion.latitude, longitude: $0.ubicacion.longitude))
        }
        distanciaAlPaso = distancia

        // Lo que falta: la distancia a la maniobra más los pasos que quedan después.
        let despues = ruta.pasos.dropFirst(pasoActual + 1).reduce(0) { $0 + $1.distancia }
        let falta = (distancia ?? 0) + despues
        restante = (falta, ruta.distancia > 0 ? ruta.duracion * falta / ruta.distancia : 0)

        // Zoom según la velocidad: más lejos en autopista, más cerca al llegar a un giro.
        zoomNavegacion = Self.zoom(velocidad: aqui.speed, distanciaAlGiro: distancia, modo: modo)

        // Llegada automática: la última maniobra cerca, o ya junto al destino (aunque no pases
        // justo por el punto final, p. ej. si aparcas al lado).
        let alDestino = destino.map {
            aqui.distance(from: CLLocation(latitude: $0.coordenada.latitude, longitude: $0.coordenada.longitude))
        } ?? .infinity
        if siguiente == nil
            || (siguiente?.icono == .bandera && (distancia ?? .infinity) < modo.radioManiobra * 1.5)
            || alDestino < max(modo.radioManiobra * 1.5, 30) {
            if !llegaste {
                llegaste = true
                horaLlegada = Date()
                restante = (0, 0)
                decir("Has llegado a \(destino?.nombre ?? "tu destino")")
                // Si no tocas nada, la ruta se cierra sola al minuto (como Apple Maps).
                Task {
                    try? await Task.sleep(for: .seconds(60))
                    if llegaste, fase == .navegando { cerrar() }
                }
            }
            return
        }

        // Avisos de voz: al acercarse a la maniobra y justo antes.
        if let siguiente, let distancia {
            let aviso = modo == .coche ? 300.0 : 80.0
            if distancia < aviso, !anunciado.contains(siguiente.id) {
                anunciado.insert(siguiente.id)
                decir("En \(FormatoRuta.distancia(distancia)), \(siguiente.instruccion.prefix(1).lowercased() + siguiente.instruccion.dropFirst())")
            }
        }

        // ¿Te saliste de la ruta? Tres lecturas seguidas a más de 60 m → se recalcula desde aquí.
        let lejos = distanciaCercana(de: aqui, a: ruta.coordenadas) > (modo == .pie ? 40 : 60)
        fueraDeRuta = lejos ? fueraDeRuta + 1 : 0
        if fueraDeRuta >= 3 {
            fueraDeRuta = 0
            decir("Recalculando")
            origen = nil
            Task {
                await calcularTodos()
                pasoActual = 0
                indiceTrazado = 0
                indiceRecorrido = 0
                anunciado = []
            }
        }
    }

    /// Distancia al trazado mirando solo el tramo cercano (unos vértices atrás y más adelante),
    /// no la ruta entera: en rutas largas son miles de puntos y se trabaría.
    private func distanciaCercana(de punto: CLLocation, a coordenadas: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard !coordenadas.isEmpty else { return .infinity }
        let desde = max(0, indiceTrazado - 15)
        let hasta = min(coordenadas.count - 1, indiceTrazado + 160)
        var minima = CLLocationDistance.infinity
        var mejor = indiceTrazado
        for i in desde...hasta {
            let c = coordenadas[i]
            let d = punto.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            if d < minima { minima = d; mejor = i }
        }
        indiceTrazado = mejor
        // Lo recorrido solo avanza (y se redibuja cada pocos vértices para no cargar el mapa).
        if mejor > indiceRecorrido + 2 {
            indiceRecorrido = mejor
            versionRutas += 1
        }
        return minima
    }

    /// Zoom de la cámara al navegar.
    static func zoom(velocidad: CLLocationSpeed, distanciaAlGiro: CLLocationDistance?, modo: ModoRuta) -> Double {
        if modo == .pie { return 17.6 }
        let v = max(0, velocidad) // m/s (negativa = desconocida)
        var z: Double
        switch v {
        case ..<6: z = 17.4      // < 22 km/h: ciudad lenta
        case ..<14: z = 16.6     // < 50 km/h
        case ..<24: z = 15.8     // < 86 km/h
        default: z = 15.0        // autopista
        }
        if let d = distanciaAlGiro, d < 250 { z = max(z, 17.2) } // acercar antes del giro
        return z
    }

    private func decir(_ texto: String) {
        guard voz else { return }
        let frase = AVSpeechUtterance(string: texto)
        frase.voice = AVSpeechSynthesisVoice(language: "es-US") ?? AVSpeechSynthesisVoice(language: "es-ES")
        frase.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
        hablador.speak(frase)
    }
}
