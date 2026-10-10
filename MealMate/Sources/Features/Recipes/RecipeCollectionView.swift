import SwiftUI

/// Grid or list layout for recipe collections (persisted per device).
enum RecipeLayout: String, CaseIterable, Identifiable {
    case grid, list
    var id: String { rawValue }
    var title: String { self == .grid ? "Grid" : "List" }
    var systemImage: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
}

/// The scrolling content of a recipe list: grid or rows, paging, pull-to-refresh, context
/// menus, empty / error states. Used by the Recipes tab and every Library recipe list.
/// Navigation title, search and toolbar belong to the hosting screen.
struct RecipeCollectionContent: View {
    let model: RecipeListModel
    let layout: RecipeLayout
    /// Empty state when nothing matches and there's no search / filter.
    var emptyTitle = "No Recipes Yet"
    var emptyMessage = "Import one from a website or create your own."
    var emptySystemImage = "book.pages"
    var onClearFilters: (() -> Void)?
    var header: AnyView?
    @Binding var sheet: RecipeSheet?
    @Binding var toast: RecipeToast?
    /// Set on the Recipes tab. Long-press starts selection; taps toggle while it is active.
    /// Library lists leave this `nil` and keep the context menu.
    var selection: Binding<RecipeSelectionState>? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var userData = RecipeUserData.shared
    @State private var changes = RecipeChanges.shared
    @State private var gridWidth: CGFloat = 0
    @Environment(AppRouter.self) private var router

    var body: some View {
        // One scroll container per layout (states render inside it) so the large title
        // and pull-to-refresh keep working across loading → content.
        Group {
            if layout == .grid && !model.isSearching {
                grid
            } else {
                list
            }
        }
        .animation(.smooth, value: model.items.map(\.id))
        .onChange(of: changes.revision) {
            model.removeDeleted(changes.deletedIDs)
            Task { await model.reload() }
        }
    }

    // MARK: Layouts

    /// Cards per row: as many minimum-width columns as fit, at least two (also on 375 pt
    /// iPhones and narrow iPad windows); larger cards in regular width (4–5 on a 13" iPad). One
    /// at accessibility sizes.
    private var columnCount: Int {
        if dynamicTypeSize.isAccessibilitySize { return 1 }
        let available = gridWidth - 2 * Theme.Spacing.screen
        guard available > 0 else { return 2 }
        let minimum = horizontalSizeClass == .regular ? Theme.gridMinimumColumnWidthRegular : Theme.gridMinimumColumnWidth
        return max(2, Int((available + Theme.Spacing.grid) / (minimum + Theme.Spacing.grid)))
    }

    private var gridRows: [[RecipeSummary]] {
        let count = columnCount
        return stride(from: 0, to: model.items.count, by: count).map {
            Array(model.items[$0..<min($0 + count, model.items.count)])
        }
    }

