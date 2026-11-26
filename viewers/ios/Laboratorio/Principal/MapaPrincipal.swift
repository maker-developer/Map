import SwiftUI

/// La app es un mapa normal, como Apple Maps: el mapa a pantalla completa con nuestro estilo,
/// controles de vidrio (2D/3D, capas, ubicación) y una hoja inferior con la búsqueda.
/// El ícono del matraz, junto a la búsqueda, abre el modo laboratorio para probar cosas nuevas.
struct MapaPrincipal: View {
    @Environment(\.colorScheme) private var esquema
    /// «auto» sigue al iPhone; «claro» u «oscuro» lo fijan.
    @AppStorage("apariencia") private var apariencia = "auto"
    @AppStorage("vista3D") private var vista3D = true
    @AppStorage("origenMapas") private var origenMapas = OrigenElegido.app.rawValue
    @AppStorage("urlMac") private var urlMac = ""

    @State private var estilo = EstiloMapa()
    @State private var zona: Zona = .miami
    @State private var repetirVuelo = 0
    @State private var medidas = Medidas()
    @State private var tocado: ElementoTocado?
    @State private var centrarEnMi = 0
    @State private var hoja: PresentationDetent = .height(HojaBusqueda.alturaMinima)
    @State private var listo = false
    /// Búsqueda, ficha del lugar, rutas y navegación (como Apple Maps y Google Maps).
    @State private var navegador = Navegador()
    /// Alto de la ficha del lugar: la hoja se ajusta a su contenido.
    @State private var alturaLugar: CGFloat = 300
    /// Brújula de vidrio (gira con el mapa; se esconde mirando al norte).
    @State private var brujula = Brujula()

    /// Alturas de la hoja según lo que se está haciendo.
    private static let alturaRutaMinima: CGFloat = 300
    private static let alturaNavegacion: CGFloat = 100
    private var alturas: Set<PresentationDetent> {
        switch navegador.fase {
        case .libre: [.height(HojaBusqueda.alturaMinima), .height(HojaBusqueda.alturaFicha), .medium, .large]
        case .lugar: [.height(alturaLugar), .medium]
        case .ruta: [.height(Self.alturaRutaMinima), .medium, .large]
        // Navegando: la barra, y al subirla las opciones (resumen, pasos, compartir llegada…).
        case .navegando: [.height(Self.alturaNavegacion), .medium]
        }
    }

