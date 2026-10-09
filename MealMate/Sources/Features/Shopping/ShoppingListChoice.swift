import SwiftUI

/// The target list of an "add to shopping list" sheet: the household's lists (cached first),
/// the last used one preselected, and creating a new one when there is none.
/// Shared by `AddToShoppingListSheet` and `MealPlanShoppingSheet`; show it with
/// `ShoppingListPickerRow`.
@MainActor
@Observable
final class ShoppingListChoice {
    private(set) var lists: [ShoppingList] = []
    var selectedListID: String?
    private(set) var phase: Phase = .loading
    /// Creating a list failed.
    var error: MealieError?

    enum Phase: Equatable { case loading, loaded, failed(MealieError) }

    /// `@AppStorage` key of the last list something was added to.
    static let lastListKey = "shopping.lastListID"

    @ObservationIgnored private var mealie: MealieService = .unconfigured

    var selectedList: ShoppingList? { lists.first { $0.id == selectedListID } }

    func load(using mealie: MealieService, lastListID: String?) async {
        self.mealie = mealie
        if lists.isEmpty, let cached = await mealie.cached([ShoppingListsViewModel.Row].self, key: "shopping.lists") {
            lists = cached.map(\.list)
            phase = .loaded
            pickDefaultList(lastListID)
        }
        do {
            lists = try await mealie.shoppingLists()
            phase = .loaded
            pickDefaultList(lastListID)
        } catch {
            let error = MealieError.wrap(error)
            if error != .cancelled, lists.isEmpty { phase = .failed(error) }
        }
    }

    private func pickDefaultList(_ lastListID: String?) {
        if let selectedListID, lists.contains(where: { $0.id == selectedListID }) { return }
        selectedListID = lists.first { $0.id == lastListID }?.id ?? lists.first?.id
    }

    func createList(named name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let list = try await mealie.createShoppingList(name: name)
            lists.append(list)
            selectedListID = list.id
        } catch {
            self.error = MealieError.wrap(error)
        }
    }
}

/// Form row picking the target list: a menu picker, or "New List…" when the household has
/// none yet. Owns the "New List" alert.
struct ShoppingListPickerRow: View {
    @Bindable var choice: ShoppingListChoice

    @State private var creatingList = false
    @State private var newListName = ""

    var body: some View {
        Group {
            switch choice.phase {
            case .loading where choice.lists.isEmpty:
                LabeledContent("List") { ProgressView() }
            case .failed(let error):
                Label(error.errorDescription ?? "Can’t load your lists.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            default:
                if choice.lists.isEmpty {
                    Button("New List…", systemImage: "plus") {
                        newListName = ""
                        creatingList = true
                    }
                } else {
                    Picker("List", selection: $choice.selectedListID) {
                        ForEach(choice.lists) { list in
                            Text(list.displayName).tag(Optional(list.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .alert("New List", isPresented: $creatingList) {
            TextField("Name", text: $newListName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { Task { await choice.createList(named: newListName) } }
        }
        .alert(isPresented: errorBinding, error: choice.error) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.recoverySuggestion ?? "The list wasn’t created. Try again.")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding { choice.error != nil } set: { if !$0 { choice.error = nil } }
    }
}
