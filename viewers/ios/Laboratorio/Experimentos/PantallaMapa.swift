import SwiftUI

/// Un experimento: el mapa a pantalla completa con sus controles de vidrio a la derecha,
/// las medidas arriba y la ficha de lo que se toca abajo.
struct PantallaMapa: View {
    let experimento: Experimento

    @AppStorage("urlMac") private var urlMac = ""
    @AppStorage("origenMapas") private var origenMapas = OrigenElegido.app.rawValue
    @State private var estilo = EstiloMapa()
    @State private var zona: Zona = .condado
    @State private var inclinacion: Double = 54
    @State private var medidas = Medidas()
    @State private var verMedidas = false
    @State private var tocado: ElementoTocado?
    @State private var centrarEnMi = 0
    @State private var listo = false

    var body: some View {
        ZStack {
            if listo {
                MapaMapLibre(
                    estilo: estilo,
                    zona: zona,
                    inclinacion: inclinacion,
                    medidas: medidas,
                    tocado: $tocado,
                    centrarEnMi: centrarEnMi
                )
                .ignoresSafeArea()
            }
        }
        .overlay(alignment: .top) {
            if experimento.comparar {
                Picker("Estilo", selection: $estilo.ronda1) {
                    Text("Antes").tag(false)
                    Text("Después").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .padding(4)
                .vidrio(Capsule())
                .padding(.top, 8)
            }
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 8) {
                if verMedidas { PanelMedidas(medidas: medidas, origen: estilo.origen.nombre) }
                if let error = medidas.error { AvisoError(texto: error) }
            }
            .padding(.leading, 16)
            .padding(.top, experimento.comparar ? 60 : 8)
        }
        .overlay(alignment: .trailing) {
            controles
                .padding(.trailing, 16)
        }
        .overlay(alignment: .bottom) {
            if let tocado {
                FichaTocado(elemento: tocado) { withAnimation(.snappy) { self.tocado = nil } }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: tocado)
        .animation(.snappy, value: verMedidas)
        .navigationTitle(experimento.titulo)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Text(experimento.mirar)
                } label: {
                    Icono(.info, tamano: 18)
                }
                .accessibilityLabel("Qué mirar")
            }
        }
        .onAppear(perform: preparar)
        .sensoryFeedback(.selection, trigger: zona)
    }

    private func preparar() {
        guard !listo else { return }
        estilo.tema = experimento.tema
        estilo.edificios3D = experimento.edificios3D
        estilo.edificiosTapan = experimento.edificiosTapan
        estilo.transporte = experimento.transporte
        estilo.ronda1 = experimento.ronda1
        estilo.origen = (OrigenElegido(rawValue: origenMapas) ?? .app).origen(urlMac: urlMac)
        zona = experimento.zona
        verMedidas = experimento.medidas
        medidas.reiniciar()
        listo = true
    }

    // MARK: - Controles

    private var controles: some View {
        VStack(spacing: 10) {
            Menu {
                Picker("Zona", selection: $zona) {
                    ForEach(Zona.allCases) { Text($0.nombre).tag($0) }
                }
            } label: {
                circulo(.pin)
            }
            .accessibilityLabel("Zona")

            Menu {
                Toggle("Edificios en 3D", isOn: $estilo.edificios3D)
                Toggle("Los edificios tapan", isOn: $estilo.edificiosTapan)
                Toggle("Rutas y paradas", isOn: $estilo.transporte)
                Toggle("Estilo de la ronda 1", isOn: $estilo.ronda1)
                Picker("Inclinación", selection: $inclinacion) {
                    Text("Suave · 40°").tag(40.0)
                    Text("Media · 47°").tag(47.0)
                    Text("Como la web · 54°").tag(54.0)
                }
            } label: {
                circulo(.capas)
            }
            .accessibilityLabel("Capas")

            BotonMapa(
                icono: estilo.tema == .claro ? .luna : .sol,
                etiqueta: estilo.tema == .claro ? "Modo oscuro" : "Modo claro"
            ) {
                estilo.tema = estilo.tema == .claro ? .oscuro : .claro
            }

            BotonMapa(icono: .medidor, etiqueta: "Medidas", activo: verMedidas) {
                verMedidas.toggle()
            }

            BotonMapa(icono: .ubicacion, etiqueta: "Mi ubicación") {
                centrarEnMi += 1
            }
        }
    }

    private func circulo(_ icono: Lc) -> some View {
        Icono(icono, tamano: 19)
            .foregroundStyle(Color.primary)
            .frame(width: 46, height: 46)
            .contentShape(Circle())
            .vidrio(Circle(), interactivo: true)
    }
}

// MARK: - Piezas

/// Medidas del mapa en vivo: primer dibujo, cuadros por segundo y memoria.
private struct PanelMedidas: View {
    let medidas: Medidas
    let origen: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            fila(.capas, "Mapas", origen)
            fila(.reloj, "Primer dibujo", medidas.primerDibujo.map { String(format: "%.1f s", $0) } ?? "midiendo…")
            fila(.medidor, "Cuadros/s", medidas.cuadrosPorSegundo.map { "\($0)" } ?? "en reposo")
            fila(.memoria, "Memoria", medidas.memoriaMB > 0 ? "\(medidas.memoriaMB) MB" : "—")
        }
        .font(.footnote.monospacedDigit())
        .padding(12)
        .vidrio(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func fila(_ icono: Lc, _ titulo: String, _ valor: String) -> some View {
        HStack(spacing: 8) {
            Icono(icono, tamano: 14)
                .foregroundStyle(.secondary)
            Text(titulo)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(valor)
                .fontWeight(.semibold)
        }
        .frame(width: 200)
    }
}

/// Lo que se tocó en el mapa: edificio (dirección y altura) o parada (nombre y rutas).
private struct FichaTocado: View {
    let elemento: ElementoTocado
    let cerrar: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconoCuadro(icono: elemento.tipo == .parada ? .bus : .edificio,
                        color: elemento.tipo == .parada ? .orange : .indigo)
            VStack(alignment: .leading, spacing: 3) {
                Text(elemento.titulo)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(elemento.detalle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: cerrar) {
                Icono(.cerrar, tamano: 16)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cerrar")
        }
        .padding(16)
        .vidrio(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct AvisoError: View {
    let texto: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Icono(.alerta, tamano: 15)
                .foregroundStyle(.orange)
            Text(texto)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: 280, alignment: .leading)
        .vidrio(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
