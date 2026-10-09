import PhotosUI
import SwiftUI

/// Create or edit a recipe. Present it as a sheet (it brings its own
/// NavigationStack):
///
/// ```swift
/// .sheet(isPresented: $isCreating) { RecipeEditorView() }            // new; opens the recipe after saving
/// .sheet(item: $editing) { recipe in
///     RecipeEditorView(recipe: recipe) { updated in self.recipe = updated }  // edit
/// }
/// ```
///
/// `onSave` receives the recipe as stored on the server. Renaming a recipe
/// changes its slug: use `updated.slug` from then on.
struct RecipeEditorView: View {
    private enum Source {
        case new
        case recipe(Recipe)
        case slug(String)
    }

    private let source: Source
    private let onSave: ((Recipe) -> Void)?
    private var scrollTarget: String?

    @Environment(\.mealie) private var mealie
    @State private var model: RecipeEditorViewModel?

    /// New recipe. Without `onSave` the new recipe is opened on the Recipes tab after saving.
    init(onSave: ((Recipe) -> Void)? = nil) {
        source = .new
        self.onSave = onSave
    }

    /// Edit an already loaded recipe.
    init(recipe: Recipe, onSave: ((Recipe) -> Void)? = nil) {
        source = .recipe(recipe)
        self.onSave = onSave
    }

    /// Edit the recipe with `slug` (loaded first).
    init(slug: String, onSave: ((Recipe) -> Void)? = nil) {
        source = .slug(slug)
        self.onSave = onSave
    }

    #if DEBUG
    /// DEBUG `editor-new/autosave` route.
    init(debugAction: String?) {
        self.init()
        scrollTarget = debugAction
    }

    /// DEBUG `editor-edit/<slug>/<section>` route: opens scrolled to a section.
    init(slug: String, scrollTo section: String?) {
        self.init(slug: slug)
        scrollTarget = section
    }
    #endif

    var body: some View {
        NavigationStack {
            if let model {
                RecipeEditorForm(model: model, onSave: onSave, scrollTarget: scrollTarget)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .screenBackground()
            }
        }
        // iPad: a long form, give it a page-sized sheet instead of the small form sheet.
        .presentationSizing(.page)
        .task {
            guard model == nil else { return }
            let model = switch source {
            case .new: RecipeEditorViewModel(mealie: mealie)
            case .recipe(let recipe): RecipeEditorViewModel(mealie: mealie, recipe: recipe)
            case .slug(let slug): RecipeEditorViewModel(mealie: mealie, slug: slug)
            }
            self.model = model
            await model.load()
        }
    }
}

// MARK: - Form

private struct RecipeEditorForm: View {
    @Bindable var model: RecipeEditorViewModel
    let onSave: ((Recipe) -> Void)?
    /// DEBUG routes: section to scroll to after loading ("ingredients", "steps", "notes", "organize"), or "tags" / "categories" to open that picker.
    var scrollTarget: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @FocusState private var focus: Field?
    @State private var editMode: EditMode = .inactive
    @State private var confirmsDiscard = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showsPhotoPicker = false
    @State private var showsCamera = false
    @State private var showsImageURLPrompt = false
    @State private var imageURLText = ""
    @State private var saveCount = 0
    /// DEBUG scroll targets "tags" / "categories" open the picker directly.
    @State private var debugPicker: OrganizerKind?
    /// Typed yield line; parsed into the draft on change (see `RecipeDraft.setYield`).
    @State private var yieldInput = ""

    private enum Field: Hashable {
        case name, description
        case ingredient(UUID), step(UUID), noteTitle(UUID), noteText(UUID)
    }

