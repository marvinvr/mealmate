import PhotosUI
import SwiftUI

/// "Import Recipe" sheet: paste a recipe link and Mealie scrapes it. Brings its
/// own NavigationStack; present it as a sheet:
///
/// ```swift
/// .sheet(isPresented: $isImporting) { ImportRecipeView() }
/// ```
///
/// After a successful import the sheet closes and the new recipe is pushed on
/// the Recipes tab (or `onImported` is called instead, if given). AI import
/// (text / photos) only appears when the server has an AI provider configured.
struct ImportRecipeView: View {
    private let initialURL: String?
    private let onImported: ((Recipe) -> Void)?
    #if DEBUG
    private var debugState: DebugState?
    private var debugAutoStart = false
    #endif

    @Environment(\.mealie) private var mealie
    @State private var model: ImportRecipeViewModel?

    init(initialURL: String? = nil, onImported: ((Recipe) -> Void)? = nil) {
        self.initialURL = initialURL
        self.onImported = onImported
    }

    var body: some View {
        NavigationStack {
            if let model {
                ImportRecipeContent(model: model, onImported: onImported)
            } else {
                Color.clear.screenBackground()
            }
        }
        .task {
            guard model == nil else { return }
            let model = ImportRecipeViewModel(mealie: mealie, initialURL: initialURL)
            self.model = model
            #if DEBUG
            if let debugState {
                debugState.apply(to: model)
                return
            }
            #endif
            await model.loadAISettings()
            #if DEBUG
            if debugAutoStart { await model.importFromURL() }
            #endif
        }
    }

    #if DEBUG
    /// Fixed states for screenshots (`import-state/<name>` routes).
    enum DebugState: String, CaseIterable, Sendable {
        case importing, failed, unavailable, duplicate, ai

        @MainActor
        func apply(to model: ImportRecipeViewModel) {
            model.urlText = "https://www.example.com/recipes/lemon-herb-chicken"
            switch self {
            case .importing:
                model.debugShow(.importing(source: "www.example.com"))
            case .failed:
                model.debugShow(.failed(RecipeImportProblem(.server(status: 400, message: "BAD_RECIPE_DATA"))))
            case .unavailable:
                model.debugShow(.failed(RecipeImportProblem(.server(status: 400, message: "Something went wrong while creating the recipe. Please try again"))))
            case .duplicate:
                let existing = RecipeSummary(id: "00000000-0000-4000-8000-000000000001", slug: "lemon-herb-chicken", name: "Lemon Herb Chicken")
                model.debugShow(.duplicate(existing: existing, url: URL(string: model.urlText)!))
            case .ai:
                model.urlText = ""
                model.debugShow(.editing, ai: true)
            }
        }
    }

    init(initialURL: String?, debugAutoStart: Bool) {
        self.init(initialURL: initialURL)
        self.debugAutoStart = debugAutoStart
    }

    init(debugState: DebugState) {
        self.init()
        self.debugState = debugState
    }
    #endif
}

// MARK: - Content

