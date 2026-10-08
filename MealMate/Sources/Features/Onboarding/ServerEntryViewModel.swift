import Foundation
import Observation

@MainActor
@Observable
final class ServerEntryViewModel {
    var address: String = ""
    private(set) var isChecking = false
    private(set) var errorMessage: String?
    /// Set when validation succeeded; the view pushes the login screen.
    var resolved: ResolvedServer?

    var canContinue: Bool {
        !isChecking && !address.trimmingCharacters(in: .whitespaces).isEmpty
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
}
