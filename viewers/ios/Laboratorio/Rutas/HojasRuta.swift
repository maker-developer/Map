import SwiftUI
import CoreLocation
import UIKit

// MARK: - Ficha del lugar

/// Ficha de un sitio, como en Apple Maps: nombre, dirección y distancia; una fila de acciones
/// («Cómo llegar · 7 min» en azul y círculos de vidrio para guardar, compartir y más) y los detalles.
/// La hoja se ajusta a lo que mide (sin hueco vacío): avisa de su alto con `altura`.
struct HojaLugar: View {
    let navegador: Navegador
    @Binding var altura: CGFloat
    @Environment(\.openURL) private var abrirURL
    @State private var copiado = false

    var body: some View {
        if let lugar = navegador.destino {
            let favoritos = navegador.favoritos
            let guardado = favoritos.esGuardado(lugar)
            VStack(alignment: .leading, spacing: 18) {
                // Cabecera
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lugar.nombre)
                            .font(.title2.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.opacity)
                        HStack(spacing: 6) {
                            if let aqui = navegador.ubicacion {
                                let metros = aqui.distance(from: .init(latitude: lugar.coordenada.latitude, longitude: lugar.coordenada.longitude))
                                Text(FormatoRuta.distancia(metros))
                                Text("·")
                            }
                            Text(lugar.subtitulo.isEmpty ? "Lugar" : lugar.subtitulo)
                                .lineLimit(1)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    BotonCerrarHoja { navegador.cerrar() }
                }

                // Acciones en una fila: la principal en azul y las demás en círculos de vidrio.
                HStack(spacing: 10) {
                    Button {
                        navegador.comoLlegar()
                    } label: {
                        HStack(spacing: 8) {
                            Icono(navegador.modo.icono, tamano: 18)
                            Text("Cómo llegar")
                            if let duracion = navegador.duracionPorModo[navegador.modo] {
                                Text("· \(FormatoRuta.duracion(duracion))")
                                    .contentTransition(.numericText())
                            } else if navegador.cargando {
                                ProgressView().tint(.white).controlSize(.small)
                            }
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.blue, in: Capsule())
                    }
                    .buttonStyle(.presionable)

                    circulo(guardado ? .guardado : .guardar, guardado ? "Quitar de guardados" : "Guardar") {
                        favoritos.alternarGuardado(lugar)
                    }
                    .sensoryFeedback(.success, trigger: guardado)

                    ShareLink(item: Self.enlace(lugar), subject: Text(lugar.nombre),
                              message: Text([lugar.nombre, lugar.subtitulo].filter { !$0.isEmpty }.joined(separator: "\n"))) {
                        iconoCirculo(.compartir)
                    }
                    .buttonStyle(.presionable)
                    .accessibilityLabel("Compartir")

                    Menu {
                        Button("Abrir en Apple Maps") { abrirURL(Self.enlace(lugar)) }
                        Button("Abrir en Google Maps") {
                            abrirURL(URL(string: "https://www.google.com/maps/search/?api=1&query=\(lugar.coordenada.latitude),\(lugar.coordenada.longitude)")!)
                        }
                        Button("Abrir en Waze") {
                            abrirURL(URL(string: "https://waze.com/ul?ll=\(lugar.coordenada.latitude),\(lugar.coordenada.longitude)&navigate=yes")!)
                        }
                        Divider()
                        Button("Guardar como Casa") { favoritos.ponerCasa(lugar) }
                        Button("Guardar como Trabajo") { favoritos.ponerTrabajo(lugar) }
                    } label: {
                        iconoCirculo(.abrirFuera)
                    }
                    .accessibilityLabel("Más")
                }

                // Detalles: la dirección (con copiar) y las coordenadas.
                VStack(alignment: .leading, spacing: 0) {
                    detalle("Dirección", [lugar.nombre, lugar.subtitulo].filter { !$0.isEmpty }.joined(separator: "\n")) {
                        UIPasteboard.general.string = [lugar.nombre, lugar.subtitulo].filter { !$0.isEmpty }.joined(separator: ", ")
                        copiado = true
                        Task { try? await Task.sleep(for: .seconds(1.5)); copiado = false }
                    }
                    Divider().padding(.leading, 14)
                    detalle("Coordenadas", String(format: "%.5f, %.5f", lugar.coordenada.latitude, lugar.coordenada.longitude), accion: nil)
                }
                .fondoPieza()
                .sensoryFeedback(.success, trigger: copiado)

                if let error = navegador.error {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 8)
            // La hoja mide lo que el contenido (más el asa de arriba).
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { altura = $0 + 20 }
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(.snappy, value: navegador.duracionPorModo.count)
        }
    }

