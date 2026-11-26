import SwiftUI

/// Map Lab: app de pruebas del mapa propio en un iPhone real.
/// Cada experimento abre el mismo mapa con una configuración distinta, para comparar
/// legibilidad, fluidez, memoria y tiempo de carga antes de llevar algo a otro proyecto.
@main
struct LaboratorioApp: App {
    var body: some Scene {
        WindowGroup {
            ListaExperimentos()
                .tint(Color.accentColor)
        }
    }
}
