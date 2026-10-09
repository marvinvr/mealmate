import Foundation
import Observation
import UIKit

/// Create a recipe by hand or edit an existing one.
///
/// Saving: new recipes are created with `POST /api/recipes` (name only), then
/// everything else is sent with one `PATCH` (see `RecipeDraft.patch`), then the
/// photo is uploaded. Existing recipes only PATCH the fields that changed.
@MainActor
@Observable
final class RecipeEditorViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// A photo change that is uploaded on save.
    enum PendingImage: Equatable {
        /// JPEG ready for `PUT /api/recipes/{slug}/image`.
        case photo(Data)
        /// Mealie downloads it (`POST /api/recipes/{slug}/image`).
        case url(URL)
    }

    var draft = RecipeDraft()
    private(set) var loadState: LoadState
    /// Recipe as stored on the server (`nil` while creating a new one).
    private(set) var original: Recipe?
    var pendingImage: PendingImage?
    /// Preview for `.photo` (decoded once).
    private(set) var pendingPreview: UIImage?
    private(set) var isPreparingPhoto = false
    private(set) var isSaving = false
    var errorMessage: String?

    @ObservationIgnored private let mealie: MealieService
    @ObservationIgnored private let slugToLoad: String?
    @ObservationIgnored private var initialDraft = RecipeDraft()
    /// Slug of a recipe this editor already created whose details failed to
    /// save; retrying patches it instead of creating a second one.
    @ObservationIgnored private var createdSlug: String?

    /// New recipe.
    init(mealie: MealieService) {
        self.mealie = mealie
        self.slugToLoad = nil
        self.loadState = .loaded
        // Start with one empty line each so typing can begin right away (empty lines aren't saved).
        draft.ingredients = [RecipeDraft.IngredientLine(text: "")]
        draft.steps = [RecipeDraft.StepLine(text: "")]
        initialDraft = draft
    }

    /// Edit `recipe` (already loaded).
    init(mealie: MealieService, recipe: Recipe) {
        self.mealie = mealie
        self.slugToLoad = nil
        self.loadState = .loaded
        setOriginal(recipe)
    }

    /// Edit the recipe with `slug` (loads it first).
    init(mealie: MealieService, slug: String) {
        self.mealie = mealie
        self.slugToLoad = slug
        self.loadState = .loading
    }

    var isNew: Bool { original == nil }
    var isDirty: Bool { draft != initialDraft || pendingImage != nil }
    var canSave: Bool { draft.canSave && !isSaving && !isPreparingPhoto && loadState == .loaded }

    var currentImageURL: URL? {
        guard let original else { return nil }
        return mealie.imageURL(for: original, size: .min)
    }

    // MARK: Loading

    func load() async {
        guard let slug = slugToLoad, original == nil else { return }
        loadState = .loading
        do {
            setOriginal(try await mealie.recipe(slug: slug))
            loadState = .loaded
        } catch {
            let wrapped = MealieError.wrap(error)
            guard !wrapped.isCancelled else { return }
            loadState = .failed(wrapped.errorDescription ?? "The recipe couldn’t be loaded.")
        }
    }

    private func setOriginal(_ recipe: Recipe) {
        original = recipe
        draft = RecipeDraft(recipe: recipe)
        initialDraft = draft
    }

    // MARK: Photo

    func setPhoto(data: Data) async {
        isPreparingPhoto = true
        defer { isPreparingPhoto = false }
        let jpeg = await Task.detached(priority: .userInitiated) {
            RecipePhotoEncoder.jpegData(from: data)
        }.value
        guard let jpeg else {
            errorMessage = "This photo couldn’t be read. Try another one."
            return
        }
        pendingImage = .photo(jpeg)
        pendingPreview = UIImage(data: jpeg)
    }

    func setPhoto(_ image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 1) else { return }
        await setPhoto(data: data)
    }

    /// Returns `false` (and sets nothing) when `text` isn't a web address.
    @discardableResult
    func setImageURL(_ text: String) -> Bool {
        guard let url = RecipeURLExtractor.normalizedURL(from: text) else { return false }
        pendingImage = .url(url)
        pendingPreview = nil
        return true
    }

    func discardPendingImage() {
        pendingImage = nil
        pendingPreview = nil
    }

    // MARK: Lines

    func addIngredient(after id: UUID? = nil, text: String = "") -> UUID {
        let line = RecipeDraft.IngredientLine(text: text)
        if let id, let index = draft.ingredients.firstIndex(where: { $0.id == id }) {
            draft.ingredients.insert(line, at: index + 1)
        } else {
            draft.ingredients.append(line)
        }
        return line.id
    }

    func addStep(text: String = "") -> UUID {
        let line = RecipeDraft.StepLine(text: text)
        draft.steps.append(line)
        return line.id
    }

    func addNote() -> UUID {
        let line = RecipeDraft.NoteLine()
        draft.notes.append(line)
        return line.id
    }

    /// Pasted text → one ingredient per line (bullets stripped).
    func pasteIngredients(_ text: String) {
        let lines = Self.pastedLines(text, stripNumbers: false)
        // Replace a single empty placeholder line instead of appending after it.
        if draft.ingredients.count == 1, draft.ingredients[0].trimmedText.isEmpty { draft.ingredients.removeAll() }
        draft.ingredients += lines.map { RecipeDraft.IngredientLine(text: $0) }
    }

    /// Pasted text → one step per paragraph (or per line when there are no blank lines).
    func pasteSteps(_ text: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let paragraphs = normalized.components(separatedBy: "\n\n")
        let chunks = paragraphs.count > 1 ? paragraphs.map { $0.replacingOccurrences(of: "\n", with: " ") } : normalized.components(separatedBy: "\n")
        let steps = chunks.flatMap { Self.pastedLines($0, stripNumbers: true) }
        if draft.steps.count == 1, draft.steps[0].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { draft.steps.removeAll() }
        draft.steps += steps.map { RecipeDraft.StepLine(text: $0) }
    }

    /// Splits pasted text into trimmed, non-empty lines without list markers.
    nonisolated static func pastedLines(_ text: String, stripNumbers: Bool) -> [String] {
        text.components(separatedBy: .newlines).compactMap { raw in
            var line = raw.trimmingCharacters(in: .whitespaces)
            for marker in ["- ", "• ", "* ", "– ", "▢ ", "☐ "] where line.hasPrefix(marker) {
                line = String(line.dropFirst(marker.count))
            }
            if stripNumbers, let match = line.firstMatch(of: /^(?:step\s*)?\d+[.):]\s+/.ignoresCase()) {
                line = String(line[match.range.upperBound...])
            }
            line = line.trimmingCharacters(in: .whitespaces)
            return line.isEmpty ? nil : line
        }
    }

    // MARK: Saving

    /// Saves and returns the stored recipe, or `nil` (with `errorMessage` set).
    func save() async -> Recipe? {
        guard canSave else { return nil }
        isSaving = true
        defer { isSaving = false }

        var slug: String
        do {
            if let original {
                slug = original.slug
            } else if let createdSlug {
                slug = createdSlug
            } else {
                slug = try await mealie.createRecipe(name: draft.trimmedName)
                createdSlug = slug
            }
        } catch {
            return fail(error, prefix: nil)
        }

        var saved: Recipe?
        var changedSomething = false
        do {
            var patch = draft.patch(against: original, parsedIngredients: await parsedIngredients())
            if original == nil {
                // The name was set by POST; sending it again could only change the slug.
                patch.name = nil
            }
            if !patch.isEmpty {
                let updated = try await mealie.patchRecipe(slug: slug, fields: patch)
                slug = updated.slug
                saved = updated
                changedSomething = true
                setSaved(updated)
            }
        } catch {
            return fail(error, prefix: original == nil ? "The recipe was created, but its details couldn’t be saved." : nil)
        }

        if let pendingImage {
            do {
                switch pendingImage {
                case .photo(let data): try await mealie.uploadRecipeImage(slug: slug, imageData: data, fileExtension: "jpg")
                case .url(let url): try await mealie.setRecipeImage(slug: slug, fromURL: url.absoluteString)
                }
                discardPendingImage()
                saved = nil // refetch below for the new image key
                changedSomething = true
            } catch {
                return fail(error, prefix: "The recipe was saved, but the photo couldn’t be uploaded.")
            }
        }

        do {
            let result: Recipe
            if let saved {
                result = saved
            } else if !changedSomething, createdSlug == nil, let original {
                result = original
            } else {
                result = try await mealie.recipe(slug: slug)
            }
            setSaved(result)
            if changedSomething || createdSlug != nil { RecipeChanges.shared.recipesChanged() }
            createdSlug = nil
            return result
        } catch {
            return fail(error, prefix: "Saved, but the recipe couldn’t be reloaded.")
        }
    }

    /// Cancelling a new recipe whose details failed to save removes the
    /// half-created recipe again (best effort).
    func discardPartialCreation() async {
        guard let createdSlug, original == nil else { return }
        try? await mealie.deleteRecipe(slug: createdSlug)
        self.createdSlug = nil
    }

    // MARK: Private

    private func setSaved(_ recipe: Recipe) {
        original = recipe
        // Keep the lines (and their IDs) the user sees, but mark the state clean.
        initialDraft = draft
    }

    private func parsedIngredients() async -> [String: RecipeIngredient] {
        let texts = draft.ingredientTextsToParse
        guard !texts.isEmpty, let results = try? await mealie.parseIngredients(texts), results.count == texts.count else {
            return [:]
        }
        return Dictionary(zip(texts, results.map(\.ingredient)), uniquingKeysWith: { first, _ in first })
    }

    private func fail(_ error: Error, prefix: String?) -> Recipe? {
        let wrapped = MealieError.wrap(error)
        guard !wrapped.isCancelled else { return nil }
        let message = wrapped.errorDescription ?? "Something went wrong."
        errorMessage = prefix.map { "\($0) \(message)" } ?? message
        return nil
    }

    #if DEBUG
    /// DEBUG `editor-new/autosave` and `editor-edit/<slug>/autosave` routes: scripted
    /// edits that exercise the save path end to end (only use on "MealMate Test" data).
    func debugApplyScriptedEdits() {
        if let original {
            draft.description = (original.description ?? "") + " Edited."
            if !draft.ingredients.isEmpty {
                draft.ingredients[draft.ingredients.count - 1].text = "Lemon wedges and sugar, to serve"
            }
            draft.ingredients.append(.init(text: "100 ml milk"))
            draft.steps.append(.init(text: "MealMate test step."))
        } else {
            draft.name = "MealMate Test Created"
            draft.description = "Created by the editor's autosave route."
            draft.servings = 2
            draft.setYield(fromLine: "1 stack")
            draft.prepTime = "5 minutes"
            draft.parsesIngredients = true
            draft.ingredients = [.init(text: "2 cups flour"), .init(text: "1 tsp zzqspice"), .init(text: "Butter for the pan")]
            draft.steps = [.init(text: "Mix everything."), .init(text: "Fry in butter.")]
            draft.notes = [.init(title: "Test", text: "Delete me.")]
            draft.sourceURL = "https://www.example.com/test"
            // Optional: exercise the image-from-URL path with any public image.
            if let image = ProcessInfo.processInfo.environment["MEALMATE_TEST_IMAGE_URL"] { setImageURL(image) }
        }
    }
    #endif
}
