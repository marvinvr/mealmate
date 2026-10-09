import SwiftUI

/// "Add to Shopping List" for a recipe: pick a list (the last used one is preselected),
/// adjust servings, and untick what's already at home. Foods marked "on hand" in Mealie
/// start unticked.
///
/// Present it from the recipe screen:
/// ```swift
/// .sheet(isPresented: $addsToList) { AddToShoppingListSheet(recipe: recipe, scale: scale) }
/// ```
/// `scale` is the recipe's servings multiplier (1 = as written).
struct AddToShoppingListSheet: View {
    private let source: Source

    private enum Source {
        case recipe(Recipe, scale: Double)
        case slug(String)
    }

    init(recipe: Recipe, scale: Double = 1) {
        source = .recipe(recipe, scale: scale)
    }

    /// Loads the recipe first (deep links, DEBUG routes).
    init(slug: String) {
        source = .slug(slug)
    }

    var body: some View {
        Group {
            switch source {
            case .recipe(let recipe, let scale):
                AddToShoppingListForm(recipe: recipe, scale: scale)
            case .slug(let slug):
                RecipeLoadingSheet(slug: slug, title: "Add to List") { recipe in
                    AddToShoppingListForm(recipe: recipe, scale: 1)
                }
            }
        }
        // iPad: room for the whole ingredient list.
        .presentationSizing(.page)
    }
}

// MARK: - Model

@MainActor
@Observable
final class AddToShoppingListModel {
    let recipe: Recipe
    /// Servings multiplier sent as `recipeIncrementQuantity`.
    var scale: Double
    /// The list to add to.
    let destination = ShoppingListChoice()
    /// Indices into `ingredients` that will be added.
    var selection: Set<Int> = []
    private(set) var isAdding = false
    var error: MealieError?

    /// Ingredient lines worth adding (non-empty), with their index in the recipe.
    let ingredients: [(index: Int, ingredient: RecipeIngredient)]

    @ObservationIgnored private var mealie: MealieService = .unconfigured

    init(recipe: Recipe, scale: Double, householdSlug: String?) {
        self.recipe = recipe
        self.householdSlug = householdSlug
        self.scale = scale > 0 ? scale : 1
        ingredients = recipe.ingredients.enumerated()
            .map { (index: $0.offset, ingredient: $0.element) }
            .filter { !IngredientFormatting.text(for: $0.ingredient).trimmingCharacters(in: .whitespaces).isEmpty }
        selection = Set(ingredients.filter { !Self.isOnHand($0.ingredient, householdSlug: householdSlug) }.map(\.index))
    }

    /// Current user's household; may arrive after the sheet opened (user still loading).
    private(set) var householdSlug: String?

    /// Unticks on-hand foods once the household is known (first time only, so later
    /// manual choices aren't overridden).
    func applyHousehold(_ slug: String?) {
        guard householdSlug == nil, let slug else { return }
        householdSlug = slug
        selection.subtract(ingredients.filter { Self.isOnHand($0.ingredient, householdSlug: slug) }.map(\.index))
    }

    static func isOnHand(_ ingredient: RecipeIngredient, householdSlug: String?) -> Bool {
        ingredient.food?.isOnHand(householdSlug: householdSlug) ?? false
    }

    var baseServings: Double? {
        guard let servings = recipe.recipeServings, servings > 0 else { return nil }
        return servings
    }

    var canAdd: Bool { destination.selectedListID != nil && !selection.isEmpty && !isAdding }

    func load(using mealie: MealieService, lastListID: String?) async {
        self.mealie = mealie
        await destination.load(using: mealie, lastListID: lastListID)
    }

    func toggle(_ index: Int) {
        if selection.contains(index) { selection.remove(index) } else { selection.insert(index) }
    }

    var allSelected: Bool { selection.count == ingredients.count }

    func selectAll(_ selectAll: Bool) {
        selection = selectAll ? Set(ingredients.map(\.index)) : []
    }

    /// Adds the selection; returns the number of lines added, or `nil` on failure.
    func add() async -> Int? {
        guard let listID = destination.selectedListID, !selection.isEmpty else { return nil }
        isAdding = true
        defer { isAdding = false }
        // All lines → let Mealie take the recipe's ingredients; otherwise send the subset.
        // Either way Mealie scales quantities by `recipeIncrementQuantity` and records the
        // recipe reference, so "remove this recipe's items" works on the list.
        let chosen = allSelected ? nil : ingredients.filter { selection.contains($0.index) }.map(\.ingredient)
        let request = ShoppingListAddRecipe(recipeId: recipe.id, recipeIncrementQuantity: scale, recipeIngredients: chosen)
        do {
            let updated = try await mealie.addRecipesToShoppingList(listID: listID, recipes: [request])
            await mealie.storeInCache(updated, key: "shopping.list.\(listID)")
            return selection.count
        } catch {
            self.error = MealieError.wrap(error)
            return nil
        }
    }
}

// MARK: - Form

