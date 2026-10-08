import SwiftUI

extension EnvironmentValues {
    /// The signed-in Mealie client. Inject-only from `RootView`; read with
    /// `@Environment(\.mealie) private var mealie` in feature views and pass it
    /// to view models.
    @Entry var mealie: MealieService = .unconfigured
}
