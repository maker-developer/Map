import SwiftUI

/// Hoja inferior del mapa: barra de búsqueda con el botón del laboratorio al lado,
/// la ficha de lo que se toca en el mapa y, debajo, sitios para explorar.
/// La búsqueda de direcciones y lugares llega en la ronda 2 (`equipo/hoja-de-ruta.md`);
/// por ahora busca entre las zonas del condado.
struct HojaBusqueda: View {
    static let alturaMinima: CGFloat = 96
    static let alturaFicha: CGFloat = 250

    @Binding var tocado: ElementoTocado?
    @Binding var hoja: PresentationDetent
    let navegador: Navegador
    let elegirZona: (Zona) -> Void

    @State private var consulta = ""

    private var recogida: Bool { hoja == .height(Self.alturaMinima) }
    @State private var verLaboratorio = false
    /// «Casa» o «Trabajo» sin guardar: se explica cómo añadirlo.
    @State private var pistaAnadir: String?
    @FocusState private var escribiendo: Bool

    var body: some View {
        VStack(spacing: 0) {
            barra
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let tocado {
                        FichaTocado(elemento: tocado) {
                            withAnimation(.snappy) { self.tocado = nil }
                            hoja = .height(Self.alturaMinima)
                        }
                    }
                    if consulta.isEmpty {
                        accesos
                        if !navegador.favoritos.recientes.isEmpty { recientes }
                    }
                    lugares
                    explorar
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            // Recogida, la hoja enseña solo la barra (como Apple Maps).
            .opacity(recogida ? 0 : 1)
            .allowsHitTesting(!recogida)
        }
        .animation(.snappy, value: tocado)
        .animation(.easeOut(duration: 0.2), value: recogida)
        .onChange(of: escribiendo) { _, activo in
            if activo { hoja = .large }
        }
        // Lugares mientras se escribe (espera un poco entre letras para no saturar el servicio).
        .task(id: consulta) {
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            await navegador.buscar(consulta)
        }
        .fullScreenCover(isPresented: $verLaboratorio) {
            ListaExperimentos(alCerrar: { verLaboratorio = false })
        }
    }

    // MARK: - Barra

