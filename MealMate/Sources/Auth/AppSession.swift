import Foundation
import Observation

/// The signed-in state of the app: server, token, current user.
///
/// Owned by `MealMateApp` and available everywhere via
/// `@Environment(AppSession.self)`. Feature code usually only needs
/// `@Environment(\.mealie)` (the signed-in `MealieService`).
@MainActor
@Observable
final class AppSession {
    enum Phase: Equatable {
        /// Show onboarding (server entry → login).
        case signedOut
        case signedIn
    }

    private(set) var phase: Phase = .signedOut
    /// Signed-in API client (`.unconfigured` while signed out).
    private(set) var service: MealieService = .unconfigured
    private(set) var serverURL: URL?
    private(set) var currentUser: User?
    private(set) var appInfo: AppInfo?
    /// Set when the session ended because the server rejected the token (401),
    /// so onboarding can explain why.
    var signedOutReason: String?

    @ObservationIgnored private var mintedTokenID: Int?
    /// Debug harness sessions aren't persisted (see `DebugLaunch`).
    @ObservationIgnored private(set) var isEphemeral = false

    var isSignedIn: Bool { phase == .signedIn }

    init() {}

    // MARK: Launch

    /// Restores the stored session instantly (cached user/app info) and
    /// revalidates in the background.
    func restore() {
        guard let stored = CredentialStore.load() else { return }
        activate(serverURL: stored.serverURL, token: stored.token)
        mintedTokenID = stored.mintedTokenID
        currentUser = CredentialStore.cachedUser
        appInfo = CredentialStore.cachedAppInfo
        Task { await refresh() }
    }

    /// Reloads the current user and server info. A 401 signs out (via the
    /// service's `onUnauthorized`); network errors keep the cached state.
    func refresh() async {
        guard isSignedIn else { return }
        let service = self.service
        async let user = try? service.currentUser()
        async let info = try? service.appInfo()
        if let user = await user {
            currentUser = user
            if !isEphemeral { CredentialStore.cachedUser = user }
        }
        if let info = await info {
            appInfo = info
            if !isEphemeral { CredentialStore.cachedAppInfo = info }
        }
    }

    // MARK: Sign in / out

    /// Completes any sign-in method and persists the session.
    func signIn(with result: SignInResult) {
        CredentialStore.save(StoredCredentials(serverURL: result.serverURL, token: result.token, mintedTokenID: result.mintedTokenID))
        CredentialStore.lastServerURL = result.serverURL
        CredentialStore.cachedUser = result.user
        CredentialStore.cachedAppInfo = result.appInfo
        isEphemeral = false
        mintedTokenID = result.mintedTokenID
        activate(serverURL: result.serverURL, token: result.token)
        currentUser = result.user
        appInfo = result.appInfo
        signedOutReason = nil
        if result.appInfo == nil { Task { await refresh() } }
    }

    /// Signs in without persisting anything (DEBUG test harness).
    func signInEphemeral(serverURL: URL, token: String) {
        isEphemeral = true
        activate(serverURL: serverURL, token: token)
        Task { await refresh() }
    }

    /// Signs out: revokes the API token MealMate minted (best effort), clears
    /// stored credentials, cached responses and images, and cooking progress.
    ///
    /// Only a token MealMate minted itself (`mintedTokenID`) is revoked; a pasted
    /// API token belongs to the user and is never deleted on the server.
    func signOut(reason: String? = nil) {
        let previousService = service
        let tokenID = mintedTokenID
        if !isEphemeral {
            CredentialStore.clear()
            if let tokenID, reason == nil {
                Task.detached { try? await previousService.deleteAPIToken(id: tokenID) }
            }
        }
        Task {
            await ResponseCache.shared.removeAll()
            await RecipeImageLoader.shared.removeAll()
        }
        CookingSessionStore.shared.removeAll()
        phase = .signedOut
        service = .unconfigured
        currentUser = nil
        appInfo = nil
        mintedTokenID = nil
        isEphemeral = false
        signedOutReason = reason
    }

    /// Shows onboarding without touching stored credentials (DEBUG routes `onboarding`/`login`).
    func showOnboardingWithoutSigningOut() {
        phase = .signedOut
        service = .unconfigured
    }

    // MARK: Private

    private func activate(serverURL: URL, token: String) {
        self.serverURL = serverURL
        service = MealieService(baseURL: serverURL, token: token) { [weak self] in
            Task { @MainActor in self?.handleUnauthorized(token: token) }
        }
        phase = .signedIn
    }

    /// Ignores late 401s from a previous session's token.
    private func handleUnauthorized(token: String) {
        guard isSignedIn, service.token == token else { return }
        signOut(reason: MealieError.unauthorized.errorDescription)
    }
}
