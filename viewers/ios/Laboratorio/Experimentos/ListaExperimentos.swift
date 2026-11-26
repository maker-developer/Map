import SwiftUI

/// Un experimento: el mismo mapa con una configuración de partida y lo que hay que mirar.
struct Experimento: Identifiable, Hashable {
    let id: String
    let titulo: String
    let detalle: String
    /// Qué comprobar en el teléfono.
    let mirar: String
    let icono: Lc
    let color: Color
    let zona: Zona
    let tema: EstiloMapa.Tema
    let edificios3D: Bool
    let edificiosTapan: Bool
    let transporte: Bool
    let medidas: Bool

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static let todos: [Experimento] = [
        Experimento(
            id: "base", titulo: "Mapa base", detalle: "Calles, agua, parques y nombres de todo el condado.",
            mirar: "Que cargue rápido, que los nombres se lean y que acercar y alejar vaya fluido.",
            icono: .mapa, color: .teal, zona: .condado, tema: .claro,
            edificios3D: true, edificiosTapan: true, transporte: false, medidas: false
        ),
        Experimento(
            id: "edificios", titulo: "Edificios en 3D", detalle: "Brickell con 7.819 edificios con altura.",
            mirar: "Compara «Los edificios tapan» encendido y apagado: ¿se sabe de qué lado de la torre está cada calle?",
            icono: .edificio, color: .indigo, zona: .brickell, tema: .claro,
            edificios3D: true, edificiosTapan: true, transporte: false, medidas: true
        ),
        Experimento(
            id: "transporte", titulo: "Rutas y paradas", detalle: "El transporte como capa encima del mapa base.",
            mirar: "Toca paradas: ¿se distinguen las del Metrorail y Metromover de las de bus?",
            icono: .bus, color: .orange, zona: .brickell, tema: .claro,
            edificios3D: true, edificiosTapan: true, transporte: true, medidas: false
        ),
        Experimento(
            id: "oscuro", titulo: "Modo oscuro", detalle: "La paleta oscura en Miami Beach.",
            mirar: "Contraste del agua, los parques y los nombres de calles de noche.",
            icono: .luna, color: .purple, zona: .miamiBeach, tema: .oscuro,
            edificios3D: true, edificiosTapan: true, transporte: false, medidas: false
        ),
        Experimento(
            id: "rendimiento", titulo: "Rendimiento", detalle: "Miami Lakes: 26.540 edificios en pantalla.",
            mirar: "Cuadros por segundo al girar e inclinar, memoria y tiempo hasta el primer dibujo.",
            icono: .medidor, color: .green, zona: .miamiLakes, tema: .claro,
            edificios3D: true, edificiosTapan: true, transporte: false, medidas: true
        ),
    ]
}

/// Qué origen eligió el usuario en Ajustes (se guarda como texto).
enum OrigenElegido: String, CaseIterable, Identifiable {
    case app, nube, mac
    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .app: "Dentro del app"
        case .nube: "En la nube"
        case .mac: "Desde la Mac"
        }
    }

    /// El origen real, o «dentro del app» si falta la URL de la nube o de la Mac.
    func origen(urlMac: String) -> OrigenDatos {
        switch self {
        case .app:
            return .app
        case .nube:
            return OrigenDatos.urlNube.map(OrigenDatos.nube) ?? .app
        case .mac:
            guard let url = URL(string: urlMac.trimmingCharacters(in: .whitespaces)),
                  url.scheme?.hasPrefix("http") == true else { return .app }
            return .mac(url)
        }
    }
}

/// Inicio: la lista de experimentos, como Ajustes.
struct ListaExperimentos: View {
    @AppStorage("origenMapas") private var origen = OrigenElegido.app.rawValue

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Experimento.todos) { experimento in
                        NavigationLink(value: experimento) {
                            Fila(experimento: experimento)
                        }
                    }
                } header: {
                    Text("Experimentos")
                } footer: {
                    Text("Los mapas salen del propio app: funcionan sin internet. Datos públicos de Miami-Dade y U.S. Census.")
                }

                Section {
                    NavigationLink {
                        AjustesLaboratorio()
                    } label: {
                        LabeledContent {
                            Text(OrigenElegido(rawValue: origen)?.nombre ?? "")
                        } label: {
                            Label {
                                Text("Origen de los mapas")
                            } icon: {
                                IconoCuadro(icono: .capas, color: .gray)
                            }
                        }
                    }
                } footer: {
                    Text("Dentro del app funciona sin internet. En la nube baja solo la parte de cada zona. Desde la Mac sirve para probar teselas nuevas sin compilar.")
                }
            }
            .navigationTitle("Map Lab")
            .navigationDestination(for: Experimento.self) { experimento in
                PantallaMapa(experimento: experimento)
            }
        }
    }
}

private struct Fila: View {
    let experimento: Experimento

    var body: some View {
        HStack(spacing: 14) {
            IconoCuadro(icono: experimento.icono, color: experimento.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(experimento.titulo)
                    .font(.body.weight(.semibold))
                Text(experimento.detalle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Cuadro de color con un ícono blanco, como en Ajustes.
struct IconoCuadro: View {
    let icono: Lc
    let color: Color

    var body: some View {
        Icono(icono, tamano: 17)
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// De dónde salen los mapas: dentro del app, la nube (R2) o la Mac por Wi-Fi.
struct AjustesLaboratorio: View {
    @AppStorage("origenMapas") private var origen = OrigenElegido.app.rawValue
    @AppStorage("urlMac") private var urlMac = ""

    var body: some View {
        Form {
            Section {
                Picker("Origen", selection: $origen) {
                    ForEach(OrigenElegido.allCases) { Text($0.nombre).tag($0.rawValue) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text(explicacion)
            }

            if origen == OrigenElegido.mac.rawValue {
                Section {
                    TextField("http://192.168.1.20:4180", text: $urlMac)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Dirección de la Mac")
                } footer: {
                    Text("En la Mac, dentro del repositorio Map: npm run dev. Copia aquí la dirección que dice «Network».")
                }
            }
        }
        .navigationTitle("Origen de los mapas")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var explicacion: String {
        switch OrigenElegido(rawValue: origen) ?? .app {
        case .app:
            "Los 89 MB de mapas van dentro del app. Funciona sin internet."
        case .nube:
            OrigenDatos.urlNube.map { "Cloudflare R2 · \($0.host() ?? $0.absoluteString). Baja solo la parte de cada zona que miras." }
                ?? "Falta MapNubeURL en Info.plist: se usarán los mapas del app."
        case .mac:
            "La Mac sirve los mapas por la misma Wi-Fi. Si la dirección está vacía, se usarán los del app."
        }
    }
}
