import SwiftUI

/// A shopping list: items grouped by label, a collapsible "Checked" section, recipes the
/// items came from, and an add bar at the bottom for typing several items in a row.
struct ShoppingListView: View {
    @Environment(\.mealie) private var mealie
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppRouter.self) private var router
    @State private var model: ShoppingListViewModel
    @State private var draft = ""
    @FocusState private var addBarFocused: Bool
    @State private var editingItem: ShoppingListItem?
    @AppStorage("shopping.showsChecked") private var showsChecked = true
    @State private var confirmsClearChecked = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var scrollTarget: String?
    @State private var reorderingSections = false

    init(listID: String) {
        _model = State(initialValue: ShoppingListViewModel(listID: listID))
    }

    var body: some View {
        content
            .screenBackground()
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbar }
            .safeAreaBar(edge: .bottom) {
                if model.phase == .loaded {
                    ShoppingAddBar(text: $draft, isFocused: $addBarFocused, submit: submitDraft)
                }
            }
            // The add bar takes the bottom edge; two stacked floating bars felt busy.
            .toolbarVisibility(.hidden, for: .tabBar)
            .task {
                await model.load(using: mealie)
                consumeIntent()
            }
            .task { await model.poll() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.refresh() } }
            }
            .sensoryFeedback(.selection, trigger: model.checkFeedback)
            .sensoryFeedback(.error, trigger: model.errorFeedback)
            .sheet(item: $editingItem) { item in
                ShoppingItemEditor(item: item, recipeNames: model.recipeNames(for: item)) { edited in
                    Task { await model.save(edited) }
                }
            }
            .sheet(isPresented: $reorderingSections) {
                ShoppingSectionOrderSheet(settings: model.orderedLabelSettings, counts: sectionCounts) { ordered in
                    Task { await model.reorderSections(ordered) }
                }
            }
            .confirmationDialog("Remove all checked items?", isPresented: $confirmsClearChecked, titleVisibility: .visible) {
                Button("Remove ^[\(model.clearableCount) Item](inflect: true)", role: .destructive) {
                    Task { await model.clearChecked() }
                }
            } message: {
                Text("They’re deleted from the list on all devices.")
            }
            .alert("Rename List", isPresented: $renaming) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Rename") { Task { await rename() } }
            }
            .alert(isPresented: errorBinding, error: model.actionError) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.recoverySuggestion ?? "Your change was undone. Try again.")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            ContentUnavailableView {
                Label("Can’t Load List", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error.errorDescription ?? "Check your connection, then try again.")
            } actions: {
                Button("Try Again") { Task { await model.refresh() } }
                    .buttonStyle(.bordered)
            }
        case .loaded:
            list
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            itemsList
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.smooth) { proxy.scrollTo(target, anchor: .bottom) }
                    scrollTarget = nil
                }
        }
    }

    private var itemsList: some View {
        List {
            if let refreshError = model.refreshError {
                Label(refreshError, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            ForEach(model.sections) { section in
                Section {
                    ForEach(section.items) { item in
                        itemRow(item)
                    }
                } header: {
                    ShoppingSectionHeader(section: section)
                }
            }

            if !model.recipeReferences.isEmpty {
                recipesSection
            }

            if !model.checkedItems.isEmpty {
                checkedSection
            }
            Color.clear
                .frame(height: 1)
                .listRowBackground(Color.clear)
                .id(Self.bottomID)
        }
        .listStyle(.insetGrouped)
        .overlay {
            if model.items.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to Buy", systemImage: "cart")
                } description: {
                    Text("Type an item below, like “2 lemons” or “olive oil”, or add a recipe’s ingredients from the recipe.")
                }
                .allowsHitTesting(false)
            }
        }
        .refreshable { await model.refresh() }
        .scrollDismissesKeyboard(.interactively)
        .animation(.snappy, value: model.items)
    }

    private func itemRow(_ item: ShoppingListItem) -> some View {
        ShoppingItemRow(item: item, recipeNames: model.recipeNames(for: item)) {
            Task { await model.toggle(item) }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task { await model.toggle(item) }
            } label: {
                if item.checked {
                    Label("Uncheck", systemImage: "arrow.uturn.backward")
                } else {
                    Label("Check", systemImage: "checkmark")
                }
            }
            .tint(.accentColor)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await model.delete(item) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                editingItem = item
            } label: {
                Label("Edit", systemImage: "pencil")
            }
        }
        .contextMenu {
            Button(item.checked ? "Uncheck" : "Check Off", systemImage: item.checked ? "circle" : "checkmark.circle") {
                Task { await model.toggle(item) }
            }
            Button("Edit…", systemImage: "pencil") { editingItem = item }
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { await model.delete(item) }
            }
        }
        .disabled(item.isPending)
    }

    private var recipesSection: some View {
        Section {
            ForEach(model.recipeReferences) { reference in
                ShoppingRecipeReferenceRow(reference: reference)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await model.remove(reference) }
                        } label: {
                            Label("Remove Items", systemImage: "minus.circle")
                        }
                    }
                    .contextMenu {
                        if let slug = reference.recipe?.slug {
                            NavigationLink(value: AppDestination.recipe(slug: slug)) {
                                Label("Open Recipe", systemImage: "book.pages")
                            }
                        }
                        Button("Remove Its Items", systemImage: "minus.circle", role: .destructive) {
                            Task { await model.remove(reference) }
                        }
                    }
            }
        } header: {
            Text("Recipes")
        } footer: {
            Text("Swipe a recipe to remove the items it added.")
        }
    }

    private var checkedSection: some View {
        Section {
            if showsChecked {
                ForEach(model.checkedItems) { item in
                    itemRow(item)
                }
            }
        } header: {
            HStack {
                Button {
                    withAnimation(.snappy) { showsChecked.toggle() }
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("Checked")
                        Text(model.checkedItems.count, format: .number)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(showsChecked ? 90 : 0))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Checked, \(model.checkedItems.count) items")
                .accessibilityValue(showsChecked ? "Expanded" : "Collapsed")
                .accessibilityHint(showsChecked ? "Hides checked items." : "Shows checked items.")
                Spacer()
                Button("Clear") { confirmsClearChecked = true }
                    .font(.subheadline.weight(.medium))
                    .textCase(nil)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Clear Checked…", systemImage: "trash", role: .destructive) {
                    confirmsClearChecked = true
                }
                .disabled(model.checkedItems.isEmpty)
                Button("Uncheck All", systemImage: "arrow.uturn.backward") {
                    Task { await model.uncheckAll() }
                }
                .disabled(model.checkedItems.isEmpty)
                Divider()
                Button("Reorder Sections…", systemImage: "arrow.up.arrow.down") {
                    reorderingSections = true
                }
                Button("Rename…", systemImage: "pencil") {
                    newName = model.list?.name ?? ""
                    renaming = true
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .disabled(model.phase != .loaded)
        }
    }

    /// Unchecked items per label id (for the reorder sheet).
    private var sectionCounts: [String: Int] {
        Dictionary(model.sections.map { ($0.id, $0.items.count) }, uniquingKeysWith: +)
    }

    private var errorBinding: Binding<Bool> {
        Binding { model.actionError != nil } set: { if !$0 { model.actionError = nil } }
    }

    private static let bottomID = "list-bottom"

    /// Deep link / DEBUG route states (see `AppRoute.registry`).
    private func consumeIntent() {
        guard model.phase == .loaded else { return }
        if router.consumeIntent("shopping-adding") != nil {
            addBarFocused = true
        } else if router.consumeIntent("shopping-bottom") != nil {
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                scrollTarget = Self.bottomID
            }
        } else if router.consumeIntent("shopping-clear") != nil {
            confirmsClearChecked = true
        } else if router.consumeIntent("shopping-sections") != nil {
            reorderingSections = true
        } else if let intent = router.consumeIntent("shopping-item/") {
            let id = String(intent.dropFirst("shopping-item/".count))
            editingItem = model.items.first { $0.id == id } ?? model.items.first
        }
    }

    private func submitDraft() {
        let text = draft
        draft = ""
        addBarFocused = true
        Task { await model.add(text: text) }
    }

    private func rename() async {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != model.list?.name else { return }
        do {
            _ = try await mealie.renameShoppingList(id: model.listID, to: name)
            await model.refresh()
        } catch {
            model.actionError = MealieError.wrap(error)
        }
    }
}

