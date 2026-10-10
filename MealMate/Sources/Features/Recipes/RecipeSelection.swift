import Foundation

/// Multi-select on the Recipes tab. Select in the context menu starts it with one recipe; taps toggle.
struct RecipeSelectionState: Equatable {
    var isActive = false
    /// Selected recipes in the order they were added.
    private(set) var recipes: [RecipeSummary] = []
    private var ids: Set<String> = []
    /// Bumps on every change so the screen can play a selection haptic.
    var changeCount = 0

    var count: Int { recipes.count }
    var isEmpty: Bool { recipes.isEmpty }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    /// True when every loaded recipe is selected (the toolbar shows Deselect All).
    func covers(_ loaded: [RecipeSummary]) -> Bool {
        let loadedIDs = Set(loaded.map(\.id))
        return !loadedIDs.isEmpty && loadedIDs.isSubset(of: ids)
    }

    mutating func begin(with recipe: RecipeSummary) {
        isActive = true
        recipes = [recipe]
        ids = [recipe.id]
        changeCount += 1
    }

    mutating func toggle(_ recipe: RecipeSummary) {
        guard isActive else {
            begin(with: recipe)
            return
        }
        if ids.contains(recipe.id) {
            recipes.removeAll { $0.id == recipe.id }
            ids.remove(recipe.id)
        } else {
            recipes.append(recipe)
            ids.insert(recipe.id)
        }
        changeCount += 1
    }

    /// Selects every loaded recipe, or clears the selection when they already all are.
    mutating func toggleAll(loaded: [RecipeSummary]) {
        if covers(loaded) {
            recipes.removeAll()
            ids.removeAll()
        } else {
            for recipe in loaded where ids.insert(recipe.id).inserted {
                recipes.append(recipe)
            }
        }
        changeCount += 1
    }

    mutating func end() {
        guard isActive || !recipes.isEmpty else { return }
        isActive = false
        recipes.removeAll()
        ids.removeAll()
        changeCount += 1
    }
}

/// What a bulk run did. Built so a partial failure is part of the value, not an optional log line.
struct RecipeBulkResult: Equatable, Sendable {
    struct Failure: Equatable, Sendable, Identifiable {
        var recipeID: String
        var recipeName: String
        var message: String
        var id: String { recipeID }
    }

    /// Past tense, title case: "Sent", "Added", "Planned".
    var successVerb: String
    /// Past participle after "couldn’t be": "sent", "added", "planned".
    var failureVerb: String
    /// Prepositional phrase, e.g. `to “Export”` or `for dinner today`.
    var destinationPhrase: String
    var succeededNames: [String]
    var failures: [Failure]
    /// Selected recipes the run never reached because it was cancelled.
    var notAttempted: Int

    var succeededCount: Int { succeededNames.count }
    var failureCount: Int { failures.count }

    /// One message shared by every failure (a single bulk request that rejected the whole set).
    var sharedFailureMessage: String? {
        guard failures.count > 1, let message = failures.first?.message, failures.allSatisfy({ $0.message == message }) else { return nil }
        return message
    }

    var title: String {
        if succeededCount == 0, failureCount == 0 { return "Cancelled" }
        if failureCount == 0, notAttempted == 0 { return "Done" }
        if succeededCount == 0, notAttempted == 0 { return "Failed" }
        return "Partly Done"
    }

    /// One or two sentences. Names of individual failures stay in `failures` for the list under this.
    var summary: String {
        if succeededCount == 0, failureCount == 0 {
            return "Nothing was \(failureVerb) \(destinationPhrase)."
        }
        var sentences: [String] = []
        if succeededCount == 1, let name = succeededNames.first {
            sentences.append("\(successVerb) “\(name)” \(destinationPhrase).")
        } else if succeededCount > 1 {
            sentences.append("\(successVerb) \(succeededCount) recipes \(destinationPhrase).")
        }
        if failureCount == 1, let failure = failures.first {
            let whereTo = succeededCount == 0 ? " \(destinationPhrase)" : ""
            sentences.append("“\(failure.recipeName)” couldn’t be \(failureVerb)\(whereTo).")
        } else if failureCount > 1 {
            let whereTo = succeededCount == 0 ? " \(destinationPhrase)" : ""
            sentences.append("\(failureCount) recipes couldn’t be \(failureVerb)\(whereTo).")
        }
        if notAttempted == 1 {
            sentences.append("1 recipe wasn’t tried.")
        } else if notAttempted > 1 {
            sentences.append("\(notAttempted) recipes weren’t tried.")
        }
        return sentences.joined(separator: " ")
    }
}

/// Runs one operation per selected recipe, or one operation for the whole set, and keeps every failure.
@MainActor
@Observable
final class RecipeBulkJob: Identifiable {
    enum Phase: Equatable {
        case running(done: Int, total: Int, current: String)
        case finished(RecipeBulkResult)
    }

    let id = UUID()
    /// Navigation title while the run is in progress ("Sending", "Adding", "Planning").
    let progressTitle: String
    private(set) var phase: Phase
    /// Bumps when the run finishes so the sheet can play a single haptic.
    private(set) var finishCount = 0
    private(set) var finishIsError = false

