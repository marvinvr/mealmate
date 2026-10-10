import Foundation
import Testing
@testable import MealMate

struct RecipeSelectionStateTests {
    private func recipe(_ id: String, _ name: String) -> RecipeSummary {
        RecipeSummary(id: id, slug: id, name: name)
    }

    @Test func longPressStartsWithThatRecipe() {
        var selection = RecipeSelectionState()
        selection.begin(with: recipe("1", "Soup"))
        #expect(selection.isActive)
        #expect(selection.count == 1)
        #expect(selection.contains("1"))
        #expect(selection.recipes.map(\.displayName) == ["Soup"])
    }

    @Test func tapsToggleAndSelectAllCoversLoadedRecipes() {
        var selection = RecipeSelectionState()
        let soup = recipe("1", "Soup")
        let bread = recipe("2", "Bread")
        let curry = recipe("3", "Curry")
        selection.begin(with: soup)
        selection.toggle(bread)
        selection.toggle(soup)
        #expect(selection.recipes.map(\.id) == ["2"])
        selection.toggleAll(loaded: [soup, bread, curry])
        #expect(selection.covers([soup, bread, curry]))
        #expect(selection.count == 3)
        selection.toggleAll(loaded: [soup, bread, curry])
        #expect(selection.isEmpty)
        #expect(selection.isActive)
    }

    @Test func endClearsTheSelection() {
        var selection = RecipeSelectionState()
        selection.begin(with: recipe("1", "Soup"))
        selection.end()
        #expect(selection.isActive == false)
        #expect(selection.isEmpty)
    }
}

struct RecipeBulkResultTests {
    private func result(
        succeeded: [String] = [],
        failures: [(String, String)] = [],
        notAttempted: Int = 0
    ) -> RecipeBulkResult {
        RecipeBulkResult(
            successVerb: "Sent",
            failureVerb: "sent",
            destinationPhrase: "to “Export”",
            succeededNames: succeeded,
            failures: failures.map { .init(recipeID: $0.0, recipeName: $0.0, message: $0.1) },
            notAttempted: notAttempted
        )
    }

    @Test func successCopy() {
        #expect(result(succeeded: ["Soup"]).summary == "Sent “Soup” to “Export”.")
        #expect(result(succeeded: ["Soup"]).title == "Done")
        let many = result(succeeded: ["Soup", "Bread"])
        #expect(many.summary == "Sent 2 recipes to “Export”.")
        #expect(many.title == "Done")
    }

    @Test func partialFailureIsPartOfTheSummary() {
        let partial = result(succeeded: ["Soup", "Bread"], failures: [("Curry", "Nope"), ("Stew", "Offline")])
        #expect(partial.title == "Partly Done")
        #expect(partial.summary == "Sent 2 recipes to “Export”. 2 recipes couldn’t be sent.")
        #expect(partial.failureCount == 2)
        #expect(partial.sharedFailureMessage == nil)
    }

    @Test func everyFailureIsKeptWhenNothingSucceeds() {
        let one = result(failures: [("Soup", "Nope")])
        #expect(one.title == "Failed")
        #expect(one.summary == "“Soup” couldn’t be sent to “Export”.")
        let many = result(failures: [("Soup", "Nope"), ("Bread", "Nope")])
        #expect(many.summary == "2 recipes couldn’t be sent to “Export”.")
        #expect(many.sharedFailureMessage == "Nope")
    }

    @Test func cancellationSaysWhatWasNotTried() {
        let stopped = result(succeeded: ["Soup"], notAttempted: 3)
        #expect(stopped.title == "Partly Done")
        #expect(stopped.summary == "Sent “Soup” to “Export”. 3 recipes weren’t tried.")
        let none = result(notAttempted: 4)
        #expect(none.title == "Cancelled")
        #expect(none.summary == "Nothing was sent to “Export”.")
    }
}

@MainActor
struct RecipeBulkJobTests {
    private func recipe(_ id: String) -> RecipeSummary {
        RecipeSummary(id: id, slug: id, name: id)
    }

    @Test func eachKeepsGoingAfterAFailure() async {
        let recipes = [recipe("Soup"), recipe("Bread"), recipe("Curry")]
        let job = RecipeBulkJob.each(
            progressTitle: "Sending",
            recipes: recipes,
            successVerb: "Sent",
            failureVerb: "sent",
            destinationPhrase: "to “Export”"
        ) { recipe in
            if recipe.id == "Bread" { throw MealieError.server(status: 500, message: "Nope") }
        }
        let result = await finishedResult(job)
        #expect(result.succeededNames == ["Soup", "Curry"])
        #expect(result.failures.map(\.recipeName) == ["Bread"])
        #expect(result.failures.first?.message == "Nope")
        #expect(result.notAttempted == 0)
    }

    @Test func batchFailureFailsTheWholeSet() async {
        let recipes = [recipe("Soup"), recipe("Bread")]
        let job = RecipeBulkJob.batch(
            progressTitle: "Adding",
            recipes: recipes,
            successVerb: "Added",
            failureVerb: "added",
            destinationPhrase: "to “Groceries”"
        ) {
            throw MealieError.unreachable("offline")
        }
        let result = await finishedResult(job)
        #expect(result.succeededCount == 0)
        #expect(result.failureCount == 2)
        #expect(result.sharedFailureMessage != nil)
        #expect(result.title == "Failed")
    }

    @Test func cancelSkipsRecipesNotStarted() async {
        let recipes = [recipe("Soup"), recipe("Bread"), recipe("Curry")]
        let job = RecipeBulkJob.each(
            progressTitle: "Sending",
            recipes: recipes,
            successVerb: "Sent",
            failureVerb: "sent",
            destinationPhrase: "to “Export”"
        ) { recipe in
            if recipe.id == "Bread" { throw CancellationError() }
        }
        let result = await finishedResult(job)
        #expect(result.succeededNames == ["Soup"])
        #expect(result.failures.isEmpty)
        #expect(result.notAttempted == 2)
        #expect(result.title == "Partly Done")
    }

    private func finishedResult(_ job: RecipeBulkJob) async -> RecipeBulkResult {
        for _ in 0..<50 {
            if case .finished(let result) = job.phase { return result }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The bulk job did not finish")
        return RecipeBulkResult(successVerb: "", failureVerb: "", destinationPhrase: "", succeededNames: [], failures: [], notAttempted: 0)
    }
}
