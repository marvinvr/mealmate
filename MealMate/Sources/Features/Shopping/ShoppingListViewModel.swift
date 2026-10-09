import SwiftUI

/// One shopping list: cached-first loading, optimistic check/edit/delete with rollback,
/// add-by-free-text and recipe references.
@MainActor
@Observable
final class ShoppingListViewModel {
    let listID: String

    private(set) var list: ShoppingList?
    private(set) var items: [ShoppingListItem] = []
    private(set) var phase: Phase = .loading
    /// A background refresh failed while cached content is shown.
    private(set) var refreshError: String?
    /// A user action failed (shown as an alert; the change was rolled back).
    var actionError: MealieError?

    /// Just-checked items that stay in their section briefly (see `ShoppingListLayout`).
    private(set) var lingering: Set<String> = []

    // Haptic triggers.
    private(set) var checkFeedback = 0
    private(set) var errorFeedback = 0

    enum Phase: Equatable {
        case loading
        case loaded
        case failed(MealieError)
    }

    @ObservationIgnored private var mealie: MealieService = .unconfigured
    /// Increments on every local mutation, so a refresh that started before it doesn't
    /// overwrite the optimistic state with stale server data.
    @ObservationIgnored private var mutationGeneration = 0
    @ObservationIgnored private var inFlight = 0

    init(listID: String) {
        self.listID = listID
    }

    var cacheKey: String { "shopping.list.\(listID)" }
    var title: String { list?.displayName ?? "Shopping List" }

    var sections: [ShoppingSection] {
        ShoppingListLayout.sections(for: items, labelSettings: list?.labelSettings, keepInPlace: lingering)
    }

    var checkedItems: [ShoppingListItem] {
        ShoppingListLayout.checkedItems(items, excluding: lingering)
    }

    var uncheckedCount: Int { ShoppingListLayout.uncheckedCount(items) }

    /// Everything `clearChecked()` removes, including items still lingering in place.
    var clearableCount: Int { items.lazy.filter(\.checked).count }

    var recipeReferences: [ShoppingListRecipeReference] {
        (list?.recipeReferences ?? []).sorted { ($0.recipe?.displayName ?? "") < ($1.recipe?.displayName ?? "") }
    }

    /// Names of the recipes an item came from.
    func recipeNames(for item: ShoppingListItem) -> [String] {
        let names = list?.recipeNamesByID ?? [:]
        return item.recipeIDs.compactMap { names[$0] }
    }

    // MARK: Loading

    func load(using mealie: MealieService) async {
        self.mealie = mealie
        if list == nil, let cached = await mealie.cached(ShoppingList.self, key: cacheKey) {
            apply(list: cached)
            phase = .loaded
        }
        await refresh()
    }

    func refresh() async {
        let generation = mutationGeneration
        do {
            let fresh = try await mealie.shoppingList(id: listID)
            guard generation == mutationGeneration, inFlight == 0 else { return }
            apply(list: fresh)
            phase = .loaded
            refreshError = nil
            await mealie.storeInCache(fresh, key: cacheKey)
        } catch let error as MealieError where error == .cancelled {
            return
        } catch {
            let error = MealieError.wrap(error)
            if error == .cancelled { return }
            if list == nil {
                phase = .failed(error)
            } else {
                refreshError = error.errorDescription
            }
        }
    }

    /// Light polling while the list is on screen, so changes from other devices show up.
    func poll(every interval: Duration = .seconds(15)) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    private func apply(list: ShoppingList) {
        self.list = list
        // Keep optimistic placeholders that the server hasn't confirmed yet.
        let pending = items.filter(\.isPending)
        items = list.items + pending
    }

    private func persist() {
        guard var list else { return }
        list.listItems = items.filter { !$0.isPending }
        self.list = list
        let mealie = mealie
        let key = cacheKey
        Task { await mealie.storeInCache(list, key: key) }
    }

    // MARK: Mutations

    /// Runs an optimistic change: `change` mutates local state, `request` talks to the
    /// server; on failure `rollback` undoes just this change and the error is shown.
    private func mutate(
        _ change: () -> Void,
        rollback: @escaping () -> Void,
        request: @escaping @Sendable (MealieService) async throws -> ShoppingListItemsCollection?
    ) async {
        mutationGeneration += 1
        inFlight += 1
        withAnimation(.snappy) { change() }
        defer { inFlight -= 1 }
        do {
            if let collection = try await request(mealie) {
                withAnimation(.snappy) { apply(collection) }
            }
            persist()
        } catch {
            let error = MealieError.wrap(error)
            withAnimation(.snappy) { rollback() }
            if error != .cancelled {
                actionError = error
                errorFeedback += 1
            }
        }
    }

