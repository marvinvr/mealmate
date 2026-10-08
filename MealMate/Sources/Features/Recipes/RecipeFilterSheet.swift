import SwiftUI

/// Filter sheet: favorites, categories, tags, tools and foods as multi-select chips.
/// Edits apply live (the list behind reloads); "Reset" clears everything.
struct RecipeFilterSheet: View {
    @Binding var filters: RecipeFilters

    @Environment(\.mealie) private var mealie
    @Environment(\.dismiss) private var dismiss
    @State private var store = OrganizerStore.shared
    @State private var foodSearch = ""
    @State private var foods: [FoodFilter] = []
    @State private var isLoadingFoods = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $filters.favoritesOnly.animation(.smooth)) {
                        Label("Favorites Only", systemImage: "heart")
                    }
                }

                ForEach(OrganizerKind.allCases, id: \.self) { kind in
                    let organizers = store.organizers(kind)
                    if !organizers.isEmpty {
                        Section {
                            ChipFlowLayout(spacing: Theme.Spacing.xs) {
                                ForEach(organizers, id: \.slug) { organizer in
                                    let isSelected = filters.contains(organizer, kind: kind)
                                    Button {
                                        withAnimation(.smooth) { filters.toggle(organizer, kind: kind) }
                                    } label: {
                                        TagChip(title: organizer.name, isSelected: isSelected)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, Theme.Spacing.xxs)
                        } header: {
                            sectionHeader(kind.title, count: filters.organizers(kind).count)
                        }
                    }
                }

                Section {
                    TextField("Search foods", text: $foodSearch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                    let shown = mergedFoods
                    if shown.isEmpty {
                        if !trimmedFoodSearch.isEmpty {
                            Text(isLoadingFoods ? "Searching…" : "No foods match “\(trimmedFoodSearch)”.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ChipFlowLayout(spacing: Theme.Spacing.xs) {
                            ForEach(shown) { food in
                                Button {
                                    withAnimation(.smooth) { filters.toggle(food) }
                                } label: {
                                    TagChip(title: food.name, isSelected: filters.foods.contains(food))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, Theme.Spacing.xxs)
                    }
                } header: {
                    sectionHeader("Foods", count: filters.foods.count)
                } footer: {
                    Text(filters.foods.isEmpty && trimmedFoodSearch.isEmpty
                         ? "Search for an ingredient, like “chicken”, to show recipes that use it."
                         : "Recipes that use any of the selected foods.")
                }

                if store.isEmpty && store.hasLoaded {
                    Section {
                        Text("Add categories, tags and tools to recipes in Mealie to filter by them here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .screenBackground()
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { withAnimation(.smooth) { filters = RecipeFilters() } }
                        .disabled(filters.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .task { await store.load(mealie) }
            .task(id: foodSearch) { await loadFoods() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var trimmedFoodSearch: String { foodSearch.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Selected foods first (so they stay visible while searching), then results. Search-first:
    /// a server has hundreds of foods, so nothing beyond the selection shows until you type.
    private var mergedFoods: [FoodFilter] {
        let selected = filters.foods
        let ids = Set(selected.map(\.id))
        return selected + foods.filter { !ids.contains($0.id) }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
            if count > 0 {
                Text("\(count) selected")
                    .foregroundStyle(.tint)
            }
        }
    }

    private func loadFoods() async {
        let query = trimmedFoodSearch
        guard !query.isEmpty else {
            foods = []
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        if Task.isCancelled { return }
        isLoadingFoods = true
        defer { isLoadingFoods = false }
        guard let page = try? await mealie.foods(search: query, perPage: 24) else { return }
        foods = page.items.compactMap { food in food.id.map { FoodFilter(id: $0, name: food.name) } }
    }
}

/// Left-aligned wrapping layout for chips.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, width: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = measure(subviews[index], width: bounds.width)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: .init(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// Ideal size, constrained to the row width only when it doesn't fit.
    private func measure(_ subview: LayoutSubview, width: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard ideal.width > width else { return ideal }
        return subview.sizeThatFits(.init(width: width, height: nil))
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = measure(subviews[index], width: width)
            let itemWidth = min(size.width, width)
            let needed = current.indices.isEmpty ? itemWidth : current.width + spacing + itemWidth
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? itemWidth : current.width + spacing + itemWidth
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