/// Floating add bar over the bottom of the list. Return adds the item and keeps the
/// keyboard up for the next one.
struct ShoppingAddBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var submit: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "plus")
                .foregroundStyle(.tint)
                .fontWeight(.semibold)
                .accessibilityHidden(true)
            TextField("Add an item", text: $text)
                .focused(isFocused)
                .submitLabel(.next)
                .autocorrectionDisabled(false)
                .onSubmit {
                    if text.trimmingCharacters(in: .whitespaces).isEmpty {
                        isFocused.wrappedValue = false
                    } else {
                        submit()
                    }
                }
            if !text.isEmpty {
                Button("Add", systemImage: "arrow.up.circle.fill", action: submit)
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(minHeight: 48)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.xs)
    }
}

/// "Added from recipe" row: thumbnail, name, scale.
struct ShoppingRecipeReferenceRow: View {
    let reference: ShoppingListRecipeReference

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            PlanningRecipeThumbnail(recipe: reference.recipe, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(reference.recipe?.displayName ?? "Recipe")
                    .font(.recipeRowTitle)
                    .lineLimit(2)
                if let quantity = reference.recipeQuantity, quantity != 1 {
                    Text("×\(quantity.formatted(.number.precision(.fractionLength(0...2))))")
                        .font(.metadata)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
