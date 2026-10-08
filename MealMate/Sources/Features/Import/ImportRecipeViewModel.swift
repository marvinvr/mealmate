import Foundation
import Observation

/// State of the "Import Recipe" sheet: URL import (with duplicate check) and,
/// when the server has an AI provider, AI import from text or photos.
@MainActor
@Observable
final class ImportRecipeViewModel {
    enum Phase: Equatable {
        case editing
        /// Waiting for Mealie. `source` is the website host or "AI".
        case importing(source: String)
        /// A recipe from this exact URL already exists.
        case duplicate(existing: RecipeSummary, url: URL)
        case failed(RecipeImportProblem)
        case imported(Recipe)
    }

    var urlText = ""
    private(set) var phase: Phase = .editing
    /// `nil` until loaded (or when the server doesn't answer): AI options stay hidden.
    private(set) var aiSettings: AIProviderSettings?

    @ObservationIgnored private let mealie: MealieService
    @ObservationIgnored private var importer: RecipeImporter { RecipeImporter(service: mealie) }

    init(mealie: MealieService, initialURL: String? = nil) {
        self.mealie = mealie
        self.urlText = initialURL ?? ""
    }

    var normalizedURL: URL? { RecipeURLExtractor.normalizedURL(from: urlText) }
    var canImport: Bool { normalizedURL != nil && !isBusy }
    var isBusy: Bool {
        if case .importing = phase { return true }
        return false
    }

    var isAIAvailable: Bool { aiSettings?.isAIAvailable == true }
    var isImageImportAvailable: Bool { aiSettings?.isImageImportAvailable == true }

    var problem: RecipeImportProblem? {
        if case .failed(let problem) = phase { return problem }
        return nil
    }

    var importedRecipe: Recipe? {
        if case .imported(let recipe) = phase { return recipe }
        return nil
    }

    // MARK: Actions

    /// Hides AI import unless the server explicitly reports a provider.
    func loadAISettings() async {
        aiSettings = try? await mealie.aiProviderSettings()
    }

    /// Accepts pasted text: uses the first link in it.
    func paste(_ strings: [String]) {
        guard let text = strings.first else { return }
        urlText = RecipeURLExtractor.firstWebURL(in: text)?.absoluteString ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .failed = phase { phase = .editing }
    }

    func editURL() {
        if case .failed = phase { phase = .editing }
        if case .duplicate = phase { phase = .editing }
    }

    func importFromURL(allowDuplicate: Bool = false) async {
        guard let url = normalizedURL, !isBusy else { return }
        urlText = url.absoluteString
        phase = .importing(source: url.host() ?? url.absoluteString)
        if !allowDuplicate, let existing = await importer.existingRecipe(importedFrom: url) {
            phase = .duplicate(existing: existing, url: url)
            return
        }
        do {
            let recipe = try await importer.importRecipe(from: url, includeOrganizers: ImportPreferences.includeOrganizers)
            phase = .imported(recipe)
        } catch let problem as RecipeImportProblem {
            phase = problem.error?.isCancelled == true ? .editing : .failed(problem)
        } catch {
            phase = .failed(RecipeImportProblem(MealieError.wrap(error)))
        }
    }

    /// `POST /api/recipes/create/ai` from pasted recipe text and/or photos (JPEG).
    func importWithAI(text: String, images: [Data] = []) async {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAIAvailable, !isBusy, !content.isEmpty || !images.isEmpty else { return }
        phase = .importing(source: "AI")
        do {
            let request = RecipeAIImportRequest(content: content.isEmpty ? nil : content,
                                                createNewOrganizers: ImportPreferences.includeOrganizers)
            let slug = try await mealie.createRecipeWithAI(request, images: images)
            let recipe = (try? await mealie.recipe(slug: slug)) ?? Recipe(id: slug, slug: slug, name: nil)
            phase = .imported(recipe)
        } catch {
            let wrapped = MealieError.wrap(error)
            phase = wrapped.isCancelled ? .editing : .failed(RecipeImportProblem(wrapped))
        }
    }

    // MARK: Debug

    #if DEBUG
    /// Fixed states for screenshots (`import-state/<state>` routes).
    func debugShow(_ phase: Phase, ai: Bool = false) {
        self.phase = phase
        if ai {
            aiSettings = AIProviderSettings(aiEnabled: true, imageProviderEnabled: true)
        }
    }
    #endif
}