    var body: some View {
        ZStack {
            if listo {
                MapaMapLibre(
                    estilo: estilo,
                    zona: zona,
                    inclinacion: 50,
                    medidas: medidas,
                    tocado: $tocado,
                    centrarEnMi: centrarEnMi,
                    vista3D: vista3D,
                    repetirVuelo: repetirVuelo,
                    // Debajo de la columna de controles (capas, 2D / 3D, ubicación).
                    margenBrujula: CGPoint(x: 23, y: 172),
                    navegador: navegador,
                    brujula: brujula
                )
                .ignoresSafeArea()
            }
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 10) {
                if navegador.fase != .navegando {
                    controles
                        .transition(.opacity)
                }
                if brujula.visible {
                    BotonBrujula(brujula: brujula)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .padding(.trailing, 16)
            // Navegando, la brújula queda debajo del banner.
            .padding(.top, navegador.fase == .navegando ? 190 : 8)
            .animation(.snappy, value: brujula.visible)
        }
        // Navegando: el banner de la maniobra arriba (como Apple y Google).
        .overlay(alignment: .top) {
            if navegador.fase == .navegando {
                BannerManiobra(navegador: navegador)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // Navegando: la velocidad actual (como Google Maps)…
        .overlay(alignment: .bottomLeading) {
            if navegador.fase == .navegando, navegador.siguiendo, !navegador.llegaste {
                BurbujaVelocidad(metrosPorSegundo: navegador.velocidad)
                    .padding(.leading, 16)
                    .padding(.bottom, 128)
                    .transition(.opacity)
            }
        }
        // …y con el mapa movido a mano, «Volver a centrar», como Apple y Google.
        .overlay(alignment: .bottomLeading) {
            if navegador.fase == .navegando, !navegador.siguiendo {
                Button {
                    navegador.recentrar()
                } label: {
                    HStack(spacing: 8) {
                        Icono(.navegar, tamano: 17)
                        Text("Volver a centrar")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Color.blue)
                    .padding(.horizontal, 16)
                    .frame(height: 46)
                    .vidrio(Capsule(), interactivo: true)
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
                .padding(.bottom, 128)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: navegador.fase)
        .animation(.snappy, value: navegador.siguiendo)
        .sensoryFeedback(.selection, trigger: navegador.elegida)
        .sensoryFeedback(.selection, trigger: navegador.modo)
        .overlay(alignment: .top) {
            if let error = medidas.error {
                Text(error)
                    .font(.footnote)
                    .padding(12)
                    .vidrio(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 70)
                    .padding(.top, 8)
            }
        }
        // La hoja de búsqueda siempre está, como en Apple Maps; se recoge pero no se cierra.
        .sheet(isPresented: .constant(listo)) {
            Group {
                switch navegador.fase {
                case .libre:
                    HojaBusqueda(
                        tocado: $tocado,
                        hoja: $hoja,
                        navegador: navegador,
                        elegirZona: { nueva in
                            if nueva == zona { repetirVuelo += 1 } else { zona = nueva }
                            hoja = .height(HojaBusqueda.alturaMinima)
                        }
                    )
                case .lugar:
                    HojaLugar(navegador: navegador, altura: $alturaLugar)
                case .ruta:
                    HojaRuta(navegador: navegador)
                case .navegando:
                    HojaNavegacion(navegador: navegador)
                }
            }
            // Cambio suave entre búsqueda, ficha, ruta y navegación.
            .transition(.blurReplace)
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: navegador.fase)
            .presentationDetents(alturas, selection: $hoja)
            .presentationDragIndicator(.visible)
            // El mapa siempre se puede tocar al navegar (antes quedaba bloqueado detrás de la barra).
            .presentationBackgroundInteraction(navegador.fase == .navegando ? .enabled : .enabled(upThrough: .medium))
            .interactiveDismissDisabled()
        }
        .onAppear(perform: preparar)
        .onChange(of: vista3D) { _, nuevo in estilo.edificios3D = nuevo }
        // La hoja se pone a la altura que toca en cada paso (ficha, ruta, navegación).
        .onChange(of: navegador.fase) { _, fase in
            switch fase {
            case .libre: hoja = .height(HojaBusqueda.alturaMinima)
            case .lugar: hoja = .height(alturaLugar)
            case .ruta: hoja = .medium
            case .navegando: hoja = .height(Self.alturaNavegacion)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: navegador.fase)
        // La ficha cambia de alto (p. ej. al llegar la dirección): la hoja la acompaña.
        .onChange(of: alturaLugar) { _, nueva in
            if navegador.fase == .lugar { withAnimation(.snappy) { hoja = .height(nueva) } }
        }
        .onChange(of: esquema) { aplicarApariencia() }
        .onChange(of: apariencia) { aplicarApariencia() }
        .onChange(of: tocado) { _, nuevo in
            // Al tocar algo en el mapa, la hoja sube un poco para enseñar su ficha.
            if nuevo != nil, hoja == .height(HojaBusqueda.alturaMinima) { hoja = .height(HojaBusqueda.alturaFicha) }
        }
        .sensoryFeedback(.selection, trigger: vista3D)
    }

    private func preparar() {
        guard !listo else { return }
        estilo.ronda1 = true
        // En 2D los edificios se ven planos desde arriba (con sus colores); en 3D, con volumen.
        estilo.edificios3D = vista3D
        estilo.edificiosTapan = true
        estilo.origen = (OrigenElegido(rawValue: origenMapas) ?? .app).origen(urlMac: urlMac)
        aplicarApariencia()
        listo = true
    }

    private func aplicarApariencia() {
        switch apariencia {
        case "claro": estilo.tema = .claro
        case "oscuro": estilo.tema = .oscuro
        default: estilo.tema = esquema == .dark ? .oscuro : .claro
        }
    }

    // MARK: - Controles (arriba a la derecha, como Apple Maps)

    private var controles: some View {
        VStack(spacing: 0) {
            Menu {
                Picker("Apariencia", selection: $apariencia) {
                    Text("Automática").tag("auto")
                    Text("Clara").tag("claro")
                    Text("Oscura").tag("oscuro")
                }
                Section {
                    Toggle("Rutas y paradas", isOn: $estilo.transporte)
                }
            } label: {
                Icono(.capas, tamano: 19)
                    .foregroundStyle(Color.primary)
                    .frame(width: 48, height: 46)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Capas del mapa")

            Divider().frame(width: 28)

            Button {
                withAnimation(.snappy) { vista3D.toggle() }
            } label: {
                Text(vista3D ? "2D" : "3D")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 48, height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(vista3D ? "Ver en 2D" : "Ver en 3D")

            Divider().frame(width: 28)

            Button {
                centrarEnMi += 1
            } label: {
                Icono(.ubicacion, tamano: 19)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 48, height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mi ubicación")
        }
        .vidrio(RoundedRectangle(cornerRadius: 24, style: .continuous), interactivo: true)
    }
}

/// Velocidad actual en mph o km/h según la región del iPhone.
private struct BurbujaVelocidad: View {
    let metrosPorSegundo: Double

    var body: some View {
        let millas = Locale.current.measurementSystem == .us
        let valor = metrosPorSegundo * (millas ? 2.23694 : 3.6)
        VStack(spacing: -2) {
            Text("\(Int(valor.rounded()))")
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(millas ? "mph" : "km/h")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 62, height: 62)
        .vidrio(Circle())
        .animation(.snappy, value: Int(valor.rounded()))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Velocidad \(Int(valor.rounded())) \(millas ? "millas por hora" : "kilómetros por hora")")
    }
}