    /// Applies Mealie's create/update/delete result (it merges duplicates server-side).
    private func apply(_ collection: ShoppingListItemsCollection) {
        let deleted = Set(collection.deletedItems.map(\.id))
        items.removeAll { deleted.contains($0.id) }
        for item in collection.updatedItems + collection.createdItems where item.shoppingListId == listID {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = item
            } else {
                items.append(item)
            }
        }
    }

    func toggle(_ item: ShoppingListItem) async {
        guard !item.isPending else { return }
        let checking = !item.checked
        var updated = item
        updated.checked = checking
        updated.updatedAt = .now
        let payload = updated.update
        checkFeedback += 1
        await mutate({
            replace(updated)
            if checking { lingering.insert(item.id) } else { lingering.remove(item.id) }
        }, rollback: { [weak self] in
            self?.replace(item)
            self?.lingering.remove(item.id)
        }, request: { try await $0.updateShoppingItem(payload) })
        if checking {
            try? await Task.sleep(for: .milliseconds(700))
            _ = withAnimation(.snappy) { lingering.remove(item.id) }
        }
    }

    func delete(_ item: ShoppingListItem) async {
        guard !item.isPending else { return }
        let id = item.id
        await mutate({ items.removeAll { $0.id == id } }, rollback: { [weak self] in
            self?.items.append(item)
        }, request: {
            try await $0.deleteShoppingItem(id: id)
            return nil
        })
    }

    func save(_ edited: ShoppingListItem) async {
        guard let original = items.first(where: { $0.id == edited.id }) else { return }
        var edited = edited
        edited.display = nil // the server renders it again
        let payload = edited.update
        await mutate({ replace(edited) }, rollback: { [weak self] in
            self?.replace(original)
        }, request: { try await $0.updateShoppingItem(payload) })
    }

    func clearChecked() async {
        let removed = items.filter(\.checked)
        let ids = removed.map(\.id)
        guard !ids.isEmpty else { return }
        await mutate({ items.removeAll { $0.checked } }, rollback: { [weak self] in
            self?.items.append(contentsOf: removed)
        }, request: {
            try await $0.deleteShoppingItems(ids: ids)
            return nil
        })
    }

    func uncheckAll() async {
        let checked = items.filter(\.checked)
        guard !checked.isEmpty else { return }
        let updates = checked.map { item -> ShoppingListItemUpdate in
            var update = item.update
            update.checked = false
            return update
        }
        checkFeedback += 1
        let ids = Set(checked.map(\.id))
        await mutate({
            for index in items.indices where items[index].checked { items[index].checked = false }
        }, rollback: { [weak self] in
            guard let self else { return }
            for index in items.indices where ids.contains(items[index].id) { items[index].checked = true }
        }, request: { try await $0.updateShoppingItems(updates) })
    }

    /// Parses free text with Mealie's ingredient parser and adds it. Falls back to a
    /// note-only item when parsing fails.
    func add(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let placeholder = ShoppingItemDraft.placeholder(for: trimmed, listID: listID)
        let listID = listID
        await mutate({ items.append(placeholder) }, rollback: {}, request: { mealie in
            let parsed = try? await mealie.parseIngredient(trimmed)
            let item = ShoppingItemDraft.item(from: parsed, input: trimmed, listID: listID)
            return try await mealie.addShoppingItem(item)
        })
        items.removeAll { $0.id == placeholder.id }
    }

    /// Removes the (unchecked) items that came from a recipe.
    func remove(_ reference: ShoppingListRecipeReference) async {
        let listID = listID
        let recipeID = reference.recipeId
        let quantity = reference.recipeQuantity ?? 1
        mutationGeneration += 1
        inFlight += 1
        defer { inFlight -= 1 }
        do {
            let updated = try await mealie.removeRecipeFromShoppingList(listID: listID, recipeID: recipeID, quantity: quantity)
            withAnimation(.snappy) { apply(list: updated) }
            await mealie.storeInCache(updated, key: cacheKey)
        } catch {
            let error = MealieError.wrap(error)
            if error != .cancelled {
                actionError = error
                errorFeedback += 1
            }
        }
    }

    /// The list's labels in section order ("Reorder Sections").
    var orderedLabelSettings: [ShoppingList.LabelSetting] {
        ShoppingListLayout.orderedLabelSettings(list?.labelSettings ?? [])
    }

    /// Saves a new section order. Optimistic: the list regroups right away and rolls back
    /// if Mealie rejects it.
    func reorderSections(_ ordered: [ShoppingList.LabelSetting]) async {
        guard let original = list?.labelSettings else { return }
        let updated = ShoppingListLayout.renumbered(ordered)
        guard updated != ShoppingListLayout.renumbered(orderedLabelSettings) else { return }
        let body = ShoppingListLayout.labelSettingUpdates(updated, listID: listID)
        mutationGeneration += 1
        inFlight += 1
        defer { inFlight -= 1 }
        withAnimation(.snappy) { list?.labelSettings = updated }
        do {
            let saved = try await mealie.updateShoppingListLabelSettings(listID: listID, settings: body)
            if let settings = saved.labelSettings, !settings.isEmpty {
                withAnimation(.snappy) { list?.labelSettings = settings }
            }
            persist()
        } catch {
            let error = MealieError.wrap(error)
            withAnimation(.snappy) { list?.labelSettings = original }
            if error != .cancelled {
                actionError = error
                errorFeedback += 1
            }
        }
    }

    private func replace(_ item: ShoppingListItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        }
    }
}