    /// The grid is a `List` of card rows rather than a `ScrollView` + `LazyVGrid`: only a List
    /// keeps the large title together with an always-visible search field (iOS 26), and its
    /// rows stay lazy.
    private var grid: some View {
        List {
            if let header {
                header
                    .listRowInsets(EdgeInsets(top: Theme.Spacing.xs, leading: Theme.Spacing.screen, bottom: Theme.Spacing.xs, trailing: Theme.Spacing.screen))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            if model.refreshError != nil {
                refreshNote
                    .listRowInsets(EdgeInsets(top: 0, leading: Theme.Spacing.screen, bottom: Theme.Spacing.s, trailing: Theme.Spacing.screen))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            let columns = columnCount
            ForEach(gridRows, id: \.first?.id) { row in
                HStack(alignment: .top, spacing: Theme.Spacing.grid) {
                    ForEach(row) { recipe in
                        // A Button, not a NavigationLink: links inside List rows get a chevron.
                        recipeControl(recipe) {
                            gridCard(recipe)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .onAppear { model.itemAppeared(recipe) }
                    }
                    ForEach(row.count..<max(columns, row.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: Theme.Spacing.screen, bottom: Theme.Spacing.xl, trailing: Theme.Spacing.screen))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            pagingFooter
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .contentMargins(.top, Theme.Spacing.xs, for: .scrollContent)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
        .overlay {
            if model.items.isEmpty { stateView }
        }
        .refreshable { await model.refresh() }
        .screenBackground()
    }

    private var list: some View {
        List {
            if let header {
                header
                    .listRowInsets(EdgeInsets(top: Theme.Spacing.xs, leading: Theme.Spacing.screen, bottom: Theme.Spacing.xs, trailing: Theme.Spacing.screen))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            if model.refreshError != nil {
                refreshNote
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            ForEach(model.items) { recipe in
                listRow(recipe)
                    .listRowBackground(Color.clear)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    .onAppear { model.itemAppeared(recipe) }
            }
            pagingFooter
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .readableContentWidth()
        .overlay {
            if model.items.isEmpty { stateView }
        }
        .refreshable { await model.refresh() }
        .screenBackground()
    }

    // MARK: Selection

    private var isSelecting: Bool { selection?.wrappedValue.isActive == true }

    private func gridCard(_ recipe: RecipeSummary) -> some View {
        let selected = selection?.wrappedValue.contains(recipe.id) == true
        return RecipeCard(recipe: recipe, isFavorite: userData.isFavorite(recipe.id))
            .overlay(alignment: .topTrailing) {
                if isSelecting {
                    RecipeSelectionMark(isSelected: selected, onPhoto: true)
                        .padding(Theme.Spacing.xs)
                }
            }
    }

    private func listLabel(_ recipe: RecipeSummary) -> some View {
        let selected = selection?.wrappedValue.contains(recipe.id) == true
        return HStack(spacing: Theme.Spacing.s) {
            if isSelecting {
                RecipeSelectionMark(isSelected: selected, onPhoto: false)
            }
            RecipeRow(recipe: recipe, isFavorite: userData.isFavorite(recipe.id))
            if selection != nil, !isSelecting {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary.opacity(0.6))
                    .accessibilityHidden(true)
            }
        }
    }

    /// Library keeps a `NavigationLink` (chevron, context menu, swipes). The Recipes tab uses a
    /// button so a long-press enters selection; swipe actions stay until selection is active.
    @ViewBuilder
    private func listRow(_ recipe: RecipeSummary) -> some View {
        if selection == nil {
            NavigationLink(value: AppDestination.recipe(slug: recipe.slug)) {
                RecipeRow(recipe: recipe, isFavorite: userData.isFavorite(recipe.id))
            }
            .contextMenu { RecipeContextMenu(recipe: recipe, sheet: $sheet, toast: $toast) }
            .swipeActions(edge: .leading) {
                FavoriteSwipeButton(recipe: recipe, toast: $toast)
            }
            .swipeActions(edge: .trailing) {
                listPlanSwipe(recipe)
            }
        } else if isSelecting {
            recipeControl(recipe) { listLabel(recipe) }
        } else {
            recipeControl(recipe) { listLabel(recipe) }
                .swipeActions(edge: .leading) {
                    FavoriteSwipeButton(recipe: recipe, toast: $toast)
                }
                .swipeActions(edge: .trailing) {
                    listPlanSwipe(recipe)
                }
        }
    }

    @ViewBuilder
    private func listPlanSwipe(_ recipe: RecipeSummary) -> some View {
        Button {
            sheet = .addToShoppingList(slug: recipe.slug)
        } label: {
            Label("Add to List", systemImage: "cart.badge.plus")
        }
        .tint(Color(.systemGray))
        Button {
            sheet = .addToMealPlan(recipe)
        } label: {
            Label("Plan", systemImage: "calendar.badge.plus")
        }
        .tint(Color(.systemGray2))
    }

    /// Opens the recipe, or toggles selection. On the Recipes tab a long-press enters selection
    /// instead of the context menu (those actions move to the selection bar).
    private func recipeControl<Label: View>(_ recipe: RecipeSummary, @ViewBuilder label: () -> Label) -> some View {
        let selecting = isSelecting
        let selected = selection?.wrappedValue.contains(recipe.id) == true
        let favorite = userData.isFavorite(recipe.id)
        return RecipePressable(
            onTap: { handleTap(recipe) },
            onLongPress: selection == nil ? nil : { handleLongPress(recipe) },
            label: label()
        )
        .modifier(RecipeContextMenuAttachment(enabled: selection == nil, recipe: recipe, sheet: $sheet, toast: $toast))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: recipe, favorite: favorite, selecting: selecting, selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(selection == nil ? "" : (selecting ? "Toggles whether this recipe is selected." : "Long press to select recipes."))
        .modifier(RecipeSelectAction(enabled: selection != nil) { handleLongPress(recipe) })
    }

    private func accessibilityLabel(for recipe: RecipeSummary, favorite: Bool, selecting: Bool, selected: Bool) -> String {
        var label = recipe.accessibilitySummary
        if favorite { label += ", favorite" }
        if selecting { label += selected ? ", selected" : ", not selected" }
        return label
    }

    private func handleTap(_ recipe: RecipeSummary) {
        if let selection, selection.wrappedValue.isActive {
            withAnimation(.snappy) { selection.wrappedValue.toggle(recipe) }
        } else {
            router.push(.recipe(slug: recipe.slug))
        }
    }

    private func handleLongPress(_ recipe: RecipeSummary) {
        guard let selection else { return }
        withAnimation(.snappy) {
            if selection.wrappedValue.isActive {
                selection.wrappedValue.toggle(recipe)
            } else {
                selection.wrappedValue.begin(with: recipe)
            }
        }
    }

    @ViewBuilder
    private var pagingFooter: some View {
        if model.hasMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.m)
                .task { await model.loadMore() }
        } else if let total = model.total, total > 8 {
            Text(total == 1 ? "1 recipe" : "\(total) recipes")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.m)
        }
    }

    @ViewBuilder
    private var refreshNote: some View {
        if let error = model.refreshError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: States

    @ViewBuilder
    private var stateView: some View {
        if let error = model.loadError {
            ContentUnavailableView {
                Label("Can’t Load Recipes", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { Task { await model.reload() } }
                    .buttonStyle(.bordered)
            }
        } else if !model.hasLoaded || model.isLoading {
            ProgressView()
                .controlSize(.large)
        } else if model.isSearching {
            ContentUnavailableView.search(text: model.key.search)
        } else if model.isFiltered || model.preset == .favorites {
            filteredEmpty
        } else {
            ContentUnavailableView(emptyTitle, systemImage: emptySystemImage, description: Text(emptyMessage))
        }
    }

    @ViewBuilder
    private var filteredEmpty: some View {
        if model.preset == .favorites || (model.filters.favoritesOnly && model.filters.count == 1) {
            ContentUnavailableView {
                Label("No Favorites Yet", systemImage: "heart")
            } description: {
                Text("Tap the heart on a recipe to keep it here.")
            } actions: {
                if let onClearFilters, model.preset != .favorites {
                    Button("Show All Recipes", action: onClearFilters).buttonStyle(.bordered)
                }
            }
        } else {
            ContentUnavailableView {
                Label("No Matching Recipes", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Try removing a filter.")
            } actions: {
                if let onClearFilters {
                    Button("Clear Filters", action: onClearFilters).buttonStyle(.bordered)
                }
            }
        }
    }
}

// MARK: - Context menu

/// Long-press menu for a recipe card or row.
struct RecipeContextMenu: View {
    let recipe: RecipeSummary
    @Binding var sheet: RecipeSheet?
    @Binding var toast: RecipeToast?

    @Environment(\.mealie) private var mealie
    @Environment(AppSession.self) private var session
    @State private var userData = RecipeUserData.shared

    var body: some View {
        let isFavorite = userData.isFavorite(recipe.id)
        Button {
            toggleFavorite(!isFavorite)
        } label: {
            Label(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "heart.slash" : "heart")
        }
        Button {
            sheet = .addToShoppingList(slug: recipe.slug)
        } label: {
            Label("Add to Shopping List", systemImage: "cart.badge.plus")
        }
        Button {
            sheet = .addToMealPlan(recipe)
        } label: {
            Label("Add to Meal Plan", systemImage: "calendar.badge.plus")
        }
        if let url = RecipeLinks.webURL(server: mealie.baseURL, groupSlug: session.currentUser?.groupSlug, slug: recipe.slug) {
            ShareLink(item: url, subject: Text(recipe.displayName)) {
                Label("Share Link", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func toggleFavorite(_ value: Bool) {
        Task {
            do {
                try await userData.setFavorite(value, recipeID: recipe.id, slug: recipe.slug, mealie: mealie, userID: session.currentUser?.id)
            } catch {
                toast = RecipeToast(message: "Couldn’t update favorites", systemImage: "exclamationmark.triangle", isError: true)
            }
        }
    }
}

/// Leading swipe on a recipe row.
private struct FavoriteSwipeButton: View {
    let recipe: RecipeSummary
    @Binding var toast: RecipeToast?

    @Environment(\.mealie) private var mealie
    @Environment(AppSession.self) private var session
    @State private var userData = RecipeUserData.shared

    var body: some View {
        let isFavorite = userData.isFavorite(recipe.id)
        Button {
            Task {
                do {
                    try await userData.setFavorite(!isFavorite, recipeID: recipe.id, slug: recipe.slug, mealie: mealie, userID: session.currentUser?.id)
                } catch {
                    toast = RecipeToast(message: "Couldn’t update favorites", systemImage: "exclamationmark.triangle", isError: true)
                }
            }
        } label: {
            Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "heart.slash" : "heart")
        }
        .tint(.accentColor)
    }
}

// MARK: - Press handling

/// A tappable recipe whose long-press is optional. The tap that ends a long-press is swallowed
/// so entering selection doesn't also open the recipe.
private struct RecipePressable<Label: View>: View {
    var onTap: () -> Void
    var onLongPress: (() -> Void)?
    var label: Label
    @State private var ignoreTap = false

    var body: some View {
        Button(action: tap) { label }
            .buttonStyle(.plain)
            .modifier(LongPressAttachment(action: onLongPress) {
                ignoreTap = true
                onLongPress?()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    ignoreTap = false
                }
            })
    }

    private func tap() {
        if ignoreTap {
            ignoreTap = false
            return
        }
        onTap()
    }
}

private struct LongPressAttachment: ViewModifier {
    var action: (() -> Void)?
    var perform: () -> Void

    func body(content: Content) -> some View {
        if action != nil {
            content.onLongPressGesture(minimumDuration: 0.45, perform: perform)
        } else {
            content
        }
    }
}

/// Context menu only where selection isn't offered (library). On the Recipes tab the long-press
/// is selection, and the menu's actions live in the selection bar.
private struct RecipeContextMenuAttachment: ViewModifier {
    var enabled: Bool
    let recipe: RecipeSummary
    @Binding var sheet: RecipeSheet?
    @Binding var toast: RecipeToast?

    func body(content: Content) -> some View {
        if enabled {
            content.contextMenu { RecipeContextMenu(recipe: recipe, sheet: $sheet, toast: $toast) }
        } else {
            content
        }
    }
}

/// VoiceOver "Select" on the Recipes tab. Absent on library lists, which have no selection mode.
private struct RecipeSelectAction: ViewModifier {
    var enabled: Bool
    var action: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.accessibilityAction(named: Text("Select"), action)
        } else {
            content
        }
    }
}
