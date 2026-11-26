import SwiftUI
import Observation

/// El rumbo del mapa, para la brújula de vidrio (la de MapLibre no es Liquid Glass).
@MainActor
@Observable
final class Brujula {
    /// Grados hacia los que mira el mapa (0 = norte arriba).
    var rumbo: Double = 0
    /// Sube para pedir al mapa que vuelva al norte.
    private(set) var pedirNorte = 0

    func norte() { pedirNorte += 1 }

    /// Como Apple Maps: solo se ve cuando el mapa no mira al norte.
    var visible: Bool {
        let r = rumbo.truncatingRemainder(dividingBy: 360)
        return min(abs(r), abs(360 - abs(r))) > 2
    }
}

/// Brujula de Liquid Glass: «N» arriba y la aguja roja apuntando al norte, girando con el mapa.
/// Al tocarla, el mapa vuelve al norte.
struct BotonBrujula: View {
    let brujula: Brujula
    var tamano: CGFloat = 46

    var body: some View {
        Button {
            brujula.norte()
        } label: {
            ZStack {
                // Aguja: roja hacia el norte, gris hacia el sur.
                VStack(spacing: 0) {
                    Triangulo().fill(Color.red).frame(width: 8, height: 11)
                    Triangulo().fill(Color.secondary.opacity(0.6)).frame(width: 8, height: 11).rotationEffect(.degrees(180))
                }
                Text("N")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .offset(y: -tamano * 0.36)
            }
            .rotationEffect(.degrees(-brujula.rumbo))
            .frame(width: tamano, height: tamano)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .vidrio(Circle(), interactivo: true)
        .accessibilityLabel("Brújula. Toca para mirar al norte")
    }
}

private struct Triangulo: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
