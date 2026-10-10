import SwiftUI

/// Recipes tab root: every recipe as a grid (or list), with search, filters, sort and the
/// "+" menu for new / imported recipes.
/// Lives inside the tab's NavigationStack (see `MainTabView`): don't add another stack.
struct RecipesView: View {
    @Environment(\.mealie) private var mealie

    var body: some View {
        RecipesScreen(mealie: mealie)
            .id(mealie.cacheScope)
    }
}

private struct RecipesScreen: View {
    @State private var model: RecipeListModel
    @AppStorage("recipes.layout") private var storedLayout: RecipeLayout = .grid
    @AppStorage("recipes.sort") private var storedSort: String = RecipeSort.recentlyAdded.rawValue
    /// Debug-route override that isn't persisted.
    @State private var layoutOverride: RecipeLayout?
    @State private var sheet: RecipeSheet?
    @State private var toast: RecipeToast?
    @State private var isFilterSheetPresented = false
    @State private var selection = RecipeSelectionState()
    @State private var bulkSheet: RecipeBulkSheet?
    /// Set once a bulk run has started, so dismissing its sheet leaves selection mode.
    @State private var exitSelectionOnDismiss = false
    @State private var pendingSelection: PendingSelection?
    @State private var recipeActions: [RecipeAction] = []
    @State private var actionsLoaded = false

    @Environment(\.mealie) private var mealie
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session
    @State private var userData = RecipeUserData.shared

    init(mealie: MealieService) {
        let sort = RecipeSort(rawValue: UserDefaults.standard.string(forKey: "recipes.sort") ?? "") ?? .recentlyAdded
        _model = State(initialValue: RecipeListModel(preset: .all, sort: sort, mealie: mealie))
    }

