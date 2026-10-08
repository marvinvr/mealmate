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

    @Environment(\.mealie) private var mealie
    @Environment(AppRouter.self) private var router

    init(mealie: MealieService) {
        let sort = RecipeSort(rawValue: UserDefaults.standard.string(forKey: "recipes.sort") ?? "") ?? .recentlyAdded
        _model = State(initialValue: RecipeListModel(preset: .all, sort: sort, mealie: mealie))
    }

    private var layout: RecipeLayout { layoutOverride ?? storedLayout }

    var body: some View {
        @Bindable var model = model
        RecipeCollectionContent(
            model: model,
            layout: layout,
            onClearFilters: { withAnimation(.smooth) { model.clearFilters() } },
            header: model.filters.isEmpty ? nil : AnyView(ActiveFilterBar(filters: $model.filters, onEdit: { isFilterSheetPresented = true })),
            sheet: $sheet,
            toast: $toast
        )
        .navigationTitle("Recipes")
        .searchable(text: $model.search, prompt: "Search recipes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { addMenu }
            ToolbarItem(placement: .topBarTrailing) { optionsMenu }
        }
        .task(id: model.key) { await model.keyChanged() }
        .task { await RecipeUserData.shared.load(mealie) }
        .onChange(of: model.sort) { _, sort in storedSort = sort.rawValue }
        .onAppear(perform: consumeIntent)
        .onChange(of: router.pendingIntent) { _, _ in consumeIntent() }
        .sheet(isPresented: $isFilterSheetPresented) {
            RecipeFilterSheet(filters: $model.filters)
        }
        .sheet(item: $sheet, onDismiss: { Task { await model.reload() } }) { sheet in
            RecipeSheetView(sheet: sheet)
        }
        .recipeToast($toast)
    }

    // MARK: Toolbar

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
        #if DEBUG
        case "recipes-error":
            Task {
                try? await Task.sleep(for: .seconds(1))
                model.simulateError()
            }
        #endif
        default: break
        }
    }
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
