import SwiftUI

/// All shopping lists with their unchecked counts.
@MainActor
@Observable
final class ShoppingListsViewModel {
    struct Row: Identifiable, Hashable, Codable, Sendable {
        var list: ShoppingList
        /// `nil` until the list's items have been fetched.
        var uncheckedCount: Int?
        var id: String { list.id }
    }

    private(set) var rows: [Row] = []
    private(set) var phase: Phase = .loading
    private(set) var refreshError: String?
    var actionError: MealieError?
    private(set) var errorFeedback = 0

    enum Phase: Equatable {
        case loading, loaded
        case failed(MealieError)
    }

    @ObservationIgnored private var mealie: MealieService = .unconfigured
    private static let cacheKey = "shopping.lists"

    func load(using mealie: MealieService) async {
        self.mealie = mealie
        if rows.isEmpty, let cached = await mealie.cached([Row].self, key: Self.cacheKey) {
            rows = cached
            phase = .loaded
        }
        await refresh()
    }

    func refresh() async {
        do {
            let lists = try await mealie.shoppingLists()
            // The list endpoint has no items: fetch each list for its count (in parallel).
            let mealie = mealie
            let details = await withTaskGroup(of: ShoppingList?.self) { group in
                for list in lists {
                    group.addTask { try? await mealie.shoppingList(id: list.id) }
                }
                var result: [String: ShoppingList] = [:]
                for await case let list? in group { result[list.id] = list }
                return result
            }
            let previous = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.uncheckedCount) })
            withAnimation(.snappy) {
                rows = lists.map { list in
                    let count = details[list.id].map { ShoppingListLayout.uncheckedCount($0.items) } ?? previous[list.id] ?? nil
                    return Row(list: list, uncheckedCount: count)
                }
            }
            phase = .loaded
            refreshError = nil
            await mealie.storeInCache(rows, key: Self.cacheKey)
            for detail in details.values {
                await mealie.storeInCache(detail, key: "shopping.list.\(detail.id)")
            }
        } catch {
            let error = MealieError.wrap(error)
            if error == .cancelled { return }
            if rows.isEmpty && phase != .loaded {
                phase = .failed(error)
            } else {
                refreshError = error.errorDescription
            }
        }
    }

    @discardableResult
    func create(name: String) async -> ShoppingList? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        do {
            let list = try await mealie.createShoppingList(name: name)
            withAnimation(.snappy) {
                rows.append(Row(list: list, uncheckedCount: 0))
                rows.sort { $0.list.displayName.localizedStandardCompare($1.list.displayName) == .orderedAscending }
            }
            await mealie.storeInCache(rows, key: Self.cacheKey)
            return list
        } catch {
            fail(error)
            return nil
        }
    }

    func rename(_ row: Row, to name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != row.list.name, let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        let original = row
        rows[index].list.name = name
        do {
            try await mealie.renameShoppingList(id: row.id, to: name)
            await mealie.storeInCache(rows, key: Self.cacheKey)
        } catch {
            if let index = rows.firstIndex(where: { $0.id == original.id }) { rows[index] = original }
            fail(error)
        }
    }

    func delete(_ row: Row) async {
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        _ = withAnimation(.snappy) { rows.remove(at: index) }
        do {
            try await mealie.deleteShoppingList(id: row.id)
            await mealie.storeInCache(rows, key: Self.cacheKey)
        } catch {
            withAnimation(.snappy) { rows.insert(row, at: min(index, rows.count)) }
            fail(error)
        }
    }

    private func fail(_ error: Error) {
        let error = MealieError.wrap(error)
        guard error != .cancelled else { return }
        actionError = error
        errorFeedback += 1
    }
}