    private var layout: RecipeLayout { layoutOverride ?? storedLayout }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            RecipeCollectionContent(
                model: model,
                layout: layout,
                onClearFilters: { withAnimation(.smooth) { model.clearFilters() } },
                header: model.filters.isEmpty ? nil : AnyView(ActiveFilterBar(filters: $model.filters, onEdit: { isFilterSheetPresented = true })),
                sheet: $sheet,
                toast: $toast,
                selection: $selection
            )
            if selection.isActive {
                // A sibling, not a safe-area overlay: Lists draw under bottom insets, which
                // hid the last row's title behind the bar.
                selectionActionBar
                    .background(.mealMateBackground)
            }
        }
        .navigationTitle(selection.isActive ? selectionTitle : "Recipes")
        // iPhone keeps the count inline between Cancel and Select All. On iPad the tab bar
        // occupies that centre, so the count stays a large title under the tabs.
        .navigationBarTitleDisplayMode(selection.isActive && horizontalSizeClass != .regular ? .inline : .large)
        .searchable(text: $model.search, prompt: "Search recipes")
        .toolbar { toolbar }
        .toolbarVisibility(selection.isActive && horizontalSizeClass != .regular ? .hidden : .automatic, for: .tabBar)
        .preference(key: AccountButtonHiddenKey.self, value: selection.isActive)
        .task(id: model.key) { await model.keyChanged() }
        .task { await RecipeUserData.shared.load(mealie) }
        .task(id: selection.isActive) { await loadActionsIfSelecting() }
        .onChange(of: model.sort) { _, sort in storedSort = sort.rawValue }
        .onChange(of: model.items.map(\.id)) { _, _ in applyPendingSelection() }
        .onAppear(perform: consumeIntent)
        .onChange(of: router.pendingIntent) { _, _ in consumeIntent() }
        .sensoryFeedback(.selection, trigger: selection.changeCount)
        .sheet(isPresented: $isFilterSheetPresented) {
            RecipeFilterSheet(filters: $model.filters)
        }
        .sheet(item: $sheet, onDismiss: { Task { await model.reload() } }) { sheet in
            RecipeSheetView(sheet: sheet)
        }
        .sheet(item: $bulkSheet, onDismiss: dismissBulkSheet) { bulk in
            bulkSheetView(bulk)
        }
        .recipeToast($toast)
    }

    private var selectionTitle: String {
        selection.count == 0 ? "Select Recipes" : "\(selection.count) Selected"
    }

    private var allLoadedSelected: Bool { selection.covers(model.items) }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if selection.isActive {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { withAnimation(.snappy) { selection.end() } }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(allLoadedSelected ? "Deselect All" : "Select All") {
                    withAnimation(.snappy) { selection.toggleAll(loaded: model.items) }
                }
                .disabled(model.items.isEmpty)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) { addMenu }
            ToolbarItem(placement: .topBarTrailing) { optionsMenu }
        }
    }

    /// Labeled glass bar below the list. The system bottom toolbar collapses these to icons.
    private var selectionActionBar: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.horizontal, showsIndicators: false) { selectionActionRow }
            } else {
                selectionActionRow
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.tint)
        .padding(.horizontal, Theme.Spacing.xs)
        .frame(minHeight: 52)
        .glassEffect(.regular.interactive(), in: .capsule)
        .frame(maxWidth: Theme.readableWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.xs)
    }

    private var selectionActionRow: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            if !actionsLoaded && recipeActions.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading recipe actions")
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else if applicableActions.count == 1, let action = applicableActions.first {
                selectionBarButton(action.title, systemImage: action.isLink ? "arrow.up.forward.app" : "paperplane") {
                    run(action)
                }
            } else if applicableActions.count > 1 {
                Menu {
                    ForEach(applicableActions) { action in
                        Button {
                            run(action)
                        } label: {
                            Label(action.title, systemImage: action.isLink ? "arrow.up.forward.app" : "paperplane")
                        }
                    }
                } label: {
                    selectionBarLabel("Actions", systemImage: "paperplane")
                }
                .buttonStyle(.borderless)
                .disabled(selection.isEmpty)
            }
            selectionBarButton("List", systemImage: "cart.badge.plus", accessibilityLabel: "Add to List") {
                bulkSheet = .shopping(selection.recipes)
            }
            selectionBarButton("Plan", systemImage: "calendar.badge.plus", accessibilityLabel: "Add to Plan") {
                bulkSheet = .mealPlan(selection.recipes)
            }
            selectionBarButton(
                favoriteAllSelected ? "Unfavorite" : "Favorite",
                systemImage: favoriteAllSelected ? "heart.slash" : "heart",
                showsTitle: false
            ) {
                favoriteSelected()
            }
            if selection.count == 1, let recipe = selection.recipes.first,
               let url = RecipeLinks.webURL(server: mealie.baseURL, groupSlug: session.currentUser?.groupSlug, slug: recipe.slug) {
                ShareLink(item: url, subject: Text(recipe.displayName)) {
                    selectionBarLabel("Share", systemImage: "square.and.arrow.up", showsTitle: false)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func selectionBarButton(
        _ title: String,
        systemImage: String,
        accessibilityLabel: String? = nil,
        showsTitle: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            selectionBarLabel(title, systemImage: systemImage, showsTitle: showsTitle)
        }
        .buttonStyle(.borderless)
        .disabled(selection.isEmpty)
        .accessibilityLabel(accessibilityLabel ?? title)
    }

    @ViewBuilder
    private func selectionBarLabel(_ title: String, systemImage: String, showsTitle: Bool = true) -> some View {
        if showsTitle {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
        } else {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
        }
    }

    /// Post actions always; link actions only for a single recipe (each one opens a browser page).
    private var applicableActions: [RecipeAction] {
        if selection.count == 1 { return recipeActions }
        return recipeActions.filter { !$0.isLink }
    }

    private var favoriteAllSelected: Bool {
        !selection.recipes.isEmpty && selection.recipes.allSatisfy { userData.isFavorite($0.id) }
    }

    private var addMenu: some View {
        Menu {
            Button {
                sheet = .importRecipe
            } label: {
                Label("Import from URL", systemImage: "link")
            }
            Button {
                sheet = .newRecipe
            } label: {
                Label("New Recipe", systemImage: "square.and.pencil")
            }
        } label: {
            Label("Add Recipe", systemImage: "plus")
        }
    }

    private var optionsMenu: some View {
        @Bindable var model = model
        return Menu {
            Section {
                Button {
                    isFilterSheetPresented = true
                } label: {
                    Label(model.filters.isEmpty ? "Filter…" : "Filters (\(model.filters.count))…",
                          systemImage: "line.3.horizontal.decrease")
                }
                Toggle(isOn: $model.filters.favoritesOnly) {
                    Label("Favorites Only", systemImage: "heart")
                }
            }
            Section("Sort By") {
                Picker("Sort By", selection: $model.sort) {
                    ForEach(RecipeSort.allCases, id: \.self) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .pickerStyle(.inline)
            }
            Section {
                Picker("Layout", selection: Binding(get: { layout }, set: { layoutOverride = nil; storedLayout = $0 })) {
                    ForEach(RecipeLayout.allCases) { layout in
                        Label(layout.title, systemImage: layout.systemImage).tag(layout)
                    }
                }
                .pickerStyle(.inline)
            }
        } label: {
            Label("View Options", systemImage: "line.3.horizontal.decrease")
        }
        .accessibilityValue(model.filters.isEmpty ? "" : "\(model.filters.count) filters active")
    }

    // MARK: Debug routes / deep links

    private func consumeIntent() {
        guard let intent = router.consumeIntent("recipes-") else { return }
        let parts = intent.split(separator: "/", maxSplits: 1).map(String.init)
        let argument = parts.count > 1 ? parts[1] : nil
        switch parts.first {
        case "recipes-list": layoutOverride = .list
        case "recipes-grid": layoutOverride = .grid
        case "recipes-filter": isFilterSheetPresented = true
        case "recipes-favorites": model.filters.favoritesOnly = true
        case "recipes-sort":
            if let argument, let sort = RecipeSort(rawValue: argument) { model.sort = sort }
        case "recipes-search":
            model.search = argument ?? ""
        case "recipes-filtered":
            // "tag:dinner,category:pasta"
            for part in (argument ?? "").split(separator: ",") {
                let pieces = part.split(separator: ":", maxSplits: 1).map(String.init)
                guard pieces.count == 2, let kind = OrganizerKind(rawValue: pieces[0]) else { continue }
                let organizer = OrganizerStore.shared.organizer(kind, slug: pieces[1])
                    ?? Organizer(name: pieces[1].replacingOccurrences(of: "-", with: " ").capitalized, slug: pieces[1])
                model.filters.toggle(organizer, kind: kind)
            }
        case "recipes-new": sheet = .newRecipe
        case "recipes-import": sheet = .importRecipe
        case "recipes-select": pendingSelection = PendingSelection(count: 3, layout: nil, sheet: nil)
        case "recipes-select-list": pendingSelection = PendingSelection(count: 3, layout: .list, sheet: nil)
        case "recipes-select-shopping": pendingSelection = PendingSelection(count: 3, layout: nil, sheet: .shopping)
        case "recipes-select-plan": pendingSelection = PendingSelection(count: 3, layout: nil, sheet: .plan)
        case "recipes-select-running": pendingSelection = PendingSelection(count: 3, layout: nil, sheet: .running)
        case "recipes-select-result": pendingSelection = PendingSelection(count: 3, layout: nil, sheet: .result)
        #if DEBUG
        case "recipes-error":
            Task {
                try? await Task.sleep(for: .seconds(1))
                model.simulateError()
            }
        #endif
        default: break
        }
        applyPendingSelection()
    }

    // MARK: Selection actions

    private func loadActionsIfSelecting() async {
        guard selection.isActive else { return }
        if let cached = await mealie.cached([RecipeAction].self, key: "recipes.actions") {
            recipeActions = cached
        }
        if let fresh = try? await mealie.recipeActions() {
            recipeActions = fresh
            await mealie.storeInCache(fresh, key: "recipes.actions")
        }
        actionsLoaded = true
    }

    private func run(_ action: RecipeAction) {
        let recipes = selection.recipes
        if action.isLink {
            guard let recipe = recipes.first else { return }
            let servings = recipe.recipeServings ?? 1
            let page = RecipeLinks.webURL(server: mealie.baseURL, groupSlug: session.currentUser?.groupSlug, slug: recipe.slug)
            if let url = RecipeActionLink.url(template: action.url, summary: recipe, recipeURL: page, scale: 1, servings: servings) {
                openURL(url)
                withAnimation(.snappy) { selection.end() }
            } else {
                toast = RecipeToast(message: "“\(action.title)” has an invalid link", systemImage: "exclamationmark.triangle", isError: true)
            }
            return
        }
        let service = mealie
        exitSelectionOnDismiss = true
        bulkSheet = .job(RecipeBulkJob.each(
            progressTitle: "Sending",
            recipes: recipes,
            successVerb: "Sent",
            failureVerb: "sent",
            destinationPhrase: "to “\(action.title)”"
        ) { recipe in
            try await service.triggerRecipeAction(id: action.id, slug: recipe.slug, scale: 1)
        })
    }

    private func favoriteSelected() {
        let makeFavorite = !favoriteAllSelected
        let recipes = selection.recipes
        let service = mealie
        let userID = session.currentUser?.id
        let data = userData
        exitSelectionOnDismiss = true
        bulkSheet = .job(RecipeBulkJob.each(
            progressTitle: makeFavorite ? "Saving" : "Updating",
            recipes: recipes,
            successVerb: makeFavorite ? "Added" : "Removed",
            failureVerb: makeFavorite ? "added" : "removed",
            destinationPhrase: makeFavorite ? "to favorites" : "from favorites"
        ) { recipe in
            if data.isFavorite(recipe.id) == makeFavorite { return }
            try await data.setFavorite(makeFavorite, recipeID: recipe.id, slug: recipe.slug, mealie: service, userID: userID)
        })
    }

    @ViewBuilder
    private func bulkSheetView(_ bulk: RecipeBulkSheet) -> some View {
        switch bulk {
        case .shopping(let recipes):
            RecipeBulkShoppingSheet(recipes: recipes) { exitSelectionOnDismiss = true }
        case .mealPlan(let recipes):
            RecipeBulkMealPlanSheet(recipes: recipes) { exitSelectionOnDismiss = true }
        case .job(let job):
            RecipeBulkJobSheet(job: job)
        }
    }

    private func dismissBulkSheet() {
        guard exitSelectionOnDismiss else { return }
        exitSelectionOnDismiss = false
        withAnimation(.snappy) { selection.end() }
    }

    private func applyPendingSelection() {
        guard let pending = pendingSelection, !model.items.isEmpty else { return }
        pendingSelection = nil
        if let layout = pending.layout { layoutOverride = layout }
        let chosen = Array(model.items.prefix(max(pending.count, 1)))
        guard let first = chosen.first else { return }
        var state = RecipeSelectionState()
        state.begin(with: first)
        for recipe in chosen.dropFirst() { state.toggle(recipe) }
        selection = state
        switch pending.sheet {
        case nil:
            break
        case .shopping:
            bulkSheet = .shopping(state.recipes)
        case .plan:
            bulkSheet = .mealPlan(state.recipes)
        case .running:
            exitSelectionOnDismiss = true
            bulkSheet = .job(RecipeBulkJob(
                progressTitle: "Sending",
                phase: .running(done: min(1, state.count), total: state.count, current: state.recipes.dropFirst().first?.displayName ?? first.displayName),
                successVerb: "Sent",
                failureVerb: "sent",
                destinationPhrase: "to “Export”",
                recipes: state.recipes
            ))
        case .result:
            exitSelectionOnDismiss = true
            bulkSheet = .job(RecipeBulkJob(
                progressTitle: "Sending",
                phase: .finished(debugResult(for: state.recipes)),
                successVerb: "Sent",
                failureVerb: "sent",
                destinationPhrase: "to “Export”",
                recipes: state.recipes
            ))
        }
    }

    /// A partial-failure summary for the screenshot route. Nothing is sent to the server.
    private func debugResult(for recipes: [RecipeSummary]) -> RecipeBulkResult {
        let failed = Array(recipes.suffix(min(2, recipes.count)))
        let succeeded = recipes.dropLast(failed.count).map(\.displayName)
        let messages = [
            "The server returned an error (500).",
            "Can’t reach your Mealie server. Check your connection and the server address.",
        ]
        return RecipeBulkResult(
            successVerb: "Sent",
            failureVerb: "sent",
            destinationPhrase: "to “Export”",
            succeededNames: succeeded,
            failures: failed.enumerated().map { index, recipe in
                .init(recipeID: recipe.id, recipeName: recipe.displayName, message: messages[index % messages.count])
            },
            notAttempted: 0
        )
    }
}

/// What the selection bar presents. The recipes are a snapshot from the moment the action started.
private enum RecipeBulkSheet: Identifiable {
    case shopping([RecipeSummary])
    case mealPlan([RecipeSummary])
    case job(RecipeBulkJob)

    var id: String {
        switch self {
        case .shopping: "shopping"
        case .mealPlan: "meal-plan"
        case .job(let job): "job-\(job.id)"
        }
    }
}

/// DEBUG / deep-link request to enter selection once the list has recipes.
private struct PendingSelection: Equatable {
    var count: Int
    var layout: RecipeLayout?
    enum Sheet: Equatable { case shopping, plan, running, result }
    var sheet: Sheet?
}

// MARK: - Active filters

/// Removable chips for the active filters, shown above the results.
struct ActiveFilterBar: View {
    @Binding var filters: RecipeFilters
    var onEdit: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                if filters.favoritesOnly {
                    RemovableChip(title: "Favorites", systemImage: "heart.fill") { filters.favoritesOnly = false }
                }
                ForEach(OrganizerKind.allCases, id: \.self) { kind in
                    ForEach(filters.organizers(kind), id: \.slug) { organizer in
                        RemovableChip(title: organizer.name, systemImage: kind.systemImage) { filters.toggle(organizer, kind: kind) }
                    }
                }
                ForEach(filters.foods) { food in
                    RemovableChip(title: food.name, systemImage: "carrot") { filters.toggle(food) }
                }
                Button("Edit", action: onEdit)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, Theme.Spacing.xs)
                    .frame(minHeight: 44)
            }
        }
        .scrollClipDisabled()
    }
}

/// Selected-style chip with a trailing ✕ that removes the filter.
private struct RemovableChip: View {
    let title: String
    let systemImage: String
    let remove: () -> Void

    var body: some View {
        Button {
            withAnimation(.smooth) { remove() }
        } label: {
            HStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: systemImage).imageScale(.small)
                Text(title).lineLimit(1)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .padding(.leading, 2)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.tint)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.16), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove filter \(title)")
    }
}
