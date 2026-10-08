import SwiftUI

/// A recipe list for one preset: favorites, a cookbook, a category / tag / tool
/// (`AppDestination.cookbook`, `.organizer`). Same grid/list, search and sort as the
/// Recipes tab.
struct RecipeCollectionScreen: View {
    let preset: RecipeCollectionPreset
    @Environment(\.mealie) private var mealie

    var body: some View {
        RecipeCollectionScreenContent(preset: preset, mealie: mealie)
            .id("\(mealie.cacheScope)|\(preset.cacheKey)")
    }
}

private struct RecipeCollectionScreenContent: View {
    let preset: RecipeCollectionPreset

    @State private var model: RecipeListModel
    @State private var store = OrganizerStore.shared
    @State private var cookbook: Cookbook?
    @State private var organizer: Organizer?
    @State private var sheet: RecipeSheet?
    @State private var toast: RecipeToast?
    @AppStorage("recipes.layout") private var layout: RecipeLayout = .grid
    @Environment(\.mealie) private var mealie

    init(preset: RecipeCollectionPreset, mealie: MealieService) {
        self.preset = preset
        let sort: RecipeSort = switch preset {
        case .favorites: .name
        default: .recentlyAdded
        }
        _model = State(initialValue: RecipeListModel(preset: preset, sort: sort, mealie: mealie))
    }

    var body: some View {
        @Bindable var model = model
        RecipeCollectionContent(
            model: model,
            layout: layout,
            emptyTitle: emptyTitle,
            emptyMessage: emptyMessage,
            emptySystemImage: systemImage,
            header: header,
            sheet: $sheet,
            toast: $toast
        )
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $model.search, prompt: "Search \(title)")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort By", selection: $model.sort) {
                        ForEach(RecipeSort.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Section {
                        Picker("Layout", selection: $layout) {
                            ForEach(RecipeLayout.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                        }
                        .pickerStyle(.inline)
                    }
                } label: {
                    Label("View Options", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .task(id: model.key) { await model.keyChanged() }
        .task { await loadInfo() }
        .sheet(item: $sheet) { RecipeSheetView(sheet: $0) }
        .recipeToast($toast)
    }

    private var title: String {
        switch preset {
        case .all: "Recipes"
        case .favorites: "Favorites"
        case .cookbook: cookbook?.name ?? "Cookbook"
        case .organizer(let kind, let slug):
            organizer?.name ?? store.organizer(kind, slug: slug)?.name
                ?? slug.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    private var systemImage: String {
        switch preset {
        case .all: "book.pages"
        case .favorites: "heart"
        case .cookbook: "book.closed"
        case .organizer(let kind, _): kind.systemImage
        }
    }

    private var emptyTitle: String {
        switch preset {
        case .cookbook: "No Recipes in This Cookbook"
        case .organizer(let kind, _): "No Recipes With This \(kind.singularTitle)"
        default: "No Recipes Yet"
        }
    }

    private var emptyMessage: String {
        switch preset {
        case .cookbook: "Recipes matching the cookbook’s filters will show up here. Edit the cookbook in Mealie to change them."
        case .organizer(let kind, _): "Add this \(kind.singularTitle.lowercased()) to a recipe in Mealie and it will show up here."
        default: "Import one from a website or create your own."
        }
    }

    private var header: AnyView? {
        guard case .cookbook = preset,
              let description = cookbook?.description?.trimmingCharacters(in: .whitespacesAndNewlines),
              !description.isEmpty else { return nil }
        return AnyView(
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        )
    }

    private func loadInfo() async {
        switch preset {
        case .cookbook(let id):
            cookbook = store.cookbooks.first { $0.id == id || $0.slug == id }
            if cookbook == nil, let cached = await mealie.cached(Cookbook.self, key: "library.cookbook.\(id)") { cookbook = cached }
            if let fresh = try? await mealie.cookbook(id: id) {
                cookbook = fresh
                await mealie.storeInCache(fresh, key: "library.cookbook.\(id)")
            }
        case .organizer(let kind, let slug):
            organizer = store.organizer(kind, slug: slug)
            if organizer == nil { organizer = try? await mealie.organizer(kind, slug: slug) }
        default:
            break
        }
    }
}