    private func circulo(_ icono: Lc, _ etiqueta: String, accion: @escaping () -> Void) -> some View {
        Button(action: accion) { iconoCirculo(icono) }
            .buttonStyle(.presionable)
            .accessibilityLabel(etiqueta)
    }

    private func iconoCirculo(_ icono: Lc) -> some View {
        Icono(icono, tamano: 19)
            .foregroundStyle(Color.blue)
            .frame(width: 50, height: 50)
            .vidrio(Circle(), interactivo: true)
            .contentShape(Circle())
    }

    private func detalle(_ titulo: String, _ valor: String, accion: (() -> Void)?) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(valor)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            if let accion {
                Button(action: accion) {
                    Icono(copiado ? .guardado : .copiar, tamano: 17)
                        .foregroundStyle(Color.blue)
                        .frame(width: 36, height: 36)
                        .contentTransition(.opacity)
                }
                .buttonStyle(.presionable)
                .accessibilityLabel(copiado ? "Copiado" : "Copiar dirección")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Enlace universal del lugar (abre Apple Maps; en otros teléfonos, la web de Apple Maps).
    static func enlace(_ lugar: Lugar) -> URL {
        var c = URLComponents(string: "https://maps.apple.com/")!
        c.queryItems = [URLQueryItem(name: "ll", value: "\(lugar.coordenada.latitude),\(lugar.coordenada.longitude)"),
                        URLQueryItem(name: "q", value: lugar.nombre)]
        return c.url!
    }
}

// MARK: - Planificar la ruta

/// «Cómo llegar», como Apple Maps: el destino en grande con «Desde Mi ubicación» e ⇅, los modos en una
/// cápsula de vidrio con un indicador que se desliza, las rutas como filas limpias (la elegida resaltada
/// con un fondo que se mueve suave) con «Ir», y los pasos que se despliegan.
struct HojaRuta: View {
    let navegador: Navegador
    @State private var verPasos = false
    @Namespace private var animacion

