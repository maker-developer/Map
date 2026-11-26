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

/// Inicio: la lista de experimentos, como Ajustes.
struct ListaExperimentos: View {
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
                        Label {
                            Text("Datos desde la Mac")
                        } icon: {
                            IconoCuadro(icono: .capas, color: .gray)
                        }
                    }
                } footer: {
                    Text("Para probar teselas nuevas sin volver a compilar: el app las pide a la Mac en la misma Wi-Fi.")
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

/// Dirección de la Mac para pedirle las teselas (opcional).
struct AjustesLaboratorio: View {
    @AppStorage("urlMac") private var urlMac = ""

    var body: some View {
        Form {
            Section {
                TextField("http://192.168.1.20:4180", text: $urlMac)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Dirección de la Mac")
            } footer: {
                Text("En la Mac, dentro del repositorio Map: npm run dev. Copia aquí la dirección que dice «Network». Déjalo vacío para usar los mapas del app.")
            }
        }
        .navigationTitle("Datos desde la Mac")
        .navigationBarTitleDisplayMode(.inline)
    }
}
