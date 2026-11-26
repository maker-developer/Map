import SwiftUI
import CoreLocation
import UIKit

// MARK: - Ficha del lugar

/// Ficha de un sitio (resultado de búsqueda o pin): nombre, dirección y «Cómo llegar» con su tiempo,
/// y acciones como en Apple Maps: guardar, compartir, copiar la dirección, abrir en otras apps
/// y guardarlo como Casa o Trabajo.
struct HojaLugar: View {
    let navegador: Navegador
    @Environment(\.openURL) private var abrirURL
    @State private var copiado = false

    var body: some View {
        if let lugar = navegador.destino {
            let favoritos = navegador.favoritos
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lugar.nombre)
                            .font(.title2.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        if !lugar.subtitulo.isEmpty {
                            Text(lugar.subtitulo)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let aqui = navegador.ubicacion {
                            let metros = aqui.distance(from: .init(latitude: lugar.coordenada.latitude, longitude: lugar.coordenada.longitude))
                            Text("A \(FormatoRuta.distancia(metros))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    BotonCerrarHoja { navegador.cerrar() }
                }

                // Botón principal azul con el tiempo en coche (como «🚗 12 min» de Apple Maps).
                Button {
                    navegador.comoLlegar()
                } label: {
                    HStack(spacing: 8) {
                        Icono(navegador.modo.icono, tamano: 18)
                        if let duracion = navegador.duracionPorModo[navegador.modo] {
                            Text(FormatoRuta.duracion(duracion))
                        } else {
                            Text("Cómo llegar")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .tint(.blue)
                .overlay(alignment: .trailing) {
                    if navegador.cargando && navegador.duracionPorModo.isEmpty {
                        ProgressView().tint(.white).padding(.trailing, 16)
                    }
                }

                // Acciones: guardar, compartir, copiar, abrir en… y más.
                HStack(spacing: 10) {
                    let guardado = favoritos.esGuardado(lugar)
                    Accion(icono: guardado ? .guardado : .guardar, titulo: guardado ? "Guardado" : "Guardar") {
                        favoritos.alternarGuardado(lugar)
                    }
                    .sensoryFeedback(.success, trigger: guardado)

                    ShareLink(item: Self.enlace(lugar), subject: Text(lugar.nombre),
                              message: Text([lugar.nombre, lugar.subtitulo].filter { !$0.isEmpty }.joined(separator: "\n"))) {
                        AccionEtiqueta(icono: .compartir, titulo: "Compartir")
                    }
                    .buttonStyle(.plain)

                    Accion(icono: .copiar, titulo: copiado ? "Copiado" : "Copiar") {
                        UIPasteboard.general.string = [lugar.nombre, lugar.subtitulo].filter { !$0.isEmpty }.joined(separator: ", ")
                        copiado = true
                        Task { try? await Task.sleep(for: .seconds(1.5)); copiado = false }
                    }
                    .sensoryFeedback(.success, trigger: copiado)

                    Menu {
                        Button("Apple Maps") { abrirURL(Self.enlace(lugar)) }
                        Button("Google Maps") {
                            abrirURL(URL(string: "https://www.google.com/maps/search/?api=1&query=\(lugar.coordenada.latitude),\(lugar.coordenada.longitude)")!)
                        }
                        Button("Waze") {
                            abrirURL(URL(string: "https://waze.com/ul?ll=\(lugar.coordenada.latitude),\(lugar.coordenada.longitude)&navigate=yes")!)
                        }
                        Divider()
                        Button("Guardar como Casa") { favoritos.ponerCasa(lugar) }
                        Button("Guardar como Trabajo") { favoritos.ponerTrabajo(lugar) }
                    } label: {
                        AccionEtiqueta(icono: .abrirFuera, titulo: "Más")
                    }
                }

                if let error = navegador.error {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// Enlace universal del lugar (abre Apple Maps; en otros teléfonos, la web de Apple Maps).
    static func enlace(_ lugar: Lugar) -> URL {
        var c = URLComponents(string: "https://maps.apple.com/")!
        c.queryItems = [URLQueryItem(name: "ll", value: "\(lugar.coordenada.latitude),\(lugar.coordenada.longitude)"),
                        URLQueryItem(name: "q", value: lugar.nombre)]
        return c.url!
    }
}

/// Botón de acción de la ficha (ícono arriba, texto abajo).
private struct Accion: View {
    let icono: Lc
    let titulo: String
    let accion: () -> Void

    var body: some View {
        Button(action: accion) { AccionEtiqueta(icono: icono, titulo: titulo) }
            .buttonStyle(.plain)
    }
}

private struct AccionEtiqueta: View {
    let icono: Lc
    let titulo: String

    var body: some View {
        VStack(spacing: 4) {
            Icono(icono, tamano: 19)
            Text(titulo)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(Color.blue)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}

// MARK: - Planificar la ruta

/// Origen y destino, pestañas de modo con su tiempo, las rutas posibles y «Ir».
struct HojaRuta: View {
    let navegador: Navegador
    @State private var verPasos = false

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text("Cómo llegar")
                    .font(.title2.weight(.bold))
                Spacer(minLength: 0)
                BotonCerrarHoja { navegador.cerrar() }
            }

            campos
            modos

            ScrollView {
                VStack(spacing: 10) {
                    if navegador.cargando && navegador.rutas.isEmpty {
                        ProgressView("Buscando rutas…")
                            .frame(maxWidth: .infinity, minHeight: 90)
                    } else if let error = navegador.error, navegador.rutas.isEmpty {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 90)
                    }
                    ForEach(Array(navegador.rutas.enumerated()), id: \.element.id) { i, ruta in
                        TarjetaRuta(ruta: ruta, elegida: i == navegador.elegida, masRapida: i == 0,
                                    modo: navegador.modo) {
                            if i == navegador.elegida { navegador.iniciar() } else { navegador.elegirRuta(i) }
                        }
                    }
                    if let ruta = navegador.rutaElegida {
                        DisclosureGroup(isExpanded: $verPasos) {
                            ListaPasos(pasos: ruta.pasos)
                        } label: {
                            Text("\(ruta.pasos.count) pasos")
                                .font(.subheadline.weight(.semibold))
                        }
                        .tint(.primary)
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                    }
                    Text("Rutas de prueba: OSRM · © OpenStreetMap. Se cambiarán por el motor propio.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .animation(.snappy, value: navegador.elegida)
    }

    /// «Desde: Mi ubicación» / «Hasta: …» con el botón ⇅ para invertir.
    private var campos: some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                fila(icono: .origen, color: .blue, titulo: navegador.nombreOrigen)
                Divider().padding(.leading, 36)
                fila(icono: .pin, color: .red, titulo: navegador.destino?.nombre ?? "")
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button {
                navegador.invertir()
            } label: {
                Icono(.invertir, tamano: 18)
                    .foregroundStyle(Color.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .vidrio(Circle(), interactivo: true)
            .accessibilityLabel("Invertir origen y destino")
        }
    }

    private func fila(icono: Lc, color: Color, titulo: String) -> some View {
        HStack(spacing: 12) {
            Icono(icono, tamano: 16).foregroundStyle(color).frame(width: 24)
            Text(titulo).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    /// Pestañas Coche / A pie / Bici, cada una con su tiempo.
    private var modos: some View {
        HStack(spacing: 8) {
            ForEach(ModoRuta.allCases) { m in
                let activo = m == navegador.modo
                Button {
                    navegador.cambiarModo(m)
                } label: {
                    VStack(spacing: 2) {
                        Icono(m.icono, tamano: 18)
                        Text(navegador.duracionPorModo[m].map(FormatoRuta.duracion) ?? m.nombre)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .foregroundStyle(activo ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(activo ? Color.blue : Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(m.nombre)
                .accessibilityAddTraits(activo ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: navegador.modo)
    }
}

/// Una ruta: tiempo grande, llegada, distancia, «por…» y «Ir» en la elegida.
private struct TarjetaRuta: View {
    let ruta: Ruta
    let elegida: Bool
    let masRapida: Bool
    let modo: ModoRuta
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(FormatoRuta.duracion(ruta.duracion))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Text("Llegas a las \(FormatoRuta.hora(ruta.llegada)) · \(FormatoRuta.distancia(ruta.distancia))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    HStack(spacing: 6) {
                        if masRapida {
                            Text("Más rápida")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                        if !ruta.via.isEmpty {
                            Text(ruta.via)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 8)
                if elegida {
                    Text("Ir")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 44)
                        .background(Color.green, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(elegida ? Color.blue : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
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

/// Barra de abajo al navegar: llegada, minutos y distancia que faltan, voz y «Finalizar».
/// Al llegar, la pantalla de llegada: el destino, la hora y «Volver».
struct HojaNavegacion: View {
    let navegador: Navegador

    var body: some View {
        Group {
            if navegador.llegaste {
                llegada
            } else {
                enCamino
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.snappy, value: navegador.llegaste)
        .sensoryFeedback(.success, trigger: navegador.llegaste)
    }

    private var enCamino: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                if let restante = navegador.restante {
                    Text(FormatoRuta.hora(Date().addingTimeInterval(restante.duracion)))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("\(FormatoRuta.duracion(restante.duracion)) · \(FormatoRuta.distancia(restante.distancia))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                } else {
                    Text("Calculando…").font(.headline)
                }
            }
            Spacer(minLength: 0)
            Button {
                navegador.voz.toggle()
            } label: {
                Icono(navegador.voz ? .vozSi : .vozNo, tamano: 20)
                    .foregroundStyle(Color.primary)
                    .frame(width: 46, height: 46)
            }
            .buttonStyle(.plain)
            .vidrio(Circle(), interactivo: true)
            .sensoryFeedback(.selection, trigger: navegador.voz)
            .accessibilityLabel(navegador.voz ? "Silenciar voz" : "Activar voz")

            Button("Finalizar") { navegador.finalizar() }
                .font(.headline)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.red)
                .controlSize(.large)
        }
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
