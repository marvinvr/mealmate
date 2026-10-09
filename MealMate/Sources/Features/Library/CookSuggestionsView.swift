import SwiftUI

/// "What Can I Cook?" (Library): pick the ingredients you have, see recipes that use them
/// with what's still missing (Mealie's `/api/recipes/suggestions`). Pushed via
/// `LibraryRoute.whatCanICook`; `preselection` (comma-separated food names, from the
/// `library-cook/<names>` route) replaces the saved selection once.
struct CookSuggestionsScreen: View {
    var preselection: String?
    @Environment(\.mealie) private var mealie

    var body: some View {
        CookSuggestionsContent(mealie: mealie, preselection: preselection)
            .id(mealie.cacheScope)
    }
}

private struct CookSuggestionsContent: View {
    let preselection: String?

    @State private var model: CookSuggestionsModel
    @State private var userData = RecipeUserData.shared
    @State private var didPreselect = false
    @FocusState private var isSearchFocused: Bool
    @Environment(\.mealie) private var mealie

    init(mealie: MealieService, preselection: String?) {
        self.preselection = preselection
        _model = State(initialValue: CookSuggestionsModel(mealie: mealie))
    }

    var body: some View {
        List {
            ingredientsSection
            resultsSection
        }
        .listStyle(.insetGrouped)
        .screenBackground()
        .navigationTitle("What Can I Cook?")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { optionsMenu }
        .refreshable {
            async let favorites: Void = userData.load(mealie, force: true)
            async let suggestions: Void = model.reload()
            _ = await (favorites, suggestions)
        }
        .task {
            if let preselection, !didPreselect {
                didPreselect = true
                await model.preselect(preselection)
            }
        }
        .task { await userData.load(mealie) }
        .task(id: model.key) { await model.keyChanged() }
        .task(id: model.foodSearch) { await model.searchFoods() }
    }

    // MARK: Ingredients

