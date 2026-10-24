import SwiftUI

/// The household's shopping lists, newest first, for the recipe context menu. A menu can't
/// load anything when it opens, so recipe lists load this when they appear.
///
/// Cached-first (the Shopping tab's `shopping.lists` rows), then refreshed. Scoped to the
/// server: a different `MealieService` (sign-out / other server) starts empty.
@MainActor
@Observable
final class RecipeShoppingLists {
    static let shared = RecipeShoppingLists()

    /// `nil` until loaded once (the menu then falls back to the add-to-list sheet).
    private(set) var lists: [ShoppingList]?

    @ObservationIgnored private var scope: String?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    private static let cacheKey = "shopping.lists"

    /// Where "Add to Shopping List" adds: the most recently created list.
    var newest: ShoppingList? { lists?.first }

    func load(_ mealie: MealieService) async {
        resetIfNeeded(for: mealie)
        if lists == nil, let cached = await mealie.cached([ShoppingListsViewModel.Row].self, key: Self.cacheKey) {
            lists = Self.newestFirst(cached.map(\.list))
        }
        if let loadTask { return await loadTask.value }
        let task = Task {
            if let fresh = try? await mealie.shoppingLists() {
                lists = Self.newestFirst(fresh)
            }
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    /// Creates a list, puts it first, and keeps the Shopping tab's cached rows in step.
    func create(named name: String, mealie: MealieService) async throws -> ShoppingList {
        let list = try await mealie.createShoppingList(name: name)
        lists = [list] + (lists ?? []).filter { $0.id != list.id }
        var rows = await mealie.cached([ShoppingListsViewModel.Row].self, key: Self.cacheKey) ?? []
        if !rows.contains(where: { $0.id == list.id }) {
            rows.insert(.init(list: list, uncheckedCount: 0), at: 0)
            await mealie.storeInCache(rows, key: Self.cacheKey)
        }
        return list
    }

    private static func newestFirst(_ lists: [ShoppingList]) -> [ShoppingList] {
        lists.sorted {
            switch ($0.createdAt, $1.createdAt) {
            case let (lhs?, rhs?) where lhs != rhs: lhs > rhs
            case (_?, nil): true
            case (nil, _?): false
            default: $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
        }
    }

    private func resetIfNeeded(for mealie: MealieService) {
        let newScope = mealie.cacheScope + "|" + String((mealie.token ?? "").hashValue)
        guard scope != newScope else { return }
        scope = newScope
        lists = nil
    }
}

/// "Add to Shopping List" in the recipe context menu: one tap adds the recipe to the newest
/// list (its name as the subtitle); "Other List" picks another list, a new one, or opens the
/// sheet to choose ingredients. Foods marked on hand are left out, as in the sheet.
struct RecipeShoppingListMenu: View {
    let recipe: RecipeSummary
    @Binding var sheet: RecipeSheet?
    @Binding var toast: RecipeToast?
    /// Asks the host (outside the menu, which closes on tap) for a new list's name.
    var onNewList: () -> Void

    @Environment(\.mealie) private var mealie
    @Environment(AppSession.self) private var session
    @State private var store = RecipeShoppingLists.shared

    var body: some View {
        if let lists = store.lists {
            Button {
                if let newest = store.newest { add(to: newest) } else { onNewList() }
            } label: {
                Label("Add to Shopping List", systemImage: "cart.badge.plus")
                if let newest = store.newest { Text(newest.displayName) }
            }
            Menu {
                ForEach(lists.dropFirst()) { list in
                    Button(list.displayName) { add(to: list) }
                }
                Section {
                    Button("New List…", systemImage: "plus", action: onNewList)
                    Button("Choose Ingredients…", systemImage: "checklist") {
                        sheet = .addToShoppingList(slug: recipe.slug)
                    }
                }
            } label: {
                Label("Other List", systemImage: "list.bullet")
            }
        } else {
            Button {
                sheet = .addToShoppingList(slug: recipe.slug)
            } label: {
                Label("Add to Shopping List", systemImage: "cart.badge.plus")
            }
        }
    }

    private func add(to list: ShoppingList) {
        RecipeQuickAdd.add(recipe, to: list, mealie: mealie, householdSlug: session.currentUser?.householdSlug, toast: $toast)
    }
}

/// Adds a recipe's ingredients (minus foods on hand) to a list without the sheet, then
/// reports the result in the recipe toast.
@MainActor
enum RecipeQuickAdd {
    static func add(_ recipe: RecipeSummary, to list: ShoppingList, mealie: MealieService,
                    householdSlug: String?, toast: Binding<RecipeToast?>) {
        Task {
            let full: Recipe
            do {
                full = try await mealie.recipe(slug: recipe.slug)
            } catch {
                toast.wrappedValue = RecipeToast(message: "Couldn’t add to \(list.displayName)", systemImage: "exclamationmark.triangle", isError: true)
                return
            }
            let model = AddToShoppingListModel(recipe: full, scale: 1, householdSlug: householdSlug)
            guard !model.selection.isEmpty else {
                let message = model.ingredients.isEmpty ? "This recipe has no ingredients" : "Everything’s already on hand"
                toast.wrappedValue = RecipeToast(message: message, systemImage: "cart")
                return
            }
            if let count = await model.add(to: list.id, using: mealie) {
                let items = count == 1 ? "1 item" : "\(count) items"
                toast.wrappedValue = RecipeToast(message: "Added \(items) to \(list.displayName)", systemImage: "cart.badge.plus")
            } else {
                toast.wrappedValue = RecipeToast(message: "Couldn’t add to \(list.displayName)", systemImage: "exclamationmark.triangle", isError: true)
                await RecipeShoppingLists.shared.load(mealie)
            }
        }
    }
}

/// Name prompt for "New List…" in the recipe context menu. Creates the list, then adds the recipe.
struct RecipeNewListAlert: ViewModifier {
    @Binding var isPresented: Bool
    let recipe: RecipeSummary
    @Binding var toast: RecipeToast?

    @Environment(\.mealie) private var mealie
    @Environment(AppSession.self) private var session
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert("New List", isPresented: $isPresented) {
                TextField("Name", text: $name)
                Button("Cancel", role: .cancel) {}
                Button("Create", action: create)
                    .disabled(trimmedName.isEmpty)
            } message: {
                Text("\(recipe.displayName) is added to this list.")
            }
            .onChange(of: isPresented) { _, presented in
                if presented { name = "" }
            }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func create() {
        let name = trimmedName
        guard !name.isEmpty else { return }
        Task {
            do {
                let list = try await RecipeShoppingLists.shared.create(named: name, mealie: mealie)
                RecipeQuickAdd.add(recipe, to: list, mealie: mealie, householdSlug: session.currentUser?.householdSlug, toast: $toast)
            } catch {
                toast = RecipeToast(message: "Couldn’t create the list", systemImage: "exclamationmark.triangle", isError: true)
            }
        }
    }
}