    private var barra: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Icono(.buscar, tamano: 17)
                    .foregroundStyle(.secondary)
                TextField("Buscar en el mapa", text: $consulta)
                    .focused($escribiendo)
                    .submitLabel(.search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !consulta.isEmpty {
                    Button {
                        consulta = ""
                    } label: {
                        Icono(.cerrar, tamano: 14)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Borrar")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .vidrio(Capsule())

            // Modo laboratorio: los experimentos de cada ronda.
            Button {
                escribiendo = false
                verLaboratorio = true
            } label: {
                Icono(.laboratorio, tamano: 19)
                    .foregroundStyle(Color.primary)
                    .frame(width: 46, height: 46)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .vidrio(Circle(), interactivo: true)
            .accessibilityLabel("Modo laboratorio")
        }
    }

    // MARK: - Explorar

    private var zonas: [Zona] {
        let lista = Zona.allCases
        let texto = consulta.trimmingCharacters(in: .whitespaces)
        guard !texto.isEmpty else { return lista }
        return lista.filter { $0.nombre.localizedStandardContains(texto) }
    }

    // MARK: - Casa, Trabajo, guardados y recientes

    /// «Ir a casa» y «Ir al trabajo» con un toque (directo a la ruta), y los guardados.
    private var accesos: some View {
        let favoritos = navegador.favoritos
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                acceso(icono: .casa, color: .blue, titulo: "Casa", detalle: favoritos.casa.map { _ in "Ir" } ?? "Añadir",
                       lugar: favoritos.casa?.lugar)
                acceso(icono: .trabajo, color: .brown, titulo: "Trabajo", detalle: favoritos.trabajo.map { _ in "Ir" } ?? "Añadir",
                       lugar: favoritos.trabajo?.lugar)
                ForEach(Array(favoritos.guardados.prefix(8).enumerated()), id: \.offset) { _, guardado in
                    acceso(icono: .guardado, color: .orange, titulo: guardado.nombre, detalle: guardado.subtitulo,
                           lugar: guardado.lugar, directo: false)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: pistaAnadir)
        .alert("Añadir \(pistaAnadir?.lowercased() ?? "")", isPresented: Binding(get: { pistaAnadir != nil }, set: { if !$0 { pistaAnadir = nil } })) {
            Button("Entendido", role: .cancel) { pistaAnadir = nil }
        } message: {
            Text("Busca el lugar o mantén pulsado el mapa, y en su ficha toca «Más» › «Guardar como \(pistaAnadir ?? "")».")
        }
    }

    /// Un acceso: con lugar, «Ir» lleva directo a la ruta; sin lugar, explica cómo añadirlo.
    private func acceso(icono: Lc, color: Color, titulo: String, detalle: String, lugar: Lugar?, directo: Bool = true) -> some View {
        Button {
            escribiendo = false
            if let lugar {
                if directo { navegador.irA(lugar) } else { navegador.elegir(lugar) }
            } else {
                pistaAnadir = titulo
            }
        } label: {
            VStack(spacing: 6) {
                Icono(icono, tamano: 20)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(color.gradient, in: Circle())
                Text(titulo)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(detalle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 76)
        }
        .buttonStyle(.plain)
    }

    /// Los últimos sitios elegidos: un toque y sale su ficha otra vez.
    private var recientes: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recientes")
                    .font(.headline)
                Spacer()
                Button("Borrar") { navegador.favoritos.borrarRecientes() }
                    .font(.subheadline)
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                let lista = Array(navegador.favoritos.recientes.prefix(5).enumerated())
                ForEach(lista, id: \.offset) { indice, reciente in
                    Button {
                        escribiendo = false
                        navegador.elegir(reciente.lugar)
                    } label: {
                        HStack(spacing: 12) {
                            IconoCuadro(icono: .recientes, color: .gray)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(reciente.nombre).foregroundStyle(.primary).lineLimit(1)
                                if !reciente.subtitulo.isEmpty {
                                    Text(reciente.subtitulo).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if indice < lista.count - 1 { Divider().padding(.leading, 58) }
                }
            }
            .fondoPieza(radio: 20)
        }
    }

    /// Lugares encontrados: cada uno con su ícono, su dirección y a qué distancia está.
    /// Mientras busca, filas «fantasma»; si no hay nada, un aviso claro.
    @ViewBuilder
    private var lugares: some View {
        let texto = consulta.trimmingCharacters(in: .whitespaces)
        if texto.count >= 2 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Lugares")
                    .font(.headline)
                    .padding(.horizontal, 4)

                if navegador.resultados.isEmpty {
                    if navegador.buscando {
                        VStack(spacing: 0) {
                            ForEach(0..<3, id: \.self) { _ in
                                HStack(spacing: 12) {
                                    Circle().fill(Color.primary.opacity(0.08)).frame(width: 34, height: 34)
                                    VStack(alignment: .leading, spacing: 6) {
                                        RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)).frame(width: 150, height: 12)
                                        RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)).frame(width: 210, height: 10)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                            }
                        }
                        .fondoPieza(radio: 20)
                        .transition(.opacity)
                    } else {
                        VStack(spacing: 8) {
                            Icono(.buscar, tamano: 24).foregroundStyle(.tertiary)
                            Text("Sin resultados para «\(texto)»")
                                .font(.subheadline.weight(.semibold))
                            Text("Prueba con una dirección, un barrio o el nombre del sitio. También puedes mantener pulsado el mapa.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .padding(.horizontal, 12)
                        .fondoPieza(radio: 20)
                        .transition(.opacity)
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(navegador.resultados.enumerated()), id: \.element.id) { indice, lugar in
                            Button {
                                escribiendo = false
                                consulta = ""
                                navegador.limpiarBusqueda()
                                navegador.elegir(lugar)
                            } label: {
                                HStack(spacing: 12) {
                                    Icono(.pin, tamano: 16)
                                        .foregroundStyle(.white)
                                        .frame(width: 34, height: 34)
                                        .background(Color.red.gradient, in: Circle())
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(lugar.nombre)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        if !lugar.subtitulo.isEmpty {
                                            Text(lugar.subtitulo)
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    if let aqui = navegador.ubicacion {
                                        Text(FormatoRuta.distancia(aqui.distance(from: .init(latitude: lugar.coordenada.latitude,
                                                                                            longitude: lugar.coordenada.longitude))))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.presionable)
                            if indice < navegador.resultados.count - 1 {
                                Divider().padding(.leading, 60)
                            }
                        }
                    }
                    .fondoPieza(radio: 20)
                    .transition(.opacity)
                }
            }
            .animation(.snappy, value: navegador.resultados.count)
            .animation(.snappy, value: navegador.buscando)
        }
    }

    /// Zonas como píldoras de vidrio (como las categorías de Apple Maps).
    @ViewBuilder
    private var explorar: some View {
        if !zonas.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(consulta.isEmpty ? "Explorar" : "Zonas")
                    .font(.headline)
                    .padding(.horizontal, 4)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(zonas) { zona in
                            Button {
                                escribiendo = false
                                consulta = ""
                                elegirZona(zona)
                            } label: {
                                HStack(spacing: 7) {
                                    Icono(icono(zona), tamano: 15)
                                        .foregroundStyle(color(zona))
                                    Text(zona.nombre)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 40)
                                .vidrio(Capsule(), interactivo: true)
                            }
                            .buttonStyle(.presionable)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollClipDisabled()
                if consulta.isEmpty {
                    Text("Mantén pulsado el mapa para poner un pin e ir a ese punto.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func icono(_ zona: Zona) -> Lc {
        switch zona {
        case .condado: .mapa
        case .miami, .brickell: .edificio
        case .miamiBeach: .sol
        case .miamiLakes: .pin
        case .bahia: .brujula
        }
    }

    private func color(_ zona: Zona) -> Color {
        switch zona {
        case .condado: .teal
        case .miami: .indigo
        case .brickell: .blue
        case .miamiBeach: .orange
        case .miamiLakes: .green
        case .bahia: .cyan
        }
    }
}
