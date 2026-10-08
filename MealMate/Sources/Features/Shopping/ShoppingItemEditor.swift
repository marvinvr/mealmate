import SwiftUI

/// Edit one shopping item: quantity, unit, food, note and label.
struct ShoppingItemEditor: View {
    @Environment(\.mealie) private var mealie
    @Environment(\.dismiss) private var dismiss

    let original: ShoppingListItem
    var recipeNames: [String] = []
    var onSave: (ShoppingListItem) -> Void

    @State private var item: ShoppingListItem
    @State private var quantityText: String
    @State private var catalog = ShoppingCatalog()
    @FocusState private var focusedField: Field?

    private enum Field { case quantity, note }

    init(item: ShoppingListItem, recipeNames: [String] = [], onSave: @escaping (ShoppingListItem) -> Void) {
        original = item
        self.recipeNames = recipeNames
        self.onSave = onSave
        _item = State(initialValue: item)
        _quantityText = State(initialValue: Self.format(item.quantity))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Quantity") {
                        TextField("None", text: $quantityText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .quantity)
                            .monospacedDigit()
                    }
                    NavigationLink {
                        UnitPicker(selection: $item.unit, units: catalog.units)
                    } label: {
                        LabeledContent("Unit", value: item.unit?.name ?? "None")
                    }
                    NavigationLink {
                        FoodPicker(selection: foodBinding)
                    } label: {
                        LabeledContent("Food", value: item.food?.name ?? "None")
                    }
                    TextField("Note", text: noteBinding, axis: .vertical)
                        .focused($focusedField, equals: .note)
                } footer: {
                    Text(previewText)
                }

                Section {
                    Picker("Label", selection: labelBinding) {
                        Text("No Label").tag(String?.none)
                        ForEach(catalog.labels) { label in
                            Text(label.name).tag(Optional(label.id))
                        }
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    Text("Items are grouped by label in the list.")
                }

                if !recipeNames.isEmpty {
                    Section("Added From") {
                        ForEach(recipeNames, id: \.self) { name in
                            Label(name, systemImage: "book.pages")
                        }
                    }
                }
            }
            .screenBackground()
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") { save() }
                        .disabled(!hasChanges)
                }
            }
            .task { await catalog.load(using: mealie) }
        }
    }

    // MARK: Bindings

    private var foodBinding: Binding<IngredientFood?> {
        Binding {
            item.food
        } set: { food in
            item.food = food
            item.foodId = food?.id
            // Follow the food's label unless the user picked a different one.
            if let labelId = food?.labelId ?? food?.label?.id {
                item.labelId = labelId
                item.label = food?.label ?? catalog.labels.first { $0.id == labelId }
            }
        }
    }

    private var noteBinding: Binding<String> {
        Binding { item.note ?? "" } set: { item.note = $0 }
    }

    private var labelBinding: Binding<String?> {
        Binding {
            item.labelId ?? item.label?.id
        } set: { id in
            item.labelId = id
            item.label = id.flatMap { id in catalog.labels.first { $0.id == id } }
        }
    }

    // MARK: Helpers

    private var parsedQuantity: Double? {
        let text = quantityText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if text.isEmpty { return 0 }
        return Double(text)
    }

    private var edited: ShoppingListItem {
        var edited = item
        edited.quantity = parsedQuantity ?? item.quantity
        edited.unitId = item.unit?.id
        edited.display = nil
        return edited
    }

    private var hasChanges: Bool {
        let edited = edited
        return edited.quantity != original.quantity || edited.unitId != original.unitId
            || edited.foodId != original.foodId || (edited.note ?? "") != (original.note ?? "")
            || edited.labelId != original.labelId
    }

    private var previewText: String {
        let text = edited.displayText
        return text.isEmpty ? "Add a food or a note." : "Shows as “\(text)”"
    }

    private func save() {
        onSave(edited)
        dismiss()
    }

    private static func format(_ quantity: Double?) -> String {
        guard let quantity, quantity > 0 else { return "" }
        return quantity.formatted(.number.precision(.fractionLength(0...3)))
    }
}

// MARK: - Catalog (units, labels)

@MainActor
@Observable
final class ShoppingCatalog {
    private(set) var units: [IngredientUnit] = []
    private(set) var labels: [MultiPurposeLabel] = []

    func load(using mealie: MealieService) async {
        if units.isEmpty, let cached = await mealie.cached([IngredientUnit].self, key: "shopping.units") { units = cached }
        if labels.isEmpty, let cached = await mealie.cached([MultiPurposeLabel].self, key: "shopping.labels") { labels = cached }
        async let freshUnits = try? mealie.units()
        async let freshLabels = try? mealie.labels()
        if let fresh = await freshUnits {
            units = fresh.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            await mealie.storeInCache(units, key: "shopping.units")
        }
        if let fresh = await freshLabels {
            labels = fresh.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            await mealie.storeInCache(labels, key: "shopping.labels")
        }
    }
}

// MARK: - Pickers

private struct UnitPicker: View {
    @Binding var selection: IngredientUnit?
    let units: [IngredientUnit]
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        List {
            Button { choose(nil) } label: { row("None", selected: selection == nil) }
            ForEach(filtered, id: \.id) { unit in
                Button { choose(unit) } label: {
                    row(unit.name, detail: unit.abbreviation, selected: selection?.id == unit.id)
                }
            }
        }
        .screenBackground()
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle("Unit")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filtered: [IngredientUnit] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return units }
        return units.filter {
            $0.name.localizedStandardContains(query) || ($0.abbreviation ?? "").localizedStandardContains(query)
                || ($0.pluralName ?? "").localizedStandardContains(query)
        }
    }

    private func choose(_ unit: IngredientUnit?) {
        selection = unit
        dismiss()
    }
}

private struct FoodPicker: View {
    @Binding var selection: IngredientFood?
    @Environment(\.mealie) private var mealie
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var foods: [IngredientFood] = []
    @State private var failed = false

    var body: some View {
        List {
            Button { choose(nil) } label: { row("None", selected: selection == nil) }
            ForEach(foods, id: \.id) { food in
                Button { choose(food) } label: {
                    row(food.name, detail: food.label?.name, selected: selection?.id == food.id)
                }
            }
        }
        .overlay {
            if failed && foods.isEmpty {
                ContentUnavailableView("Can’t Load Foods", systemImage: "wifi.exclamationmark",
                                       description: Text("Check your connection, then search again."))
            } else if !search.isEmpty && foods.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .screenBackground()
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search foods")
        .navigationTitle("Food")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: search) {
            if !search.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            do {
                foods = try await mealie.foods(search: search, perPage: 50).items
                failed = false
            } catch {
                if MealieError.wrap(error) != .cancelled { failed = true }
            }
        }
    }

    private func choose(_ food: IngredientFood?) {
        selection = food
        dismiss()
    }
}

private func row(_ title: String, detail: String? = nil, selected: Bool) -> some View {
    HStack {
        Text(title)
            .foregroundStyle(.primary)
        Spacer()
        if let detail, !detail.isEmpty {
            Text(detail)
                .foregroundStyle(.secondary)
        }
        if selected {
            Image(systemName: "checkmark")
                .foregroundStyle(.tint)
                .fontWeight(.semibold)
        }
    }
    .contentShape(.rect)
    .accessibilityAddTraits(selected ? .isSelected : [])
}
