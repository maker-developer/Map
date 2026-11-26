import UIKit
import MapLibre

/// Escudos de autopista dibujados en código (sin imágenes de terceros), estirables para que quepa
/// cualquier número: la capa `escudos` del estilo usa `escudo-<red>` con `icon-text-fit`.
///
/// `red` (de Codex, ver `equipo/capas.md`): `I` interestatal, `US` federal, `SR` estatal,
/// `TP` Turnpike; cualquier otra cosa usa `escudo-otro`.
enum Escudos {
    private struct Diseno {
        let relleno: UIColor
        let borde: UIColor
        let radio: CGFloat
    }

    private static let disenos: [String: Diseno] = [
        "I": Diseno(relleno: UIColor(red: 0.12, green: 0.30, blue: 0.62, alpha: 1), borde: .white, radio: 6),
        "US": Diseno(relleno: .white, borde: UIColor(white: 0.12, alpha: 1), radio: 4),
        "SR": Diseno(relleno: .white, borde: UIColor(red: 0.18, green: 0.42, blue: 0.30, alpha: 1), radio: 3),
        "TP": Diseno(relleno: UIColor(red: 0.16, green: 0.47, blue: 0.31, alpha: 1), borde: .white, radio: 6),
        "otro": Diseno(relleno: UIColor(white: 0.96, alpha: 1), borde: UIColor(white: 0.45, alpha: 1), radio: 4),
    ]

    /// Añade los escudos al estilo recién cargado.
    static func registrar(en estilo: MLNStyle) {
        for (red, diseno) in disenos {
            estilo.setImage(imagen(diseno), forName: "escudo-\(red)")
        }
    }

    private static func imagen(_ d: Diseno) -> UIImage {
        let tamano = CGSize(width: 24, height: 18)
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 3
        let imagen = UIGraphicsImageRenderer(size: tamano, format: formato).image { _ in
            let caja = CGRect(origin: .zero, size: tamano).insetBy(dx: 1, dy: 1)
            let forma = UIBezierPath(roundedRect: caja, cornerRadius: d.radio)
            d.relleno.setFill()
            forma.fill()
            d.borde.setStroke()
            forma.lineWidth = 1.5
            forma.stroke()
        }
        // Las esquinas no se estiran; el centro sí, para que quepa «I-95» o «FL Turnpike».
        return imagen.resizableImage(
            withCapInsets: UIEdgeInsets(top: 7, left: 8, bottom: 7, right: 8),
            resizingMode: .stretch
        )
    }
}