    private var trimmedSearch: String { model.foodSearch.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var ingredientsSection: some View {
        @Bindable var model = model
        return Section {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Add an ingredient you have", text: $model.foodSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isSearchFocused)
                if !model.foodSearch.isEmpty {
                    Button("Clear Search", systemImage: "xmark.circle.fill") { model.foodSearch = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.tertiary)
                        .buttonStyle(.plain)
                }
            }

            let shown = model.shownFoods
            if shown.isEmpty {
                if !trimmedSearch.isEmpty {
                    Text(model.isSearchingFoods ? "Searching…" : "No foods match “\(trimmedSearch)”.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                ChipFlowLayout(spacing: Theme.Spacing.xs) {
                    ForEach(shown) { food in
                        let isSelected = model.isSelected(food)
                        Button {
                            withAnimation(.smooth) { model.toggle(food) }
                        } label: {
                            TagChip(title: food.name, systemImage: isSelected ? "checkmark" : "plus", isSelected: isSelected)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(isSelected ? "Removes this ingredient" : "Adds this ingredient")
                    }
                }
                .padding(.vertical, Theme.Spacing.xxs)
                .sensoryFeedback(.selection, trigger: model.pantry.foods)
            }
        } header: {
            HStack {
                Text("Your Ingredients")
                if model.hasSelection {
                    Text("\(model.pantry.foods.count) selected")
                        .foregroundStyle(.tint)
                }
            }
        } footer: {
            Text(model.hasSelection || !trimmedSearch.isEmpty
                 ? "Tap an ingredient to remove it. Only recipes with recognized ingredients are matched."
                 : "Search for what you have, like “eggs” or “flour”.")
        }
    }

    // MARK: Results

    @ViewBuilder
    private var resultsSection: some View {
        if !model.hasSelection {
            Section {
                ContentUnavailableView {
                    Label("What’s in Your Kitchen?", systemImage: "refrigerator")
                } description: {
                    Text("Add a few ingredients you have to find recipes you can cook with them.")
                }
                .listRowBackground(Color.clear)
            }
        } else if model.isWaitingForResults {
            Section {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.xxl)
                    .listRowBackground(Color.clear)
            } header: {
                resultsHeader
            }
        } else if let error = model.loadError {
            Section {
                ContentUnavailableView {
                    Label("Can’t Load Suggestions", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await model.reload() } }
                        .buttonStyle(.bordered)
                }
                .listRowBackground(Color.clear)
            }
        } else if model.suggestions.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("No Matching Recipes", systemImage: "fork.knife")
                } description: {
                    Text(model.nextMissingAllowance == nil
                         ? "Add more of the ingredients you have."
                         : "Allow more missing ingredients, or add more of what you have.")
                } actions: {
                    if model.nextMissingAllowance != nil {
                        Button("Allow More Missing") { withAnimation(.smooth) { model.allowMoreMissing() } }
                            .buttonStyle(.bordered)
                    }
                }
                .listRowBackground(Color.clear)
            } header: {
                resultsHeader
            }
        } else {
            Section {
                ForEach(model.suggestions) { suggestion in
                    NavigationLink(value: AppDestination.recipe(slug: suggestion.recipe.slug)) {
                        CookSuggestionRow(suggestion: suggestion,
                                          isFavorite: userData.isFavorite(suggestion.recipe.id))
                    }
                }
            } header: {
                resultsHeader
            } footer: {
                if let error = model.refreshError {
                    Label(error, systemImage: "exclamationmark.triangle")
                }
            }
        }
    }

    /// "Recipes" + the missing-ingredients allowance as a small inline menu.
    private var resultsHeader: some View {
        @Bindable var model = model
        return HStack {
            Text("Recipes")
            Spacer()
            Menu {
                Picker("Missing Ingredients", selection: $model.pantry.maxMissing.animation(.smooth)) {
                    ForEach(CookSuggestions.allowances, id: \.self) { value in
                        Text(CookSuggestions.allowanceTitle(value)).tag(value)
                    }
                }
            } label: {
                HStack(spacing: Theme.Spacing.xxs) {
                    Text(model.pantry.maxMissing == 0 ? "Nothing missing" : "Up to \(model.pantry.maxMissing) missing")
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                }
                .font(.footnote)
            }
            .textCase(nil)
            .accessibilityLabel("Missing ingredients allowed")
            .accessibilityValue(CookSuggestions.allowanceTitle(model.pantry.maxMissing))
        }
    }

    // MARK: Toolbar

    private var optionsMenu: some ToolbarContent {
        @Bindable var model = model
        return ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Toggle(isOn: $model.pantry.includeOnHand) {
                    Label("Count Foods on Hand", systemImage: "house")
                    Text("Foods your household marked as on hand in Mealie")
                }
                if model.hasSelection {
                    Section {
                        Button("Clear Ingredients", systemImage: "xmark.circle", role: .destructive) {
                            withAnimation(.smooth) { model.clearFoods() }
                        }
                    }
                }
            } label: {
                Label("Options", systemImage: "slider.horizontal.3")
            }
        }
    }
}

/// A suggested recipe: thumbnail, serif title, metadata, then what's missing or substituted.
private struct CookSuggestionRow: View {
    let suggestion: RecipeSuggestion
    var isFavorite = false

    @ScaledMetric(relativeTo: .body) private var thumbnailSide: CGFloat = 56

    private var recipe: RecipeSummary { suggestion.recipe }
    private var missing: String? { CookSuggestions.missingText(for: suggestion) }
    private var substitution: String? { CookSuggestions.substitutionText(for: suggestion) }

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            RecipeImage(recipe: recipe, size: .tiny)
                .frame(width: thumbnailSide, height: thumbnailSide)
                .recipeImageShape(cornerRadius: Theme.Radius.thumbnail)

            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.displayName)
                    .font(.recipeRowTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if recipe.cardMetadata != nil || recipe.rating != nil {
                    RecipeMetadataLine(recipe: recipe)
                }
                Group {
                    if let missing {
                        Text(missing)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: Theme.Spacing.xxs) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                            Text("You have everything")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let substitution {
                        Text(substitution)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
                .lineLimit(2)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isFavorite {
                Image(systemName: "heart.fill")
                    .font(.footnote)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [recipe.accessibilitySummary]
        if isFavorite { parts.append("favorite") }
        parts.append(missing ?? "you have everything")
        if let substitution { parts.append(substitution) }
        return parts.joined(separator: ", ")
    }
}
