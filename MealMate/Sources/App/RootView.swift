import SwiftUI

/// Switches between onboarding and the signed-in tab shell.
struct RootView: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            switch session.phase {
            case .signedOut:
                OnboardingFlowView()
                    .transition(.opacity)
            case .signedIn:
                MainTabView()
                    .environment(\.mealie, session.service)
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: session.phase)
        .onChange(of: session.phase) { _, phase in
            if phase == .signedOut { router.reset() }
        }
        #if DEBUG
        .debugWindowWidth()
        #endif
        .onOpenURL { url in
            guard let route = AppRoute(url: url) else { return }
            route.apply(router: router, session: session)
        }
    }
}