private struct ImportRecipeContent: View {
    @Bindable var model: ImportRecipeViewModel
    let onImported: ((Recipe) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @AppStorage(ImportPreferences.includeOrganizersKey, store: CredentialStore.defaults)
    private var includeOrganizers = false
    @FocusState private var isURLFocused: Bool
    @State private var aiPhotoItems: [PhotosPickerItem] = []

    var body: some View {
        Group {
            switch model.phase {
            case .importing(let source):
                ImportProgressView(source: source)
            case .duplicate(let existing, _):
                duplicateView(existing)
            case .editing, .failed, .imported:
                form
            }
        }
        .screenBackground()
        .navigationTitle("Import Recipe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark") { dismiss() }
            }
        }
        .animation(.smooth, value: model.phase)
        .sensoryFeedback(.success, trigger: model.importedRecipe?.slug) { _, new in new != nil }
        .sensoryFeedback(.error, trigger: model.problem) { _, new in new != nil }
        .onChange(of: model.importedRecipe?.slug) { _, slug in
            guard let recipe = model.importedRecipe, slug != nil else { return }
            open(recipe)
        }
    }

    private func open(_ recipe: Recipe) {
        dismiss()
        if let onImported {
            onImported(recipe)
        } else {
            router.push(.recipe(slug: recipe.slug), in: .recipes)
        }
    }

    // MARK: Form

    private var form: some View {
        Form {
            Section {
                HStack(spacing: Theme.Spacing.xs) {
                    TextField("https://example.com/recipe", text: $model.urlText, axis: .vertical)
                        .lineLimit(1...3)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($isURLFocused)
                        .onSubmit(startImport)
                        .onChange(of: model.urlText) { model.editURL() }
                        .accessibilityLabel("Recipe address")
                    if model.urlText.isEmpty {
                        PasteButton(payloadType: String.self) { strings in
                            Task { @MainActor in model.paste(strings) }
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                    } else {
                        Button("Clear", systemImage: "xmark.circle.fill") { model.urlText = "" }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.tertiary)
                            .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Recipe website")
            } footer: {
                Text("Paste the link to a recipe page. Mealie reads the ingredients, steps and photo from it.")
            }

            if let problem = model.problem {
                Section {
                    ImportProblemRow(problem: problem)
                }
            }

            Section {
                Toggle("Import tags and categories", isOn: $includeOrganizers)
                    .tint(.accentColor)
            } footer: {
                Text("Adds the website’s keywords to the recipe as tags and categories. New ones are created in Mealie.")
            }

            if model.isAIAvailable {
                aiSection
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: startImport) {
                Text(model.problem == nil ? "Import Recipe" : "Try Again")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .primaryActionStyle()
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(!model.canImport)
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.bottom, Theme.Spacing.xs)
        }
        .onAppear {
            if model.urlText.isEmpty && model.problem == nil && !model.isAIAvailable { isURLFocused = true }
        }
    }

    private func startImport() {
        isURLFocused = false
        Task { await model.importFromURL() }
    }

    // MARK: AI

    private var aiSection: some View {
        Section {
            NavigationLink {
                AITextImportView(model: model)
            } label: {
                Label("Paste Recipe Text", systemImage: "text.document")
            }
            if model.isImageImportAvailable {
                PhotosPicker(selection: $aiPhotoItems, maxSelectionCount: 4, matching: .images) {
                    Label {
                        Text("Recipe from Photos").foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "camera.viewfinder")
                    }
                }
                .onChange(of: aiPhotoItems) { _, items in
                    guard !items.isEmpty else { return }
                    Task { await importPhotos(items) }
                }
            }
        } header: {
            Text("Import with AI")
        } footer: {
            Text("For recipes from a message, a cookbook page or a handwritten card. Uses the AI provider set up on your Mealie server.")
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        var images: [Data] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let jpeg = await Task.detached(priority: .userInitiated) { RecipePhotoEncoder.jpegData(from: data) }.value
            if let jpeg { images.append(jpeg) }
        }
        aiPhotoItems = []
        guard !images.isEmpty else { return }
        await model.importWithAI(text: "", images: images)
    }

    // MARK: Duplicate

    private func duplicateView(_ existing: RecipeSummary) -> some View {
        ContentUnavailableView {
            Label("Already in Your Recipes", systemImage: "book.closed")
        } description: {
            Text("You imported this page before as \(Text(existing.displayName).bold()).")
        } actions: {
            Button {
                dismiss()
                if let onImported {
                    onImported(Recipe(id: existing.id, slug: existing.slug, name: existing.name))
                } else {
                    router.push(.recipe(slug: existing.slug), in: .recipes)
                }
            } label: {
                Text("Open Recipe").font(.body.weight(.semibold))
            }
            .primaryActionStyle()
            .controlSize(.large)

            Button("Import a Copy") {
                Task { await model.importFromURL(allowDuplicate: true) }
            }
            .buttonStyle(.bordered)
            .tint(.primary)
        }
    }
}

// MARK: - Pieces

/// AI import from pasted text (only reachable when the server has AI).
private struct AITextImportView: View {
    @Bindable var model: ImportRecipeViewModel
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 220)
                    .focused($isFocused)
                    .accessibilityLabel("Recipe text")
            } footer: {
                Text("Paste a recipe from a message, a note or an e-mail. The AI turns it into ingredients and steps.")
            }
            if let problem = model.problem {
                Section { ImportProblemRow(problem: problem) }
            }
        }
        .overlay {
            if case .importing(let source) = model.phase {
                ImportProgressView(source: source)
                    .background(.mealMateBackground)
            }
        }
        .screenBackground()
        .navigationTitle("Paste Recipe Text")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                isFocused = false
                Task { await model.importWithAI(text: text) }
            } label: {
                Text("Import with AI")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .primaryActionStyle()
            .controlSize(.large)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.bottom, Theme.Spacing.xs)
        }
        .onAppear { isFocused = true }
    }
}

#if DEBUG
#Preview("Import") {
    ImportRecipeView()
        .environment(AppRouter())
}
#endif
