import Foundation
import Observation

@MainActor
@Observable
final class LoginViewModel {
    enum Method: Equatable { case oidc, password, token }

    let server: ResolvedServer
    private(set) var inProgress: Method?
    var errorMessage: String?

    var username = ""
    var password = ""
    var apiToken = ""

    init(server: ResolvedServer) {
        self.server = server
    }

    var isBusy: Bool { inProgress != nil }
    var canSubmitPassword: Bool { !isBusy && !username.isEmpty && !password.isEmpty }
    var canSubmitToken: Bool { !isBusy && !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var flow: SignInFlow { SignInFlow(serverURL: server.url, appInfo: server.info) }

    func signInWithOIDC(session: AppSession) async {
        await run(.oidc, session: session) {
            try await self.flow.signInWithOIDC()
        }
    }

    func signInWithPassword(session: AppSession) async {
        await run(.password, session: session) {
            try await self.flow.signIn(username: self.username, password: self.password)
        }
    }

    func signInWithToken(session: AppSession) async {
        await run(.token, session: session) {
            try await self.flow.signIn(apiToken: self.apiToken)
        }
    }

    private func run(_ method: Method, session: AppSession, _ work: () async throws -> SignInResult) async {
        guard !isBusy else { return }
        inProgress = method
        errorMessage = nil
        defer { inProgress = nil }
        do {
            let result = try await work()
            password = ""
            apiToken = ""
            session.signIn(with: result)
        } catch OIDCError.cancelled {
            // User closed the browser sheet: no error message.
        } catch let error as MealieError where error.isCancelled {
            // Ignore.
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? MealieError.wrap(error).errorDescription
            // Start the retry from an empty field (shows the placeholder) instead of hidden dots.
            if method == .password { password = "" }
        }
    }
}
