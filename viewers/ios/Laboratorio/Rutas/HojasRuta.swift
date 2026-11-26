import SwiftUI
import CoreLocation
import UIKit

// MARK: - Ficha del lugar

/// Ficha de un sitio, como en Apple Maps. Arriba, lo que se ve al abrirla: nombre, categoría, distancia,
/// si está abierto ahora y la fila de acciones («Cómo llegar · 7 min» en azul y círculos de vidrio).
/// Si es un negocio del catálogo (`lugar.ficha`), debajo y al subir la hoja: Llamar / Sitio web / Correo,
/// fotos con su crédito, descripción, horario de la semana, contacto y redes, servicios, pagos y la fuente.
/// Cada parte sale solo si hay datos. La hoja abre a la altura de la parte de arriba (`altura`).
struct HojaLugar: View {
    let navegador: Navegador
    @Binding var altura: CGFloat
    @Environment(\.openURL) private var abrirURL
    @State private var copiado = false
    @State private var semanaAbierta = false
    @State private var descripcionAbierta = false

    var body: some View {
        if let lugar = navegador.destino {
            let ficha = lugar.ficha
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 18) {
                        cabecera(lugar, ficha)
                        acciones(lugar)
                        if ficha == nil { detallesBasicos(lugar) }
                    }
                    // La hoja abre a la altura de esta parte (más el asa y los márgenes).
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { altura = $0 + 50 }

                    if let ficha {
                        contactoRapido(ficha)
                        if !ficha.fotos.isEmpty { fotos(ficha.fotos) }
                        if let texto = ficha.descripcion { descripcion(texto) }
                        if let horario = ficha.horario { semana(horario) }
                        detalles(lugar, ficha)
                        if !ficha.servicios.isEmpty { chips("Servicios", ficha.servicios) }
                        if !ficha.pagos.isEmpty { chips("Formas de pago", ficha.pagos) }
                        fuente(ficha)
                    }

                    if let error = navegador.error {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .sensoryFeedback(.success, trigger: copiado)
            .animation(.snappy, value: navegador.duracionPorModo.count)
            .animation(.snappy, value: semanaAbierta)
            .animation(.snappy, value: descripcionAbierta)
        }
    }

    // MARK: Cabecera

