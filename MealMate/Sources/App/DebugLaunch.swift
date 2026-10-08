#if DEBUG
import Foundation

/// DEBUG-only test harness (compiled out of Release).
///
/// - `MEALMATE_TEST_SERVER` + `MEALMATE_TEST_TOKEN` env vars: sign in with the
///   token at launch without persisting anything.
/// - `-MealMateRoute <route>` launch argument: open a screen directly, see
///   `AppRoute.registry`. `onboarding` / `login` show onboarding without
///   touching stored credentials (no token needed).
///
/// `scripts/screenshot.sh` drives this; see scripts/README.md.
@MainActor
enum DebugLaunch {
    /// Returns `true` when the harness configured the session (skip normal restore).
    static func configure(session: AppSession, router: AppRouter) -> Bool {
        let environment = ProcessInfo.processInfo.environment
        let server = environment["MEALMATE_TEST_SERVER"].flatMap { $0.isEmpty ? nil : $0 }
        let token = environment["MEALMATE_TEST_TOKEN"].flatMap { $0.isEmpty ? nil : $0 }
        let routeString = UserDefaults.standard.string(forKey: "MealMateRoute")
        let route = routeString.flatMap(AppRoute.init(string:))
        if let routeString, route == nil {
            mealieLogger.error("Unknown -MealMateRoute '\(routeString, privacy: .public)'")
        }

        switch route {
        case .onboarding:
            session.showOnboardingWithoutSigningOut()
            router.onboardingPrefill = server.map { .init(serverAddress: $0, autoContinue: false) }
            return true
        case .login, .loginOIDC:
            session.showOnboardingWithoutSigningOut()
            router.autoStartOIDC = route == .loginOIDC
            let address = server ?? CredentialStore.lastServerURL?.absoluteString
            router.onboardingPrefill = address.map { .init(serverAddress: $0, autoContinue: true) }
            return true
        case .signOut:
            session.restore()
            session.signOut()
            return true
        default:
            break
        }

        guard let server, let token, let url = ServerAddress.candidates(for: server).first else {
            route?.apply(router: router, session: session)
            return false
        }
        session.signInEphemeral(serverURL: url, token: token)
        route?.apply(router: router, session: session)
        return true
    }
}
#endif