    var body: some View {
        VStack(spacing: 16) {
            cabecera
            modos

            ScrollView {
                VStack(spacing: 6) {
                    if navegador.cargando && navegador.rutas.isEmpty {
                        ForEach(0..<2, id: \.self) { _ in filaCargando }
                    } else if let error = navegador.error, navegador.rutas.isEmpty {
                        VStack(spacing: 8) {
                            Icono(.ruta, tamano: 26).foregroundStyle(.secondary)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 110)
                    }

                    ForEach(Array(navegador.rutas.enumerated()), id: \.element.id) { i, ruta in
                        FilaRuta(ruta: ruta, elegida: i == navegador.elegida, masRapida: i == 0 && navegador.rutas.count > 1,
                                 animacion: animacion) {
                            if i == navegador.elegida { navegador.iniciar() } else { navegador.elegirRuta(i) }
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    if let ruta = navegador.rutaElegida {
                        pasos(ruta)
                            .padding(.top, 8)
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: navegador.elegida)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: navegador.rutas.count)
        .animation(.snappy, value: navegador.modo)
    }

    /// Destino en grande, «Desde Mi ubicación» y el botón ⇅.
    private var cabecera: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(navegador.destino?.nombre ?? "Cómo llegar")
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
                    .contentTransition(.opacity)
                HStack(spacing: 6) {
                    Icono(.origen, tamano: 13).foregroundStyle(.blue)
                    Text("Desde \(navegador.nombreOrigen)")
                        .lineLimit(1)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.snappy) { navegador.invertir() }
            } label: {
                Icono(.invertir, tamano: 16)
                    .foregroundStyle(Color.primary)
                    .frame(width: 36, height: 36)
                    .background(Color(uiColor: .tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.presionable)
            .accessibilityLabel("Invertir origen y destino")
            BotonCerrarHoja { navegador.cerrar() }
        }
    }

    /// Los modos en una cápsula de vidrio; el elegido con un fondo azul que se desliza.
    private var modos: some View {
        HStack(spacing: 4) {
            ForEach(ModoRuta.allCases) { m in
                let activo = m == navegador.modo
                Button {
                    navegador.cambiarModo(m)
                } label: {
                    HStack(spacing: 6) {
                        Icono(m.icono, tamano: 16)
                        Text(navegador.duracionPorModo[m].map(FormatoRuta.duracion) ?? "–")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .contentTransition(.numericText())
                    }
                    .foregroundStyle(activo ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background {
                        if activo {
                            Capsule().fill(Color.blue)
                                .matchedGeometryEffect(id: "modo", in: animacion)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.presionable)
                .accessibilityLabel(m.nombre)
                .accessibilityAddTraits(activo ? .isSelected : [])
            }
        }
        .padding(4)
        .vidrio(Capsule())
        .sensoryFeedback(.selection, trigger: navegador.modo)
    }

    private var filaCargando: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)).frame(width: 90, height: 22)
            RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)).frame(width: 200, height: 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .fondoPieza()
        .redacted(reason: .placeholder)
    }

    /// «8 pasos» que se despliegan con animación.
    private func pasos(_ ruta: Ruta) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { verPasos.toggle() }
            } label: {
                HStack {
                    Icono(.listaPasos, tamano: 17).foregroundStyle(.secondary)
                    Text("\(ruta.pasos.count) pasos")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Icono(.flecha, tamano: 14)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(verPasos ? 90 : 0))
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if verPasos {
                ListaPasos(pasos: ruta.pasos)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .fondoPieza()
    }
}

/// Una ruta como fila limpia: tiempo grande, llegada y distancia, «Más rápida» y «por…»;
/// la elegida con fondo resaltado (que se desliza entre filas) y el botón verde «Ir».
private struct FilaRuta: View {
    let ruta: Ruta
    let elegida: Bool
    let masRapida: Bool
    let animacion: Namespace.ID
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(FormatoRuta.duracion(ruta.duracion))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        if masRapida {
                            Text("Más rápida")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }
                    Text("Llegas \(FormatoRuta.hora(ruta.llegada)) · \(FormatoRuta.distancia(ruta.distancia))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if !ruta.via.isEmpty {
                        Text(ruta.via)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if elegida {
                    Text("Ir")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 70, height: 44)
                        .background(Color.green, in: Capsule())
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .padding(14)
            .background {
                if elegida {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.blue.opacity(0.10))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.blue.opacity(0.35), lineWidth: 1))
                        .matchedGeometryEffect(id: "ruta", in: animacion)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.presionable)
        .accessibilityHint(elegida ? "Empieza la navegación" : "Elige esta ruta")
    }
}

/// Los pasos de la ruta con su flecha y distancia.
struct ListaPasos: View {
    let pasos: [Paso]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(pasos) { paso in
                HStack(spacing: 12) {
                    Icono(paso.icono, tamano: 18)
                        .foregroundStyle(.blue)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(paso.instruccion)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        if paso.distancia > 0 {
                            Text(FormatoRuta.distancia(paso.distancia))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                Divider().padding(.leading, 40)
            }
        }
        .padding(.top, 6)
    }
}

// MARK: - Navegando

/// Banner de arriba: la flecha grande, la distancia a la maniobra y la calle (como Apple y Google),
/// los carriles que sirven y, al tocarlo, la vista previa de los próximos pasos.
struct BannerManiobra: View {
    let navegador: Navegador
    @State private var verPrevia = false

