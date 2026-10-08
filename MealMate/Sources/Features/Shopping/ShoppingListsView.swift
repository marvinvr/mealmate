import SwiftUI

/// Shopping tab root: all lists with what's left to buy; create, rename, delete.
struct ShoppingListsView: View {
    @Environment(\.mealie) private var mealie
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = ShoppingListsViewModel()

    @State private var creating = false
    @State private var renamingRow: ShoppingListsViewModel.Row?
    @State private var deletingRow: ShoppingListsViewModel.Row?
    @State private var nameText = ""
    /// Deep link / DEBUG route: "add this recipe to a list" sheet by slug.
    @State private var addRecipeSlug: String?

    var body: some View {
        content
            .screenBackground()
            .navigationTitle("Shopping")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New List", systemImage: "plus") {
                        nameText = ""
                        creating = true
                    }
                }
            }
            .task { await model.load(using: mealie) }
            .onAppear(perform: consumeIntent)
            .onChange(of: router.pendingIntent) { consumeIntent() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.refresh() } }
            }
            .sensoryFeedback(.error, trigger: model.errorFeedback)
            .alert("New List", isPresented: $creating) {
                TextField("Name", text: $nameText)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    Task {
                        if let list = await model.create(name: nameText) {
                            router.push(.shoppingList(id: list.id), in: .shopping)
                        }
                    }
                }
            }
            .alert("Rename List", isPresented: renamingBinding, presenting: renamingRow) { row in
                TextField("Name", text: $nameText)
                Button("Cancel", role: .cancel) {}
                Button("Rename") { Task { await model.rename(row, to: nameText) } }
            }
            .confirmationDialog("Delete “\(deletingRow?.list.displayName ?? "")”?",
                                isPresented: deletingBinding, titleVisibility: .visible,
                                presenting: deletingRow) { row in
                Button("Delete List", role: .destructive) { Task { await model.delete(row) } }
            } message: { _ in
                Text("The list and all its items are deleted for everyone in your household.")
            }
            .alert(isPresented: errorBinding, error: model.actionError) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.recoverySuggestion ?? "Nothing was changed. Try again.")
            }
            .sheet(item: addRecipeBinding) { item in
                AddToShoppingListSheet(slug: item.id)
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
                Label("Can’t Load Lists", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error.errorDescription ?? "Check your connection, then try again.")
            } actions: {
                Button("Try Again") { Task { await model.refresh() } }
                    .buttonStyle(.bordered)
            }
        case .loaded:
            if model.rows.isEmpty {
                ContentUnavailableView {
                    Label("No Shopping Lists", systemImage: "cart")
                } description: {
                    Text("Create a list, then add items or a recipe’s ingredients to it.")
                } actions: {
                    Button("New List") {
                        nameText = ""
                        creating = true
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                list
            }
        }
    }

    private var list: some View {
        List {
            if let refreshError = model.refreshError {
                Label(refreshError, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(model.rows) { row in
                    NavigationLink(value: AppDestination.shoppingList(id: row.id)) {
                        ShoppingListRow(row: row)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { deletingRow = row } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button { startRename(row) } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                    }
                    .contextMenu {
                        Button("Rename…", systemImage: "pencil") { startRename(row) }
                        Button("Delete…", systemImage: "trash", role: .destructive) { deletingRow = row }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await model.refresh() }
    }

    private func startRename(_ row: ShoppingListsViewModel.Row) {
        nameText = row.list.name ?? ""
        renamingRow = row
    }

    private func consumeIntent() {
        if router.consumeIntent("shopping-new") != nil {
            nameText = ""
            creating = true
        } else if let intent = router.consumeIntent("shopping-add-recipe/") {
            addRecipeSlug = String(intent.dropFirst("shopping-add-recipe/".count))
        }
    }

    private var renamingBinding: Binding<Bool> {
        Binding { renamingRow != nil } set: { if !$0 { renamingRow = nil } }
    }

    private var deletingBinding: Binding<Bool> {
        Binding { deletingRow != nil } set: { if !$0 { deletingRow = nil } }
    }

    private var errorBinding: Binding<Bool> {
        Binding { model.actionError != nil } set: { if !$0 { model.actionError = nil } }
    }

    private struct SlugItem: Identifiable { let id: String }

    private var addRecipeBinding: Binding<SlugItem?> {
        Binding { addRecipeSlug.map(SlugItem.init) } set: { addRecipeSlug = $0?.id }
    }
}

private struct ShoppingListRow: View {
    let row: ShoppingListsViewModel.Row

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: row.uncheckedCount == 0 ? "checkmark.circle" : "cart")
                .font(.title3)
                .foregroundStyle(row.uncheckedCount == 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.list.displayName)
                    .font(.body.weight(.medium))
                Text(summary)
                    .font(.metadata)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        switch row.uncheckedCount {
        case nil: " "
        case 0: "All done"
        case 1: "1 item to buy"
        case let count?: "\(count) items to buy"
        }
    }
}
