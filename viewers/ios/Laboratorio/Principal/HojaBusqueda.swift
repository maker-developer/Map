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
    let elegirZona: (Zona) -> Void

    @State private var consulta = ""
    @State private var verLaboratorio = false
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
                    explorar
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .animation(.snappy, value: tocado)
        .onChange(of: escribiendo) { _, activo in
            if activo { hoja = .large }
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

    private var explorar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(consulta.isEmpty ? "Explorar" : "Resultados")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(zonas.enumerated()), id: \.element) { indice, zona in
                    Button {
                        escribiendo = false
                        consulta = ""
                        elegirZona(zona)
                    } label: {
                        HStack(spacing: 12) {
                            IconoCuadro(icono: icono(zona), color: color(zona))
                            Text(zona.nombre)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            Icono(.flecha, tamano: 13)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if indice < zonas.count - 1 {
                        Divider().padding(.leading, 58)
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            if zonas.isEmpty {
                Text("Sin resultados. La búsqueda de direcciones y lugares llega pronto.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            } else {
                Text("Pronto: direcciones, calles, barrios y lugares públicos del condado.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
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