    @ObservationIgnored private let recipes: [RecipeSummary]
    @ObservationIgnored private let successVerb: String
    @ObservationIgnored private let failureVerb: String
    @ObservationIgnored private let destinationPhrase: String
    @ObservationIgnored private var task: Task<Void, Never>?

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    /// A job that does not start work. DEBUG routes use it to show progress or a finished summary.
    init(progressTitle: String, phase: Phase, successVerb: String, failureVerb: String, destinationPhrase: String, recipes: [RecipeSummary] = []) {
        self.progressTitle = progressTitle
        self.phase = phase
        self.successVerb = successVerb
        self.failureVerb = failureVerb
        self.destinationPhrase = destinationPhrase
        self.recipes = recipes
        if case .finished(let result) = phase {
            finishIsError = result.failureCount > 0
        }
    }

    /// `operation` is called once per recipe, in order. A failure is recorded and the rest still run.
    static func each(
        progressTitle: String,
        recipes: [RecipeSummary],
        successVerb: String,
        failureVerb: String,
        destinationPhrase: String,
        operation: @escaping @MainActor (RecipeSummary) async throws -> Void
    ) -> RecipeBulkJob {
        let current = recipes.first?.displayName ?? ""
        let job = RecipeBulkJob(
            progressTitle: progressTitle,
            phase: .running(done: 0, total: recipes.count, current: current),
            successVerb: successVerb,
            failureVerb: failureVerb,
            destinationPhrase: destinationPhrase,
            recipes: recipes
        )
        job.task = Task { @MainActor in
            await job.runEach(operation)
        }
        return job
    }

    /// One request for the whole selection (the shopping-list bulk endpoint).
    /// If it throws, every recipe is a failure: a bulk request can't say which recipe was accepted.
    static func batch(
        progressTitle: String,
        recipes: [RecipeSummary],
        successVerb: String,
        failureVerb: String,
        destinationPhrase: String,
        operation: @escaping @MainActor () async throws -> Void
    ) -> RecipeBulkJob {
        let current = recipes.first?.displayName ?? ""
        let job = RecipeBulkJob(
            progressTitle: progressTitle,
            phase: .running(done: 0, total: recipes.count, current: current),
            successVerb: successVerb,
            failureVerb: failureVerb,
            destinationPhrase: destinationPhrase,
            recipes: recipes
        )
        job.task = Task { @MainActor in
            await job.runBatch(operation)
        }
        return job
    }

    /// Stops before the next recipe. Recipes already sent stay sent and show up in the summary.
    func cancel() {
        guard isRunning else { return }
        if task == nil {
            finish(succeeded: [], failures: [], notAttempted: recipes.isEmpty ? phaseTotal : recipes.count)
            return
        }
        task?.cancel()
    }

    private var phaseTotal: Int {
        if case .running(_, let total, _) = phase { return total }
        return recipes.count
    }

    private func runEach(_ operation: @escaping @MainActor (RecipeSummary) async throws -> Void) async {
        guard !recipes.isEmpty else {
            finish(succeeded: [], failures: [], notAttempted: 0)
            return
        }
        var succeeded: [String] = []
        var failures: [RecipeBulkResult.Failure] = []
        for (index, recipe) in recipes.enumerated() {
            if Task.isCancelled {
                finish(succeeded: succeeded, failures: failures, notAttempted: recipes.count - index)
                return
            }
            phase = .running(done: index, total: recipes.count, current: recipe.displayName)
            do {
                try await operation(recipe)
                succeeded.append(recipe.displayName)
            } catch {
                let wrapped = MealieError.wrap(error)
                if wrapped.isCancelled || Task.isCancelled {
                    finish(succeeded: succeeded, failures: failures, notAttempted: recipes.count - index)
                    return
                }
                failures.append(.init(recipeID: recipe.id, recipeName: recipe.displayName,
                                       message: wrapped.errorDescription ?? "Please try again."))
            }
        }
        finish(succeeded: succeeded, failures: failures, notAttempted: 0)
    }

    private func runBatch(_ operation: @escaping @MainActor () async throws -> Void) async {
        guard !recipes.isEmpty else {
            finish(succeeded: [], failures: [], notAttempted: 0)
            return
        }
        phase = .running(done: 0, total: recipes.count, current: recipes.first?.displayName ?? "")
        do {
            try await operation()
            if Task.isCancelled {
                finish(succeeded: [], failures: [], notAttempted: recipes.count)
                return
            }
            finish(succeeded: recipes.map(\.displayName), failures: [], notAttempted: 0)
        } catch {
            let wrapped = MealieError.wrap(error)
            if wrapped.isCancelled || Task.isCancelled {
                finish(succeeded: [], failures: [], notAttempted: recipes.count)
                return
            }
            let message = wrapped.errorDescription ?? "Please try again."
            let failures = recipes.map {
                RecipeBulkResult.Failure(recipeID: $0.id, recipeName: $0.displayName, message: message)
            }
            finish(succeeded: [], failures: failures, notAttempted: 0)
        }
    }

    private func finish(succeeded: [String], failures: [RecipeBulkResult.Failure], notAttempted: Int) {
        let result = RecipeBulkResult(
            successVerb: successVerb,
            failureVerb: failureVerb,
            destinationPhrase: destinationPhrase,
            succeededNames: succeeded,
            failures: failures,
            notAttempted: notAttempted
        )
        phase = .finished(result)
        finishIsError = result.failureCount > 0 || (result.succeededCount == 0 && result.notAttempted > 0)
        finishCount += 1
    }
}
