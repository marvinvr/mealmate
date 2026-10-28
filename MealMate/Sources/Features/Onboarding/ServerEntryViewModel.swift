import Foundation
import Observation

@MainActor
@Observable
final class ServerEntryViewModel {
    var address: String = ""
    private(set) var isChecking = false
    private(set) var isConnectingDemo = false
    private(set) var errorMessage: String?
    /// Set when validation succeeded; the view pushes the login screen.
    var resolved: ResolvedServer?

    var canContinue: Bool {
        !isChecking && !isConnectingDemo && !address.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Tries each candidate URL (`https` then `http` without a scheme) and
    /// accepts the first that answers `/api/app/about` like Mealie.
    func resolve() async {
        let candidates = ServerAddress.candidates(for: address)
        guard !candidates.isEmpty else {
            errorMessage = MealieError.invalidServerURL.errorDescription
            return
        }
        isChecking = true
        errorMessage = nil
        defer { isChecking = false }

        var errors: [MealieError] = []
        for url in candidates {
            do {
                let info = try await MealieService(baseURL: url).appInfo()
                resolved = ResolvedServer(url: url, info: info)
                return
            } catch {
                let error = MealieError.wrap(error)
                if error.isCancelled { return }
                errors.append(error)
            }
        }
        // Prefer the most specific explanation.
        let best = errors.first { $0 == .notMealie } ?? errors.last
        errorMessage = best?.errorDescription
    }

    /// Signs in to Mealie's public demo server with its published demo account. Keeps the
    /// short-lived session token: no API token is minted on the shared account.
    func connectToDemo(session: AppSession) async {
        guard !isChecking, !isConnectingDemo else { return }
        isConnectingDemo = true
        errorMessage = nil
        defer { isConnectingDemo = false }
        do {
            let info = try await MealieService(baseURL: DemoServer.url).appInfo()
            let result = try await SignInFlow(serverURL: DemoServer.url, appInfo: info)
                .signIn(username: DemoServer.username, password: DemoServer.password, mintLongLivedToken: false)
            let lastServer = CredentialStore.lastServerURL
            session.signIn(with: result)
            // Don't prefill the demo address after signing out.
            CredentialStore.lastServerURL = lastServer
        } catch {
            if MealieError.wrap(error).isCancelled { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? MealieError.wrap(error).errorDescription
        }
    }
}

/// Mealie's public demo (credentials shown on its login page and in the Mealie docs).
enum DemoServer {
    static let url = URL(string: "https://demo.mealie.io")!
    static let username = "changeme@example.com"
    static let password = "MyPassword"
}