private struct AddToShoppingListForm: View {
    @Environment(\.mealie) private var mealie
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ShoppingListChoice.lastListKey) private var lastListID = ""

    @State private var model: AddToShoppingListModel?
    let recipe: Recipe
    let scale: Double

    @State private var toast: ActionToast?
    @State private var successFeedback = 0
    @State private var errorFeedback = 0

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    form(model)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .screenBackground()
            .navigationTitle("Add to List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model?.isAdding == true {
                        ProgressView()
                    } else {
                        Button("Add", systemImage: "checkmark") { Task { await add() } }
                            .disabled(model?.canAdd != true || toast != nil)
                    }
                }
            }
            .actionToast($toast)
        }
        .sensoryFeedback(.success, trigger: successFeedback)
        .sensoryFeedback(.error, trigger: errorFeedback)
        .task {
            if model == nil {
                model = AddToShoppingListModel(recipe: recipe, scale: scale,
                                               householdSlug: session.currentUser?.householdSlug)
            }
            await model?.load(using: mealie, lastListID: lastListID)
        }
        .onChange(of: session.currentUser?.householdSlug) { _, slug in
            model?.applyHousehold(slug)
        }
        .alert(isPresented: errorBinding, error: model?.error) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.recoverySuggestion ?? "Nothing was added. Try again.")
        }
    }

    @ViewBuilder
    private func form(_ model: AddToShoppingListModel) -> some View {
        @Bindable var model = model
        Form {
            Section {
                HStack(spacing: Theme.Spacing.s) {
                    RecipeImage(recipe: recipe.summary, size: .tiny)
                        .frame(width: 44, height: 44)
                        .recipeImageShape(cornerRadius: Theme.Radius.thumbnail)
                    Text(recipe.displayName)
                        .font(.recipeRowTitle)
                        .lineLimit(2)
                }

                ShoppingListPickerRow(choice: model.destination)
                servingsStepper(model)
            }

            Section {
                if model.ingredients.isEmpty {
                    Text("This recipe has no ingredients.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.ingredients, id: \.index) { entry in
                    IngredientToggleRow(
                        groupTitle: entry.ingredient.title?.trimmingCharacters(in: .whitespaces),
                        text: IngredientFormatting.text(for: entry.ingredient, scale: model.scale),
                        isSelected: model.selection.contains(entry.index),
                        isOnHand: AddToShoppingListModel.isOnHand(entry.ingredient, householdSlug: model.householdSlug)
                    ) {
                        model.toggle(entry.index)
                    }
                }
            } header: {
                HStack {
                    Text("Ingredients")
                    Spacer()
                    if !model.ingredients.isEmpty {
                        Button(model.allSelected ? "Select None" : "Select All") {
                            model.selectAll(!model.allSelected)
                        }
                        .font(.subheadline.weight(.medium))
                        .textCase(nil)
                    }
                }
            } footer: {
                Text("Untick what you already have.")
            }
        }
        .sensoryFeedback(.selection, trigger: model.selection)
    }

    @ViewBuilder
    private func servingsStepper(_ model: AddToShoppingListModel) -> some View {
        if let base = model.baseServings {
            let servings = (base * model.scale).rounded()
            Stepper(value: Binding(get: { servings }, set: { model.scale = max($0, 1) / base }), in: 1...99, step: 1) {
                LabeledContent("Servings") {
                    Text(servings, format: .number.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: servings))
                }
            }
        } else {
            Stepper(value: Binding(get: { model.scale }, set: { model.scale = $0 }), in: 0.5...20, step: 0.5) {
                LabeledContent("Amount") {
                    Text("×\(model.scale.formatted(.number.precision(.fractionLength(0...1))))")
                        .monospacedDigit()
                }
            }
        }
    }

    private func add() async {
        guard let model, let count = await model.add() else {
            errorFeedback += 1
            return
        }
        lastListID = model.destination.selectedListID ?? lastListID
        successFeedback += 1
        let listName = model.destination.selectedList?.displayName ?? "your list"
        toast = ActionToast(message: count == 1 ? "Added 1 item to \(listName)" : "Added \(count) items to \(listName)",
                            duration: .seconds(2))
        try? await Task.sleep(for: .seconds(1.2))
        dismiss()
    }

    private var errorBinding: Binding<Bool> {
        Binding { model?.error != nil } set: { if !$0 { model?.error = nil } }
    }
}

private struct IngredientToggleRow: View {
    /// Ingredient group header ("Sauce") shown above the first line of a group.
    var groupTitle: String?
    let text: String
    let isSelected: Bool
    let isOnHand: Bool
    var toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let groupTitle, !groupTitle.isEmpty {
                Text(groupTitle)
                    .font(.stepLabel)
                    .foregroundStyle(.secondary)
                    .padding(.top, Theme.Spacing.xxs)
                    .accessibilityAddTraits(.isHeader)
            }
            toggleButton
        }
    }

    private var toggleButton: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(text)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    if isOnHand {
                        Text("On hand")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Will be added." : "Won't be added.")
    }
}

// MARK: - Loading wrapper

/// Loads a recipe by slug, then shows `content`. Used by the sheets' slug initialisers.
struct RecipeLoadingSheet<Content: View>: View {
    let slug: String
    let title: String
    @ViewBuilder var content: (Recipe) -> Content

    @Environment(\.mealie) private var mealie
    @Environment(\.dismiss) private var dismiss
    @State private var recipe: Recipe?
    @State private var error: MealieError?

    var body: some View {
        if let recipe {
            content(recipe)
        } else {
            NavigationStack {
                Group {
                    if let error {
                        ContentUnavailableView {
                            Label("Can't Load Recipe", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(error.errorDescription ?? "Check your connection, then try again.")
                        } actions: {
                            Button("Try Again") { Task { await load() } }
                                .buttonStyle(.bordered)
                        }
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .screenBackground()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", systemImage: "xmark") { dismiss() }
                    }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        error = nil
        do {
            recipe = try await mealie.recipe(slug: slug)
        } catch {
            let error = MealieError.wrap(error)
            if error != .cancelled { self.error = error }
        }
    }
}
