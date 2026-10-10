import SwiftUI

/// "Add to Shopping List" for the meal plan: the week's planned recipes by day (notes are
/// left out), each toggleable, and the target list (last used preselected). Today and later
/// start ticked; opened for one day, only that day is shown. Everything goes to Mealie in one
/// `POST …/lists/{id}/recipe` (`MealPlanShopping.requests`).
///
/// ```swift
/// .sheet(item: $shopping) { MealPlanShoppingSheet(week: model.week, entries: model.entries, day: $0.day) }
/// ```
struct MealPlanShoppingSheet: View {
    let week: MealPlanWeek
    let entries: [MealPlanEntry]
    /// Shop for this day only.
    var day: MealieDay?

    @Environment(\.mealie) private var mealie
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ShoppingListChoice.lastListKey) private var lastListID = ""

    @State private var model: MealPlanShoppingModel?
    @State private var toast: ActionToast?
    @State private var successFeedback = 0
    @State private var errorFeedback = 0

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    if model.days.isEmpty {
                        empty
                    } else {
                        form(model)
                    }
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
                if model?.days.isEmpty == false {
                    ToolbarItem(placement: .confirmationAction) {
                        if model?.isAdding == true {
                            ProgressView()
                        } else {
                            Button("Add", systemImage: "checkmark") { Task { await add() } }
                                .disabled(model?.canAdd != true || toast != nil)
                        }
                    }
                }
            }
            .actionToast($toast)
        }
        // iPad: room for a week of recipes.
        .presentationSizing(.page)
        .sensoryFeedback(.success, trigger: successFeedback)
        .sensoryFeedback(.error, trigger: errorFeedback)
        .task {
            if model == nil {
                model = MealPlanShoppingModel(week: week, entries: entries, day: day)
            }
            if model?.days.isEmpty == false {
                await model?.load(using: mealie, lastListID: lastListID)
            }
        }
        .alert(isPresented: errorBinding, error: model?.error) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.recoverySuggestion ?? "Nothing was added. Try again.")
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label(day == nil ? "No Recipes This Week" : "No Recipes This Day", systemImage: "cart")
        } description: {
            Text("Plan a recipe first, then add its ingredients to a shopping list from here.")
        }
    }

    private func form(_ model: MealPlanShoppingModel) -> some View {
        Form {
            Section {
                ShoppingListPickerRow(choice: model.destination)
                NewShoppingListButton(choice: model.destination) {
                    Task { await add() }
                }
            } footer: {
                Text("Adds each recipe’s ingredients as written, once per planned meal.")
            }

            ForEach(model.days) { day in
                Section {
                    ForEach(day.entries) { entry in
                        MealPlanShoppingRow(entry: entry, isSelected: model.selection.contains(entry.id)) {
                            model.toggle(entry.id)
                        }
                    }
                } header: {
                    Text("\(day.day.relativeName()), \(day.day.shortDate)")
                }
            }
        }
        .sensoryFeedback(.selection, trigger: model.selection)
    }

    private func add() async {
        guard let model, let count = await model.add() else {
            errorFeedback += 1
            return
        }
        lastListID = model.destination.selectedListID ?? lastListID
        successFeedback += 1
        let listName = model.destination.selectedList?.displayName ?? "your list"
        let meals = count == 1 ? "1 meal" : "\(count) meals"
        toast = ActionToast(message: "Added ingredients for \(meals) to \(listName)", duration: .seconds(2))
        try? await Task.sleep(for: .seconds(1.2))
        dismiss()
    }

    private var errorBinding: Binding<Bool> {
        Binding { model?.error != nil } set: { if !$0 { model?.error = nil } }
    }
}

// MARK: - Model

@MainActor
@Observable
final class MealPlanShoppingModel {
    /// Days with planned recipes.
    let days: [MealPlanShopping.Day]
    /// Ticked entry ids.
    var selection: Set<Int>
    /// The list to add to.
    let destination = ShoppingListChoice()
    private(set) var isAdding = false
    var error: MealieError?

    @ObservationIgnored private var mealie: MealieService = .unconfigured

    init(week: MealPlanWeek, entries: [MealPlanEntry], day: MealieDay?, today: MealieDay = .today) {
        var days = MealPlanShopping.days(entries, in: week)
        if let day { days = days.filter { $0.day == day } }
        self.days = days
        selection = MealPlanShopping.defaultSelection(days, today: today, only: day)
    }

    var canAdd: Bool { destination.selectedListID != nil && !selection.isEmpty && !isAdding }

    func toggle(_ id: Int) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    func load(using mealie: MealieService, lastListID: String?) async {
        self.mealie = mealie
        await destination.load(using: mealie, lastListID: lastListID)
    }

    /// Adds the ticked meals' recipes; returns the number of meals, or `nil` on failure.
    func add() async -> Int? {
        guard let listID = destination.selectedListID else { return nil }
        let chosen = days.flatMap(\.entries).filter { selection.contains($0.id) }
        let requests = MealPlanShopping.requests(for: chosen)
        guard !requests.isEmpty else { return nil }
        isAdding = true
        defer { isAdding = false }
        do {
            let updated = try await mealie.addRecipesToShoppingList(listID: listID, recipes: requests)
            await mealie.storeInCache(updated, key: "shopping.list.\(listID)")
            return chosen.count
        } catch {
            self.error = MealieError.wrap(error)
            return nil
        }
    }
}

// MARK: - Row

private struct MealPlanShoppingRow: View {
    let entry: MealPlanEntry
    let isSelected: Bool
    var toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                PlanningRecipeThumbnail(recipe: entry.recipe, size: 44)
                    .opacity(isSelected ? 1 : 0.6)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Image(systemName: entry.entryType.systemImage)) \(entry.entryType.title)")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(entry.displayTitle)
                        .font(.recipeRowTitle)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.entryType.title): \(entry.displayTitle)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isSelected ? "Will be added." : "Won’t be added.")
    }
}
