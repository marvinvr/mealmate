import SwiftUI

/// The target list of an "add to shopping list" sheet: the household's lists (cached first,
/// newest first), the newest one preselected, and creating a new one.
/// Shared by the add-to-list sheets; show it with `ShoppingListPickerRow`.
@MainActor
@Observable
final class ShoppingListChoice {
    private(set) var lists: [ShoppingList] = []
    var selectedListID: String?
    private(set) var phase: Phase = .loading
    /// Creating a list failed.
    var error: MealieError?

    enum Phase: Equatable { case loading, loaded, failed(MealieError) }

    @ObservationIgnored private var mealie: MealieService = .unconfigured

    var selectedList: ShoppingList? { lists.first { $0.id == selectedListID } }

    func load(using mealie: MealieService) async {
        self.mealie = mealie
        if lists.isEmpty, let cached = await mealie.cached([ShoppingListsViewModel.Row].self, key: "shopping.lists") {
            lists = cached.map(\.list).sorted(by: ShoppingList.newestFirst)
            phase = .loaded
            pickDefaultList()
        }
        do {
            lists = try await mealie.shoppingLists()
            phase = .loaded
            pickDefaultList()
        } catch {
            let error = MealieError.wrap(error)
            if error != .cancelled, lists.isEmpty { phase = .failed(error) }
        }
    }

    /// The newest list, unless the user already picked one.
    private func pickDefaultList() {
        if let selectedListID, lists.contains(where: { $0.id == selectedListID }) { return }
        selectedListID = lists.first?.id
    }

    /// Creates the list, selects it, and returns it. `nil` when the name is empty or Mealie rejects it.
    @discardableResult
    func createList(named name: String) async -> ShoppingList? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        do {
            let list = try await mealie.createShoppingList(name: name)
            lists.append(list)
            lists.sort(by: ShoppingList.newestFirst)
            selectedListID = list.id
            await storeListsInCache()
            return list
        } catch {
            self.error = MealieError.wrap(error)
            return nil
        }
    }

    /// Keeps the Shopping tab's cached rows in step with a list created from another screen.
    private func storeListsInCache() async {
        var rows = await mealie.cached([ShoppingListsViewModel.Row].self, key: "shopping.lists") ?? []
        for list in lists where !rows.contains(where: { $0.id == list.id }) {
            rows.append(.init(list: list, uncheckedCount: list.id == selectedListID ? 0 : nil))
        }
        rows.sort { ShoppingList.newestFirst($0.list, $1.list) }
        await mealie.storeInCache(rows, key: "shopping.lists")
    }
}

/// Form row picking the target list. Pair it with `NewShoppingListButton` in the same section.
struct ShoppingListPickerRow: View {
    @Bindable var choice: ShoppingListChoice

    var body: some View {
        switch choice.phase {
        case .loading where choice.lists.isEmpty:
            LabeledContent("List") { ProgressView() }
        case .failed(let error):
            Label(error.errorDescription ?? "Can’t load your lists.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        default:
            if choice.lists.isEmpty {
                Text("No lists yet")
                    .foregroundStyle(.secondary)
            } else {
                // A menu of toggles rather than a `Picker`: menu pickers drop the date subtitle.
                Menu {
                    ForEach(choice.lists) { list in
                        Toggle(isOn: selectionBinding(list)) {
                            Text(list.displayName)
                            if let created = list.createdText {
                                Text(created)
                            }
                        }
                    }
                } label: {
                    // The whole row opens the menu, like a menu picker.
                    LabeledContent {
                        HStack(spacing: 4) {
                            Text(choice.selectedList?.displayName ?? "Choose")
                            Image(systemName: "chevron.up.chevron.down")
                                .imageScale(.small)
                        }
                        .foregroundStyle(.tint)
                    } label: {
                        Text("List")
                            .foregroundStyle(Color.primary)
                    }
                    .contentShape(.rect)
                }
            }
        }
    }

    private func selectionBinding(_ list: ShoppingList) -> Binding<Bool> {
        Binding { choice.selectedListID == list.id } set: { if $0 { choice.selectedListID = list.id } }
    }
}

/// "New List…" for an add-to-list sheet. Asks for a name, creates the list, then calls
/// `onCreated` so the sheet adds the recipes to it.
struct NewShoppingListButton: View {
    @Bindable var choice: ShoppingListChoice
    var onCreated: () -> Void = {}

    @State private var creatingList = false
    @State private var newListName = ""

    var body: some View {
        Button("New List…", systemImage: "plus") {
            newListName = ShoppingListNames.suggestion(avoiding: choice.lists.map(\.displayName))
            creatingList = true
        }
        .disabled(choice.phase == .loading && choice.lists.isEmpty)
        .alert("New List", isPresented: $creatingList) {
            TextField("Name", text: $newListName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                Task {
                    guard await choice.createList(named: newListName) != nil else { return }
                    onCreated()
                }
            }
            .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("The recipes are added to this list.")
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

extension ShoppingList {
    /// Creation date as quiet secondary text ("Oct 12"; with the year when it isn't this year).
    var createdText: String? {
        guard let createdAt else { return nil }
        let sameYear = Calendar.current.isDate(createdAt, equalTo: .now, toGranularity: .year)
        return sameYear
            ? createdAt.formatted(.dateTime.month(.abbreviated).day())
            : createdAt.formatted(date: .abbreviated, time: .omitted)
    }
}