    private func cabecera(_ lugar: Lugar, _ ficha: FichaLugar?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ficha?.nombre ?? lugar.nombre)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                HStack(spacing: 6) {
                    if let categoria = ficha?.categoria {
                        Text(categoria).lineLimit(1)
                        Text("·")
                    }
                    if let aqui = navegador.ubicacion {
                        let metros = aqui.distance(from: .init(latitude: lugar.coordenada.latitude, longitude: lugar.coordenada.longitude))
                        Text(FormatoRuta.distancia(metros))
                    }
                    if ficha?.categoria == nil {
                        if navegador.ubicacion != nil { Text("·") }
                        Text(lugar.subtitulo.isEmpty ? "Lugar" : lugar.subtitulo).lineLimit(1)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let ficha {
                    if ficha.cerrado {
                        Text("Cerrado permanentemente")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                    } else if let estado = ficha.horario?.estado() {
                        Text(estado.texto)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(estado.abierto ? Color.green : Color.red)
                    }
                    if let marca = ficha.marca {
                        Text(marca).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            BotonCerrarHoja { navegador.cerrar() }
        }
    }

    // MARK: Acciones

    /// La principal en azul y las demás en círculos de vidrio.
    private func acciones(_ lugar: Lugar) -> some View {
        let favoritos = navegador.favoritos
        let guardado = favoritos.esGuardado(lugar)
        return HStack(spacing: 10) {
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
    }

    /// Llamar · Sitio web · Correo en baldosas iguales (solo las que tiene el negocio).
    @ViewBuilder
    private func contactoRapido(_ ficha: FichaLugar) -> some View {
        let tel = ficha.telefonos.first.flatMap(Self.urlTelefono)
        let web = ficha.webs.first
        let correo = ficha.correo.flatMap { URL(string: "mailto:\($0)") }
        if tel != nil || web != nil || correo != nil {
            HStack(spacing: 10) {
                if let tel { baldosa(.telefono, "Llamar") { abrirURL(tel) } }
                if let web { baldosa(.web, "Sitio web") { abrirURL(web) } }
                if let correo { baldosa(.correo, "Correo") { abrirURL(correo) } }
            }
        }
    }

    private func baldosa(_ icono: Lc, _ titulo: String, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            VStack(spacing: 5) {
                Icono(icono, tamano: 20)
                Text(titulo).font(.caption.weight(.semibold))
            }
            .foregroundStyle(Color.blue)
            .frame(maxWidth: .infinity, minHeight: 58)
            .vidrio(RoundedRectangle(cornerRadius: 16, style: .continuous), interactivo: true)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.presionable)
    }

    // MARK: Fotos y descripción

    private func fotos(_ fotos: [FichaLugar.Foto]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(fotos, id: \.url) { foto in
                    Button {
                        if let pagina = foto.pagina { abrirURL(pagina) }
                    } label: {
                        AsyncImage(url: foto.url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { fase in
                            switch fase {
                            case .success(let imagen): imagen.resizable().scaledToFill()
                            case .failure: Icono(.foto, tamano: 26).foregroundStyle(.tertiary)
                            default: ProgressView()
                            }
                        }
                        .frame(width: fotos.count == 1 ? 350 : 230, height: 160)
                        .fondoPieza(radio: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(alignment: .bottomLeading) {
                            // Crédito obligatorio de Wikimedia Commons: autor y licencia.
                            let credito = [foto.autor, foto.licencia].compactMap { $0 }.joined(separator: " · ")
                            if !credito.isEmpty {
                                Text(credito)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.black.opacity(0.45), in: Capsule())
                                    .padding(8)
                            }
                        }
                    }
                    .buttonStyle(.presionable)
                    .accessibilityLabel("Foto de \(foto.autor ?? "Wikimedia Commons")")
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func descripcion(_ texto: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            titulo("Acerca de")
            Text(texto)
                .font(.subheadline)
                .lineLimit(descripcionAbierta ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
            if texto.count > 140 {
                Button(descripcionAbierta ? "Menos" : "Más") { descripcionAbierta.toggle() }
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    // MARK: Horario

    /// Hoy arriba (con si está abierto); al tocar, la semana entera con hoy resaltado.
    private func semana(_ horario: Horario) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            titulo("Horario")
            VStack(alignment: .leading, spacing: 0) {
                if horario.estado() != nil {
                    let hoy = Horario.hoy()
                    Button { semanaAbierta.toggle() } label: {
                        HStack(spacing: 10) {
                            Icono(.horario, tamano: 17).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hoy").font(.footnote).foregroundStyle(.secondary)
                                Text(horario.texto(dia: hoy)).font(.subheadline)
                            }
                            Spacer(minLength: 0)
                            Icono(.flecha, tamano: 15)
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(semanaAbierta ? 90 : 0))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(semanaAbierta ? "Ocultar la semana" : "Ver la semana")

                    if semanaAbierta {
                        Divider().padding(.leading, 14)
                        VStack(spacing: 8) {
                            ForEach(0..<7, id: \.self) { dia in
                                HStack {
                                    Text(Horario.nombresES[dia])
                                    Spacer()
                                    Text(horario.texto(dia: dia))
                                        .foregroundStyle(horario.texto(dia: dia) == "Cerrado" ? Color.secondary : Color.primary)
                                }
                                .font(.subheadline.weight(dia == hoy ? .semibold : .regular))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                } else {
                    // Formato que no se entiende (feriados, temporadas…): el texto tal cual.
                    HStack(spacing: 10) {
                        Icono(.horario, tamano: 17).foregroundStyle(.secondary)
                        Text(horario.original).font(.subheadline).textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
            .fondoPieza()
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: Detalles

    private func detallesBasicos(_ lugar: Lugar) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            detalle("Dirección", [lugar.nombre, lugar.subtitulo].filter { !$0.isEmpty }.joined(separator: "\n")) {
                copiar([lugar.nombre, lugar.subtitulo].filter { !$0.isEmpty }.joined(separator: ", "))
            }
            Divider().padding(.leading, 14)
            detalle("Coordenadas", Self.coordenadas(lugar), accion: nil)
        }
        .fondoPieza()
    }

    /// Teléfonos, webs, correo, redes, dirección y coordenadas en una sola pieza.
    private func detalles(_ lugar: Lugar, _ ficha: FichaLugar) -> some View {
        let direccion = ficha.direccion ?? lugar.subtitulo
        var filas: [AnyView] = []
        for (i, tel) in ficha.telefonos.enumerated() {
            filas.append(AnyView(enlaceFila(i == 0 ? "Teléfono" : "Otro teléfono", tel, .telefono, Self.urlTelefono(tel))))
        }
        for web in ficha.webs {
            filas.append(AnyView(enlaceFila("Sitio web", Self.bonita(web), .web, web)))
        }
        if let correo = ficha.correo {
            filas.append(AnyView(enlaceFila("Correo", correo, .arroba, URL(string: "mailto:\(correo)"))))
        }
        for red in ficha.redes {
            filas.append(AnyView(enlaceFila(red.nombre, Self.bonita(red.url), .enlace, red.url)))
        }
        if !direccion.isEmpty {
            filas.append(AnyView(detalle("Dirección", direccion) { copiar(direccion.replacingOccurrences(of: "\n", with: ", ")) }))
        }
        filas.append(AnyView(detalle("Coordenadas", Self.coordenadas(lugar), accion: nil)))

        return VStack(alignment: .leading, spacing: 6) {
            titulo("Detalles")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(filas.indices, id: \.self) { i in
                    if i > 0 { Divider().padding(.leading, 14) }
                    filas[i]
                }
            }
            .fondoPieza()
        }
    }

    /// Una fila que se toca para llamar o abrir (el valor en azul, como Apple Maps).
    private func enlaceFila(_ titulo: String, _ valor: String, _ icono: Lc, _ url: URL?) -> some View {
        Button {
            if let url { abrirURL(url) }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo).font(.footnote).foregroundStyle(.secondary)
                    Text(valor).font(.subheadline).foregroundStyle(Color.blue).lineLimit(1)
                }
                Spacer(minLength: 0)
                Icono(icono, tamano: 17).foregroundStyle(Color.blue)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copiar") { copiar(valor) }
        }
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

    // MARK: Servicios, pagos y fuente

    private func chips(_ seccion: String, _ textos: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            titulo(seccion)
            FilaFlexible(espacio: 8) {
                ForEach(textos, id: \.self) { texto in
                    HStack(spacing: 6) {
                        Icono(Self.iconoChip(texto), tamano: 14).foregroundStyle(.secondary)
                        Text(texto).font(.subheadline)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .fondoPieza(radio: 100)
                }
            }
        }
    }

    private func fuente(_ ficha: FichaLugar) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let atribucion = ficha.atribucion {
                Text("Datos: \(atribucion)")
            }
            if !ficha.fotos.isEmpty {
                Text("Fotos: Wikimedia Commons, con la licencia de cada autor.")
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Piezas

    private func titulo(_ texto: String) -> some View {
        Text(texto)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
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

    private func copiar(_ texto: String) {
        UIPasteboard.general.string = texto
        copiado = true
        Task { try? await Task.sleep(for: .seconds(1.5)); copiado = false }
    }

    private static func coordenadas(_ lugar: Lugar) -> String {
        String(format: "%.5f, %.5f", lugar.coordenada.latitude, lugar.coordenada.longitude)
    }

    /// «+1 (305) 555-0100» → tel:+13055550100
    static func urlTelefono(_ telefono: String) -> URL? {
        let limpio = telefono.filter { $0.isNumber || $0 == "+" }
        return limpio.isEmpty ? nil : URL(string: "tel:\(limpio)")
    }

    /// «https://www.ejemplo.com/» → «ejemplo.com»
    private static func bonita(_ url: URL) -> String {
        var t = url.absoluteString
        for prefijo in ["https://", "http://", "www."] where t.hasPrefix(prefijo) { t.removeFirst(prefijo.count) }
        if t.hasSuffix("/") { t.removeLast() }
        return t
    }

    private static func iconoChip(_ texto: String) -> Lc {
        switch texto {
        case "Para llevar": .compras
        case "Entrega a domicilio": .entrega
        case "Comer en el local": .comida
        case "Autoservicio en el auto": .coche
        case "Reservas": .horario
        case "Terraza": .asiento
        case "Wi-Fi": .wifi
        case "Accesible en silla de ruedas", "Accesibilidad limitada": .accesible
        case "Opciones veganas", "Opciones vegetarianas", "Sin gluten", "Halal", "Kosher": .hoja
        case "Efectivo": .etiqueta
        default: .tarjeta
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

/// Coloca las píldoras en filas que saltan de línea (servicios y pagos).
struct FilaFlexible: Layout {
    var espacio: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ancho = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, alto: CGFloat = 0, maximo: CGFloat = 0
        for v in subviews {
            let t = v.sizeThatFits(.unspecified)
            if x > 0, x + t.width > ancho { x = 0; y += alto + espacio; alto = 0 }
            x += t.width + espacio
            alto = max(alto, t.height)
            maximo = max(maximo, x - espacio)
        }
        return CGSize(width: proposal.width ?? maximo, height: y + alto)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, alto: CGFloat = 0
        for v in subviews {
            let t = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + t.width > bounds.maxX { x = bounds.minX; y += alto + espacio; alto = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(t))
            x += t.width + espacio
            alto = max(alto, t.height)
        }
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
                    .foregroundStyle(Color.primary)
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
                .foregroundStyle(Color.primary)
                Spacer(minLength: 0)
            }

            // Carriles: los que sirven en blanco, los demás apagados.
            if !navegador.llegaste, let paso, paso.carriles.count > 1 {
                HStack(spacing: 6) {
                    ForEach(paso.carriles) { carril in
                        Icono(carril.icono, tamano: 22)
                            .foregroundStyle(carril.valido ? Color.primary : Color.primary.opacity(0.25))
                            .frame(width: 34, height: 34)
                            .background(carril.valido ? Color.primary.opacity(0.09) : Color.clear,
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
                    .foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if ruta.pasos.indices.contains(navegador.pasoActual + 2) {
                    let luego = ruta.pasos[navegador.pasoActual + 2]
                    HStack(spacing: 6) {
                        Text("Luego")
                        Icono(luego.icono, tamano: 14)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Liquid Glass (antes, verde oscuro).
        .vidrio(RoundedRectangle(cornerRadius: 26, style: .continuous), interactivo: true)
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
    /// La barra está subida: se ven «Finalizar» y las opciones. Recogida, solo las cifras.
    var expandida = false

    var body: some View {
        Group {
            if navegador.llegaste {
                llegada
            } else {
                VStack(spacing: 18) {
                    cifras
                    if expandida {
                        ScrollView {
                            VStack(spacing: 14) {
                                // «Finalizar» en Liquid Glass con tinte rojo (no un bloque rojo sólido).
                                Button {
                                    navegador.finalizar()
                                } label: {
                                    Text("Finalizar ruta")
                                        .font(.headline)
                                        .foregroundStyle(Color.red)
                                        .frame(maxWidth: .infinity, minHeight: 52)
                                        .vidrio(Capsule(), interactivo: true, tinte: .red.opacity(0.35))
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.presionable)
                                opciones
                            }
                            .padding(.bottom, 24)
                        }
                        .scrollIndicators(.hidden)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: expandida)
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