    var body: some View {
        let paso = navegador.pasoSiguiente
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                Icono(navegador.llegaste ? .bandera : (paso?.icono ?? .flechaArriba), tamano: 40)
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    if navegador.llegaste {
                        Text("Has llegado")
                            .font(.title2.weight(.bold))
                    } else {
                        if let distancia = navegador.distanciaAlPaso {
                            Text(FormatoRuta.distancia(distancia))
                                .font(.title.weight(.bold))
                                .monospacedDigit()
                                .contentTransition(.numericText(countsDown: true))
                        }
                        Text(paso.map { titulo($0) } ?? "Sigue la ruta")
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)
                    }
                }
                .foregroundStyle(.white)
                Spacer(minLength: 0)
            }

            // Carriles: los que sirven en blanco, los demás apagados.
            if !navegador.llegaste, let paso, paso.carriles.count > 1 {
                HStack(spacing: 6) {
                    ForEach(paso.carriles) { carril in
                        Icono(carril.icono, tamano: 22)
                            .foregroundStyle(carril.valido ? Color.white : Color.white.opacity(0.3))
                            .frame(width: 34, height: 34)
                            .background(carril.valido ? Color.white.opacity(0.16) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .accessibilityLabel("Carriles: \(paso.carriles.filter(\.valido).count) de \(paso.carriles.count) sirven")
            }

            // La que viene después, en pequeño, o la vista previa de los próximos pasos.
            if !navegador.llegaste, let ruta = navegador.rutaElegida {
                if verPrevia {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(ruta.pasos.dropFirst(navegador.pasoActual + 2).prefix(3)) { siguiente in
                            HStack(spacing: 10) {
                                Icono(siguiente.icono, tamano: 16)
                                Text(siguiente.instruccion).lineLimit(1)
                                Spacer(minLength: 0)
                                Text(FormatoRuta.distancia(siguiente.distancia)).monospacedDigit()
                            }
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if ruta.pasos.indices.contains(navegador.pasoActual + 2) {
                    let luego = ruta.pasos[navegador.pasoActual + 2]
                    HStack(spacing: 6) {
                        Text("Luego")
                        Icono(luego.icono, tamano: 14)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.11, green: 0.36, blue: 0.27), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { verPrevia.toggle() } }
        .animation(.snappy, value: navegador.pasoActual)
        .sensoryFeedback(.impact(weight: .light), trigger: navegador.pasoActual)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Toca para ver los próximos pasos")
    }

    /// En salidas y rampas, el cartel («Salida 4 · Downtown»); si no, la calle o la instrucción.
    private func titulo(_ paso: Paso) -> String {
        if let destinos = paso.destinos, !destinos.isEmpty {
            return [paso.salida.map { "Salida \($0)" }, destinos].compactMap { $0 }.joined(separator: " · ")
        }
        return paso.calle.isEmpty ? paso.instruccion : paso.calle
    }
}

/// Barra de abajo al navegar, como Apple Maps: recogida, solo **llegada · tiempo · distancia**
/// centradas y en grande (letra del sistema, redondeada); al subirla, «Finalizar», las opciones
/// y los próximos pasos. Al llegar, la pantalla de llegada.
struct HojaNavegacion: View {
    let navegador: Navegador

    var body: some View {
        Group {
            if navegador.llegaste {
                llegada
            } else {
                VStack(spacing: 18) {
                    cifras
                    ScrollView {
                        VStack(spacing: 14) {
                            Button {
                                navegador.finalizar()
                            } label: {
                                Text("Finalizar ruta")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, minHeight: 50)
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.roundedRectangle(radius: 14))
                            .tint(.red)
                            opciones
                        }
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.snappy, value: navegador.llegaste)
        .sensoryFeedback(.success, trigger: navegador.llegaste)
    }

    /// Las tres cifras, simétricas: cada una en su tercio, centrada, número grande y unidad debajo.
    private var cifras: some View {
        let restante = navegador.restante
        let llegada = restante.map { Date().addingTimeInterval($0.duracion) }
        let hora = llegada.map { partir(FormatoRuta.hora($0)) } ?? ("--", "llegada")
        let tiempo = restante.map { partir(FormatoRuta.duracion($0.duracion)) } ?? ("--", "min")
        let distancia = restante.map { partir(FormatoRuta.distancia($0.distancia)) } ?? ("--", "")
        return HStack(spacing: 0) {
            cifra(hora.0, unidad: hora.1.isEmpty ? "llegada" : hora.1)
            cifra(tiempo.0, unidad: tiempo.1)
            cifra(distancia.0, unidad: distancia.1)
        }
        .frame(height: 64)
    }

    private func cifra(_ valor: String, unidad: String) -> some View {
        VStack(spacing: 0) {
            Text(valor)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(unidad)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: valor)
    }

    /// «1:17 p. m.» → («1:17», «p. m.»); «7 min» → («7», «min»); «2.3 mi» → («2.3», «mi»).
    private func partir(_ texto: String) -> (String, String) {
        guard let espacio = texto.firstIndex(where: { $0 == " " || $0 == "\u{202F}" || $0 == "\u{00A0}" }) else {
            return (texto, "")
        }
        let valor = String(texto[..<espacio])
        let unidad = String(texto[texto.index(after: espacio)...]).trimmingCharacters(in: .whitespaces)
        // «1 h 5 min»: todo como valor.
        if unidad.contains("min") && valor.allSatisfy(\.isNumber) && unidad.first?.isNumber == false && unidad != "min" {
            return (texto, "")
        }
        return (valor, unidad)
    }

    /// Opciones al subir la barra (como Apple Maps): resumen, compartir llegada, voz y los pasos.
    private var opciones: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Button {
                    navegador.resumen()
                } label: {
                    opcion(.ruta, "Resumen")
                }
                .buttonStyle(.plain)

                if let restante = navegador.restante, let destino = navegador.destino {
                    let hora = FormatoRuta.hora(Date().addingTimeInterval(restante.duracion))
                    ShareLink(item: "Voy a \(destino.nombre). Llego a las \(hora) (\(FormatoRuta.duracion(restante.duracion))).") {
                        opcion(.compartir, "Compartir llegada")
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    navegador.voz.toggle()
                } label: {
                    opcion(navegador.voz ? .vozSi : .vozNo, navegador.voz ? "Voz" : "Sin voz")
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: navegador.voz)
            }

            if let ruta = navegador.rutaElegida {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Próximos pasos")
                        .font(.headline)
                    ListaPasos(pasos: Array(ruta.pasos.dropFirst(navegador.pasoActual + 1)))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func opcion(_ icono: Lc, _ titulo: String) -> some View {
        VStack(spacing: 6) {
            Icono(icono, tamano: 20)
            Text(titulo)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(Color.blue)
        .frame(maxWidth: .infinity, minHeight: 64)
        .fondoPieza(radio: 14)
        .contentShape(Rectangle())
    }

    private var llegada: some View {
        HStack(spacing: 14) {
            Icono(.bandera, tamano: 26)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Color.green, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(navegador.destino?.nombre ?? "Has llegado")
                    .font(.headline)
                    .lineLimit(1)
                Text("Llegaste a las \(FormatoRuta.hora(navegador.horaLlegada ?? Date()))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Volver") { navegador.cerrar() }
                .font(.headline)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.blue)
                .controlSize(.large)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

/// Botón ✕ redondo de las hojas.
struct BotonCerrarHoja: View {
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Icono(.cerrar, tamano: 15)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Color(uiColor: .tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cerrar")
    }
}
