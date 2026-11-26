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

    /// Alturas de la hoja según lo que se está haciendo.
    private static let alturaLugar: CGFloat = 270
    private static let alturaNavegacion: CGFloat = 120
    private var alturas: Set<PresentationDetent> {
        switch navegador.fase {
        case .libre: [.height(HojaBusqueda.alturaMinima), .height(HojaBusqueda.alturaFicha), .medium, .large]
        case .lugar: [.height(Self.alturaLugar), .medium]
        case .ruta: [.height(Self.alturaLugar), .medium, .large]
        case .navegando: [.height(Self.alturaNavegacion)]
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
                    navegador: navegador
                )
                .ignoresSafeArea()
            }
        }
        .overlay(alignment: .topTrailing) {
            if navegador.fase != .navegando {
                controles
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        // Navegando: el banner de la maniobra arriba (como Apple y Google).
        .overlay(alignment: .top) {
            if navegador.fase == .navegando {
                BannerManiobra(navegador: navegador)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: navegador.fase)
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
                    HojaLugar(navegador: navegador)
                case .ruta:
                    HojaRuta(navegador: navegador)
                case .navegando:
                    HojaNavegacion(navegador: navegador)
                }
            }
            .presentationDetents(alturas, selection: $hoja)
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .interactiveDismissDisabled()
        }
        .onAppear(perform: preparar)
        .onChange(of: vista3D) { _, nuevo in estilo.edificios3D = nuevo }
        // La hoja se pone a la altura que toca en cada paso (ficha, ruta, navegación).
        .onChange(of: navegador.fase) { _, fase in
            switch fase {
            case .libre: hoja = .height(HojaBusqueda.alturaMinima)
            case .lugar: hoja = .height(Self.alturaLugar)
            case .ruta: hoja = .medium
            case .navegando: hoja = .height(Self.alturaNavegacion)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: navegador.fase)
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