    var body: some View {
        Group {
            switch model.loadState {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Can’t Load Recipe", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await model.load() } }
                        .buttonStyle(.bordered)
                }
            case .loaded:
                form
            }
        }
        .screenBackground()
        .onChange(of: model.loadState, initial: true) { yieldInput = model.draft.yieldLine }
        .navigationTitle(model.isNew ? "New Recipe" : "Edit Recipe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .interactiveDismissDisabled(model.isDirty || model.isSaving)
        .confirmationDialog("Discard your changes?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) {
                Task { await model.discardPartialCreation() }
                dismiss()
            }
            Button("Keep Editing", role: .cancel) {}
        }
        .alert("Couldn’t Save", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sensoryFeedback(.success, trigger: saveCount)
        .sensoryFeedback(.error, trigger: model.errorMessage) { _, new in new != nil }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", systemImage: "xmark") {
                if model.isDirty { confirmsDiscard = true } else { dismiss() }
            }
            .disabled(model.isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
            if model.isSaving {
                ProgressView()
            } else {
                Button("Save", systemImage: "checkmark") { save() }
                    .disabled(!model.canSave || (!model.isDirty && !model.isNew))
            }
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focus = nil }
        }
    }

    private func save() {
        focus = nil
        Task {
            guard let recipe = await model.save() else { return }
            saveCount += 1
            dismiss()
            if let onSave {
                onSave(recipe)
            } else {
                router.push(.recipe(slug: recipe.slug), in: .recipes)
            }
        }
    }

    // MARK: Sections

    private var form: some View {
        ScrollViewReader { proxy in
            Form {
                photoSection
                basicsSection
                detailsSection
                ingredientsSection.id("ingredients")
                stepsSection.id("steps")
                notesSection.id("notes")
                organizeSection.id("organize")
                sourceSection
            }
            .task(id: scrollTarget) {
                guard let scrollTarget else { return }
                try? await Task.sleep(for: .milliseconds(400))
                switch scrollTarget {
                case "tags": debugPicker = .tag
                case "categories": debugPicker = .category
                case "autosave":
                    #if DEBUG
                    model.debugApplyScriptedEdits()
                    yieldInput = model.draft.yieldLine
                    save()
                    #else
                    break
                    #endif
                default: proxy.scrollTo(scrollTarget, anchor: .top)
                }
            }
            .navigationDestination(item: $debugPicker) { kind in
                OrganizerPickerView(kind: kind, selection: kind == .tag ? $model.draft.tags : $model.draft.categories)
            }
        }
        .environment(\.editMode, $editMode)
        .scrollDismissesKeyboard(.interactively)
        .photosPicker(isPresented: $showsPhotoPicker, selection: $photoItem, matching: .images, photoLibrary: .shared())
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await model.setPhoto(data: data)
                } else {
                    model.errorMessage = "This photo couldn’t be loaded. Try another one."
                }
                photoItem = nil
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker { image in Task { await model.setPhoto(image) } }
                .ignoresSafeArea()
        }
        .alert("Photo from the Web", isPresented: $showsImageURLPrompt) {
            TextField("https://example.com/photo.jpg", text: $imageURLText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Use Photo") {
                if !model.setImageURL(imageURLText) {
                    model.errorMessage = "That doesn’t look like a web address."
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste the address of an image. Mealie downloads it when you save.")
        }
    }

    // Photo

    private var hasPhoto: Bool { model.pendingImage != nil || model.currentImageURL != nil }

    private var photoSection: some View {
        Section {
            if hasPhoto {
                VStack(spacing: Theme.Spacing.s) {
                    photoPreview
                        .frame(maxWidth: .infinity)
                        .aspectRatio(Theme.Aspect.card, contentMode: .fit)
                        .clipped()
                        .recipeImageShape()
                        .overlay { preparingIndicator }
                    photoMenu
                }
                .listRowInsets(EdgeInsets(top: Theme.Spacing.m, leading: Theme.Spacing.m, bottom: Theme.Spacing.m, trailing: Theme.Spacing.m))
            } else {
                HStack(spacing: Theme.Spacing.m) {
                    RecipeImagePlaceholder(seed: model.original?.id ?? "new-recipe")
                        .frame(width: 64, height: 64)
                        .recipeImageShape(cornerRadius: Theme.Radius.thumbnail)
                        .overlay { preparingIndicator }
                    photoMenu
                }
            }
        }
    }

    @ViewBuilder
    private var preparingIndicator: some View {
        if model.isPreparingPhoto {
            ProgressView()
                .padding(Theme.Spacing.s)
                .glassEffect(in: .circle)
        }
    }

    @ViewBuilder
    private var photoPreview: some View {
        let seed = model.original?.id ?? "new-recipe"
        switch model.pendingImage {
        case .photo:
            if let preview = model.pendingPreview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel("New photo")
            } else {
                RecipeImagePlaceholder(seed: seed)
            }
        case .url(let url):
            remoteImage(url, seed: seed)
        case nil:
            if let url = model.currentImageURL {
                remoteImage(url, seed: seed)
            } else {
                RecipeImagePlaceholder(seed: seed)
            }
        }
    }

    private func remoteImage(_ url: URL, seed: String) -> some View {
        AsyncImage(url: url, transaction: Transaction(animation: .smooth)) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill().transition(.opacity)
            } else {
                RecipeImagePlaceholder(seed: seed)
            }
        }
        .accessibilityLabel("Recipe photo")
    }

    private var photoMenu: some View {
        Menu {
            Button("Choose from Library", systemImage: "photo.on.rectangle") { showsPhotoPicker = true }
            if CameraPicker.isAvailable {
                Button("Take Photo", systemImage: "camera") { showsCamera = true }
            }
            Button("From a Web Address", systemImage: "link") {
                imageURLText = ""
                showsImageURLPrompt = true
            }
            if model.pendingImage != nil {
                Divider()
                Button("Undo Photo Change", systemImage: "arrow.uturn.backward") { model.discardPendingImage() }
            }
        } label: {
            Label(model.pendingImage == nil && model.currentImageURL == nil ? "Add Photo" : "Change Photo",
                  systemImage: "photo.badge.plus")
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(.primary)
        .disabled(model.isPreparingPhoto)
    }

    // Basics

    private var basicsSection: some View {
        Section {
            TextField("Recipe name", text: $model.draft.name, axis: .vertical)
                .font(.recipeRowTitle)
                .focused($focus, equals: .name)
                .submitLabel(.next)
                .onSubmit { focus = .description }
            TextField("Short description", text: $model.draft.description, axis: .vertical)
                .lineLimit(2...6)
                .focused($focus, equals: .description)
        } footer: {
            if model.draft.trimmedName.isEmpty && model.isDirty {
                Text("A recipe needs a name.")
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            LabeledContent("Servings") {
                TextField("Not set", value: $model.draft.servings, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Yield") {
                TextField("e.g. 1 loaf", text: $yieldInput)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: yieldInput) { _, line in
                        if line != model.draft.yieldLine { model.draft.setYield(fromLine: line) }
                    }
            }
            timeRow("Prep time", text: $model.draft.prepTime)
            timeRow("Cook time", text: $model.draft.cookTime)
            timeRow("Total time", text: $model.draft.totalTime)
        }
    }

    private func timeRow(_ title: String, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField("e.g. 20 min", text: text)
                .multilineTextAlignment(.trailing)
        }
    }

    // Ingredients

    private var ingredientsSection: some View {
        Section {
            ForEach($model.draft.ingredients) { $line in
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    if let title = line.sectionTitle {
                        Text(title)
                            .font(.stepLabel)
                            .foregroundStyle(.secondary)
                    }
                    TextField("e.g. 2 cups flour", text: $line.text)
                        .focused($focus, equals: .ingredient(line.id))
                        .submitLabel(.next)
                        .onSubmit {
                            guard !line.trimmedText.isEmpty else { return }
                            focus = .ingredient(model.addIngredient(after: line.id))
                        }
                }
            }
            .onDelete { model.draft.ingredients.remove(atOffsets: $0) }
            .onMove { model.draft.ingredients.move(fromOffsets: $0, toOffset: $1) }

            addRow("Add Ingredient") {
                focus = .ingredient(model.addIngredient())
            } paste: { model.pasteIngredients($0) }

            Toggle("Recognize amounts", isOn: $model.draft.parsesIngredients)
                .tint(.accentColor)
        } header: {
            sectionHeader("Ingredients", count: model.draft.ingredients.count)
        } footer: {
            Text(model.draft.parsesIngredients
                 ? "Mealie splits new and edited lines into amount, unit and food, so the recipe can be scaled and added to shopping lists."
                 : "Lines are saved exactly as typed.")
        }
    }

    // Steps

    private var stepsSection: some View {
        Section {
            ForEach(Array($model.draft.steps.enumerated()), id: \.element.id) { index, $line in
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text("Step \(index + 1)")
                        .font(.stepLabel)
                        .foregroundStyle(.secondary)
                    TextField("Describe this step", text: $line.text, axis: .vertical)
                        .lineLimit(1...12)
                        .focused($focus, equals: .step(line.id))
                }
                .padding(.vertical, Theme.Spacing.xxs)
            }
            .onDelete { model.draft.steps.remove(atOffsets: $0) }
            .onMove { model.draft.steps.move(fromOffsets: $0, toOffset: $1) }

            addRow("Add Step") {
                focus = .step(model.addStep())
            } paste: { model.pasteSteps($0) }
        } header: {
            sectionHeader("Steps", count: model.draft.steps.count)
        }
    }

    // Notes

    private var notesSection: some View {
        Section {
            ForEach($model.draft.notes) { $line in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    TextField("Title", text: $line.title)
                        .font(.body.weight(.semibold))
                        .focused($focus, equals: .noteTitle(line.id))
                        .submitLabel(.next)
                        .onSubmit { focus = .noteText(line.id) }
                    TextField("Note", text: $line.text, axis: .vertical)
                        .lineLimit(1...10)
                        .focused($focus, equals: .noteText(line.id))
                }
                .padding(.vertical, Theme.Spacing.xxs)
            }
            .onDelete { model.draft.notes.remove(atOffsets: $0) }
            .onMove { model.draft.notes.move(fromOffsets: $0, toOffset: $1) }

            Button("Add Note", systemImage: "plus") {
                focus = .noteTitle(model.addNote())
            }
        } header: {
            Text("Notes")
        }
    }

    // Organize

    private var organizeSection: some View {
        Section("Organize") {
            organizerLink(.category, selection: $model.draft.categories)
            organizerLink(.tag, selection: $model.draft.tags)
        }
    }

    private func organizerLink(_ kind: OrganizerKind, selection: Binding<[Organizer]>) -> some View {
        NavigationLink {
            OrganizerPickerView(kind: kind, selection: selection)
        } label: {
            LabeledContent {
                Text(selection.wrappedValue.isEmpty ? "None" : selection.wrappedValue.map(\.name).formatted(.list(type: .and)))
                    .lineLimit(2)
            } label: {
                Label(kind.title, systemImage: kind.systemImage)
            }
        }
    }

    private var sourceSection: some View {
        Section {
            TextField("https://example.com/recipe", text: $model.draft.sourceURL)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Source")
        } footer: {
            Text("The website or book this recipe comes from.")
        }
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            if count > 1 {
                Button(editMode.isEditing ? "Done" : "Reorder") {
                    withAnimation(.snappy) { editMode = editMode.isEditing ? .inactive : .active }
                }
                .font(.subheadline.weight(.medium))
                .textCase(nil)
            }
        }
    }

    private func addRow(_ title: String, add: @escaping () -> Void, paste: @escaping (String) -> Void) -> some View {
        HStack {
            Button(title, systemImage: "plus", action: add)
                .buttonStyle(.borderless)
            Spacer()
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                Task { @MainActor in withAnimation(.snappy) { paste(text) } }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .accessibilityLabel("Paste several")
        }
    }
}

#if DEBUG
#Preview("New") {
    RecipeEditorView()
        .environment(AppRouter())
}
#endif
