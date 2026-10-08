import SwiftUI

/// Library tab root: Favorites, then cookbooks, categories, tags and tools; each opens a
/// recipe list. Searchable across all organizers.
/// Lives inside the tab's NavigationStack (see `MainTabView`): don't add another stack.
struct LibraryView: View {
    @Environment(\.mealie) private var mealie
    @Environment(AppRouter.self) private var router
    @State private var store = OrganizerStore.shared
    @State private var userData = RecipeUserData.shared
    @State private var search = ""

    /// Organizers shown per section before "Show All".
    private let previewCount = 5

    var body: some View {
        List {
            if trimmedSearch.isEmpty {
                Section {
                    NavigationLink(value: LibraryRoute.favorites) {
                        LibraryRow(title: "Favorites", systemImage: "heart", count: userData.hasLoaded ? userData.favoriteIDs.count : nil)
                    }
                } footer: {
                    if store.hasLoaded, store.isEmpty {
                        Text("Cookbooks, categories, tags and tools you create in Mealie show up here.")
                    }
                }
            }

            if let error = store.error, store.isEmpty {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            cookbooksSection
            ForEach(OrganizerKind.allCases, id: \.self) { kind in
                organizerSection(kind)
            }
        }
        .listStyle(.insetGrouped)
        .screenBackground()
        .overlay {
            if !trimmedSearch.isEmpty, searchResultsEmpty {
                ContentUnavailableView.search(text: trimmedSearch)
            } else if !store.hasLoaded {
                ProgressView().controlSize(.large)
            }
        }
        .navigationTitle("Library")
        .searchable(text: $search, prompt: "Search cookbooks, tags…")
        .refreshable {
            async let organizers: Void = store.load(mealie, force: true)
            async let favorites: Void = userData.load(mealie, force: true)
            _ = await (organizers, favorites)
        }
        .task {
            async let organizers: Void = store.load(mealie)
            async let favorites: Void = userData.load(mealie)
            _ = await (organizers, favorites)
        }
        .navigationDestination(for: LibraryRoute.self) { route in
            switch route {
            case .favorites:
                RecipeCollectionScreen(preset: .favorites)
            case .all(let kind):
                OrganizerListView(kind: kind)
            case .cookbooks:
                CookbookListView()
            }
        }
        .onAppear(perform: consumeIntent)
        .onChange(of: router.pendingIntent) { _, _ in consumeIntent() }
    }

    private var trimmedSearch: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func matches(_ name: String) -> Bool {
        trimmedSearch.isEmpty || name.localizedStandardContains(trimmedSearch)
    }

    private var searchResultsEmpty: Bool {
        store.cookbooks.allSatisfy { !matches($0.name) }
            && OrganizerKind.allCases.allSatisfy { kind in store.organizers(kind).allSatisfy { !matches($0.name) } }
    }

    @ViewBuilder
    private var cookbooksSection: some View {
        let cookbooks = store.cookbooks.filter { matches($0.name) }
        if !cookbooks.isEmpty {
            let shown = trimmedSearch.isEmpty ? Array(cookbooks.prefix(previewCount)) : cookbooks
            Section("Cookbooks") {
                ForEach(shown) { cookbook in
                    NavigationLink(value: AppDestination.cookbook(id: cookbook.id)) {
                        LibraryRow(title: cookbook.name, systemImage: "book.closed", subtitle: cookbook.description)
                    }
                }
                if shown.count < cookbooks.count {
                    NavigationLink(value: LibraryRoute.cookbooks) {
                        Text("Show All \(cookbooks.count)").foregroundStyle(.tint)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func organizerSection(_ kind: OrganizerKind) -> some View {
        let organizers = store.organizers(kind).filter { matches($0.name) }
        if !organizers.isEmpty {
            let shown = trimmedSearch.isEmpty ? Array(organizers.prefix(previewCount)) : organizers
            Section(kind.title) {
                ForEach(shown, id: \.slug) { organizer in
                    NavigationLink(value: AppDestination.organizer(kind: kind, slug: organizer.slug)) {
                        LibraryRow(title: organizer.name, systemImage: kind.systemImage, count: organizer.recipeCount)
                    }
                }
                if shown.count < organizers.count {
                    NavigationLink(value: LibraryRoute.all(kind)) {
                        Text("Show All \(organizers.count)").foregroundStyle(.tint)
                    }
                }
            }
        }
    }

    private func consumeIntent() {
        guard let intent = router.consumeIntent("library-") else { return }
        let parts = intent.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        switch parts[0] {
        case "library-search":
            search = parts[1]
        case "library-all":
            if parts[1] == "favorites" {
                router.libraryPath.append(LibraryRoute.favorites)
            } else if parts[1] == "cookbooks" {
                router.libraryPath.append(LibraryRoute.cookbooks)
            } else if let kind = OrganizerKind(rawValue: parts[1]) {
                router.libraryPath.append(LibraryRoute.all(kind))
            }
        default: break
        }
    }
}

/// Library-only navigation targets.
enum LibraryRoute: Hashable {
    case favorites
    case cookbooks
    case all(OrganizerKind)
}

struct LibraryRow: View {
    let title: String
    let systemImage: String
    var subtitle: String?
    var count: Int?

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let count {
                Text(count, format: .number)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// All categories, tags or tools (searchable).
struct OrganizerListView: View {
    let kind: OrganizerKind

    @Environment(\.mealie) private var mealie
    @State private var store = OrganizerStore.shared
    @State private var search = ""

    var body: some View {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let organizers = store.organizers(kind).filter { query.isEmpty || $0.name.localizedStandardContains(query) }
        List(organizers, id: \.slug) { organizer in
            NavigationLink(value: AppDestination.organizer(kind: kind, slug: organizer.slug)) {
                LibraryRow(title: organizer.name, systemImage: kind.systemImage, count: organizer.recipeCount)
            }
        }
        .listStyle(.insetGrouped)
        .screenBackground()
        .overlay {
            if organizers.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView("No \(kind.title)", systemImage: kind.systemImage,
                                           description: Text("Add \(kind.title.lowercased()) to recipes in Mealie to browse them here."))
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .navigationTitle(kind.title)
        .searchable(text: $search, prompt: "Search \(kind.title.lowercased())")
        .refreshable { await store.load(mealie, force: true) }
        .task { await store.load(mealie) }
    }
}

/// All cookbooks.
struct CookbookListView: View {
    @Environment(\.mealie) private var mealie
    @State private var store = OrganizerStore.shared

    var body: some View {
        List(store.cookbooks) { cookbook in
            NavigationLink(value: AppDestination.cookbook(id: cookbook.id)) {
                LibraryRow(title: cookbook.name, systemImage: "book.closed", subtitle: cookbook.description)
            }
        }
        .listStyle(.insetGrouped)
        .screenBackground()
        .overlay {
            if store.cookbooks.isEmpty {
                ContentUnavailableView("No Cookbooks", systemImage: "book.closed",
                                       description: Text("Create cookbooks in Mealie to group recipes by filters."))
            }
        }
        .navigationTitle("Cookbooks")
        .refreshable { await store.load(mealie, force: true) }
        .task { await store.load(mealie) }
    }
}
