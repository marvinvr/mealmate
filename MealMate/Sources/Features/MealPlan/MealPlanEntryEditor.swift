import SwiftUI

/// Add or edit a meal plan entry: day, meal, and either a recipe (searchable) or a note.
struct MealPlanEntryEditor: View {
    enum Mode {
        case add(day: MealieDay, type: PlanEntryType, kind: Kind)
        case edit(MealPlanEntry)
    }

    enum Kind: String, CaseIterable, Identifiable {
        case recipe, note
        var id: String { rawValue }
        var title: String { self == .recipe ? "Recipe" : "Note" }
    }

    let mode: Mode
    /// Creates the entry; return `false` to keep the sheet open (the caller shows the error).
    var onAdd: (MealPlanEntryCreate) async -> Bool = { _ in true }
    /// Saves an edited entry (the caller updates optimistically).
    var onSave: (MealPlanEntry) -> Void = { _ in }
    var onDelete: ((MealPlanEntry) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var type: PlanEntryType
    @State private var kind: Kind
    @State private var recipe: RecipeSummary?
    @State private var title: String
    @State private var text: String
    @State private var isSaving = false
    @State private var search = ""
    @State private var picker = RecipeSearchModel()
    @FocusState private var titleFocused: Bool
    @Environment(\.mealie) private var mealie

    init(mode: Mode,
         onAdd: @escaping (MealPlanEntryCreate) async -> Bool = { _ in true },
         onSave: @escaping (MealPlanEntry) -> Void = { _ in },
         onDelete: ((MealPlanEntry) -> Void)? = nil) {
        self.mode = mode
        self.onAdd = onAdd
        self.onSave = onSave
        self.onDelete = onDelete
        switch mode {
        case .add(let day, let type, let kind):
            _date = State(initialValue: day.date())
            _type = State(initialValue: type)
            _kind = State(initialValue: kind)
            _recipe = State(initialValue: nil)
            _title = State(initialValue: "")
            _text = State(initialValue: "")
        case .edit(let entry):
            _date = State(initialValue: entry.date.date())
            _type = State(initialValue: entry.entryType)
            _kind = State(initialValue: entry.isNote ? .note : .recipe)
            _recipe = State(initialValue: entry.recipe)
            _title = State(initialValue: entry.title ?? "")
            _text = State(initialValue: entry.text ?? "")
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { true } else { false }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Day", selection: $date, displayedComponents: .date)
                    Picker("Meal", selection: $type) {
                        ForEach(MealPlanLayout.mealTypes, id: \.self) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Picker("Type", selection: $kind.animation(.snappy)) {
                        ForEach(Kind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                switch kind {
                case .recipe: recipeSections
                case .note: noteSection
                }

                if case .edit(let entry) = mode, let onDelete {
                    Section {
                        Button("Remove from Meal Plan", role: .destructive) {
                            onDelete(entry)
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .screenBackground()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .modifier(RecipeSearchable(isEnabled: kind == .recipe, text: $search))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(isEditing ? "Save" : "Add", systemImage: "checkmark") { Task { await commit() } }
                            .disabled(!canCommit)
                    }
                }
            }
            .task(id: "\(kind.rawValue)|\(search)") {
                guard kind == .recipe else { return }
                await picker.search(search, using: mealie)
            }
            .onAppear {
                if kind == .note, !isEditing { titleFocused = true }
            }
            .onChange(of: kind) { _, kind in
                if kind == .note { titleFocused = true }
            }
        }
        // iPad: room for the recipe search results.
        .presentationSizing(.page)
    }

    private var navigationTitle: String {
        if isEditing { return "Edit Meal" }
        return "\(MealieDay(date).relativeName()) · \(type.title)"
    }

    // MARK: Recipe

    @ViewBuilder
    private var recipeSections: some View {
        if let recipe, search.isEmpty {
            Section("Selected") {
                RecipeRow(recipe: recipe)
                    .overlay(alignment: .trailing) { checkmark }
            }
        }
        Section {
            if picker.isLoading && picker.results.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error = picker.error, picker.results.isEmpty {
                Label(error, systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.secondary)
            } else if picker.results.isEmpty, !search.isEmpty {
                ContentUnavailableView.search(text: search)
            }
            ForEach(picker.results.filter { $0.id != recipe?.id || !search.isEmpty }) { result in
                Button {
                    withAnimation(.snappy) { recipe = result }
                } label: {
                    RecipeRow(recipe: result)
                        .overlay(alignment: .trailing) {
                            if result.id == recipe?.id { checkmark }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(result.id == recipe?.id ? .isSelected : [])
            }
        } header: {
            Text(search.isEmpty ? "Recipes" : "Results")
        }
    }

    private var checkmark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.title3)
            .foregroundStyle(.tint)
            .background(Circle().fill(.mealMateSurface))
            .accessibilityHidden(true)
    }

    // MARK: Note

    private var noteSection: some View {
        Section {
            TextField("Title", text: $title)
                .focused($titleFocused)
                .submitLabel(.next)
            TextField("Details (optional)", text: $text, axis: .vertical)
                .lineLimit(3...8)
        } footer: {
            Text("Notes are for meals without a recipe, like “Leftovers” or “Dinner at Sam’s”.")
        }
    }

    // MARK: Commit

    private var canCommit: Bool {
        guard !isSaving else { return false }
        switch kind {
        case .recipe: return recipe != nil
        case .note: return !title.trimmingCharacters(in: .whitespaces).isEmpty || !text.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func commit() async {
        let day = MealieDay(date)
        let noteTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .add:
            var create = MealPlanEntryCreate(date: day, entryType: type)
            if kind == .recipe {
                create.recipeId = recipe?.id
            } else {
                create.title = noteTitle
                create.text = noteText
            }
            isSaving = true
            let success = await onAdd(create)
            isSaving = false
            if success { dismiss() }
        case .edit(let entry):
            var updated = entry
            updated.date = day
            updated.entryType = type
            if kind == .recipe {
                updated.recipeId = recipe?.id
                updated.recipe = recipe
                updated.title = ""
                updated.text = ""
            } else {
                updated.recipeId = nil
                updated.recipe = nil
                updated.title = noteTitle
                updated.text = noteText
            }
            onSave(updated)
            dismiss()
        }
    }
}

/// `.searchable` only while picking a recipe (a note has nothing to search).
private struct RecipeSearchable: ViewModifier {
    let isEnabled: Bool
    @Binding var text: String

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search recipes")
        } else {
            content
        }
    }
}

/// Debounced recipe search for pickers (empty query = recipes by name).
@MainActor
@Observable
final class RecipeSearchModel {
    private(set) var results: [RecipeSummary] = []
    private(set) var isLoading = false
    private(set) var error: String?

    func search(_ text: String, using mealie: MealieService) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
        } else if results.isEmpty, let cached = await mealie.cached([RecipeSummary].self, key: "mealplan.picker.recipes") {
            results = cached
        }
        isLoading = true
        defer { isLoading = false }
        var request = RecipeQuery()
        request.search = query.isEmpty ? nil : query
        request.sort = .name
        request.perPage = 50
        do {
            let page = try await mealie.recipes(request)
            guard !Task.isCancelled else { return }
            results = page.items
            error = nil
            if query.isEmpty { await mealie.storeInCache(page.items, key: "mealplan.picker.recipes") }
        } catch {
            let error = MealieError.wrap(error)
            if error != .cancelled { self.error = error.errorDescription }
        }
    }
}
