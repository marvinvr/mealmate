import SwiftUI

/// Onboarding: server address → sign-in method.
struct OnboardingFlowView: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var model = ServerEntryViewModel()
    @State private var path: [ResolvedServer] = []

    var body: some View {
        NavigationStack(path: $path) {
            ServerEntryView(model: model)
                .navigationDestination(for: ResolvedServer.self) { server in
                    LoginView(server: server)
                }
        }
        .onChange(of: model.resolved) { _, resolved in
            if let resolved { path = [resolved] }
        }
        .onChange(of: path) { _, path in
            if path.isEmpty { model.resolved = nil }
        }
        .task {
            if let prefill = router.onboardingPrefill {
                model.address = prefill.serverAddress
                router.onboardingPrefill = nil
                if let resolved = prefill.resolved {
                    path = [resolved]
                } else if prefill.autoContinue {
                    await model.resolve()
                }
            } else if model.address.isEmpty, let last = CredentialStore.lastServerURL {
                model.address = last.absoluteString
            }
        }
    }
}

enum Onboarding {
    /// Top padding of the onboarding screens: fixed on iPhone; on tall screens (iPad) the
    /// 520 pt column moves down towards the optical centre instead of hugging the top.
    static func topPadding(minimum: CGFloat, height: CGFloat, isRegularWidth: Bool) -> CGFloat {
        guard isRegularWidth, height > 700 else { return minimum }
        return max(minimum, height * 0.16)
    }
}
