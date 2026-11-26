import SwiftUI

/// Map: un mapa normal de Miami-Dade (como Apple Maps) con el estilo propio.
/// El modo laboratorio (ícono del matraz junto a la búsqueda) abre los experimentos de cada
/// ronda para comparar legibilidad, fluidez, memoria y carga antes de pasarlos al mapa.
@main
struct LaboratorioApp: App {
    var body: some Scene {
        WindowGroup {
            MapaPrincipal()
                .tint(Color.accentColor)
        }
    }
}
