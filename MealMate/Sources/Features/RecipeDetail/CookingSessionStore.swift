import Foundation
import Observation

/// Per-recipe cooking state shared by the recipe detail and cook mode: chosen servings,
/// checked-off ingredients and the current cook-mode step. Survives navigation and app
/// relaunches for 12 hours (UserDefaults), so a half-cooked recipe keeps its check marks.
@MainActor
@Observable
final class CookingSessionStore {
    static let shared = CookingSessionStore()

    struct Session: Codable, Hashable, Sendable {
        /// `nil` = the recipe's own servings.
        var servings: Double?
        var checkedIngredients: Set<Int> = []
        var currentStep = 0
        var updatedAt = Date()
    }

    private(set) var sessions: [String: Session] = [:]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey = "cooking.sessions"
    private static let lifetime: TimeInterval = 12 * 60 * 60

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode([String: Session].self, from: data) {
            sessions = stored.filter { Date().timeIntervalSince($0.value.updatedAt) < Self.lifetime }
        }
    }

    func session(for recipeID: String) -> Session {
        sessions[recipeID] ?? Session()
    }

    func update(_ recipeID: String, _ change: (inout Session) -> Void) {
        var session = session(for: recipeID)
        change(&session)
        session.updatedAt = Date()
        sessions[recipeID] = session
        save()
    }

    func toggleIngredient(_ index: Int, recipeID: String) {
        update(recipeID) { session in
            if session.checkedIngredients.contains(index) {
                session.checkedIngredients.remove(index)
            } else {
                session.checkedIngredients.insert(index)
            }
        }
    }

    /// Clears check marks and the cook-mode position (keeps the chosen servings).
    func reset(_ recipeID: String) {
        update(recipeID) { session in
            session.checkedIngredients = []
            session.currentStep = 0
        }
    }

    /// Forgets every recipe's progress (sign-out).
    func removeAll() {
        sessions = [:]
        defaults.removeObject(forKey: storageKey)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
