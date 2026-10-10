import SwiftUI

/// The signed-in shell: four tabs, each with its own NavigationStack.
///
/// Feature root views (RecipesView, MealPlanView, ...) must NOT create their
/// own NavigationStack; they get one here, plus the account button and the
/// `AppDestination` navigation destinations. On iPad (regular width) the tab bar sits at the
/// top and Shopping shows its lists beside the open list (`ShoppingSplitRoot`).
struct MainTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            Tab(AppTab.recipes.title, systemImage: AppTab.recipes.systemImage, value: AppTab.recipes) {
                TabRoot(path: $router.recipesPath) { RecipesView() }
            }
            Tab(AppTab.mealPlan.title, systemImage: AppTab.mealPlan.systemImage, value: AppTab.mealPlan) {
                TabRoot(path: $router.mealPlanPath) { MealPlanView() }
            }
            Tab(AppTab.shopping.title, systemImage: AppTab.shopping.systemImage, value: AppTab.shopping) {
                if horizontalSizeClass == .regular {
                    ShoppingSplitRoot()
                } else {
                    NavigationStack(path: $router.shoppingPath) {
                        ShoppingListsView()
                            .tabRootChrome()
                    }
                }
            }
            Tab(AppTab.library.title, systemImage: AppTab.library.systemImage, value: AppTab.library) {
                TabRoot(path: $router.libraryPath) { LibraryView() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $router.isSettingsPresented) {
            SettingsView()
        }
        .fullScreenCover(item: $router.presentedDestination) { destination in
            AppDestinationView(destination: destination)
        }
        .createFlowRouteSheets()
        .supporterPromptPresenter()
    }
}

/// Set by the Recipes tab while multi-select is active, so Cancel and Select All aren't crowded
/// by the account button. Preferences flow up to `TabRoot`; the button lives outside the screen.
struct AccountButtonHiddenKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// NavigationStack + shared toolbar/destinations for one tab.
private struct TabRoot<Content: View>: View {
    @Binding var path: NavigationPath
    @ViewBuilder var content: Content
    @State private var hidesAccountButton = false

    var body: some View {
        NavigationStack(path: $path) {
            content
                .onPreferenceChange(AccountButtonHiddenKey.self) { hidesAccountButton = $0 }
                .tabRootChrome(hidesAccountButton: hidesAccountButton)
        }
    }
}

private extension View {
    /// The account button and the `AppDestination` destinations every tab root gets.
    func tabRootChrome(hidesAccountButton: Bool = false) -> some View {
        toolbar {
            if !hidesAccountButton {
                ToolbarItem(placement: .topBarTrailing) {
                    AccountButton()
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .navigationDestination(for: AppDestination.self) { destination in
            AppDestinationView(destination: destination)
        }
    }
}

/// Shopping on iPad (regular width): the lists in a sidebar column, the open list beside them.
/// Driven by the same `router.shoppingPath` as the iPhone stack: its first element (a
/// `.shoppingList`) is the selection, the rest is the detail column's stack, so deep links and
/// rotating into a narrow window keep the open list.
private struct ShoppingSplitRoot: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationSplitView {
            ShoppingListsView(selection: selection)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        AccountButton()
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 420)
        } detail: {
            NavigationStack(path: detailPath) {
                Group {
                    if case .shoppingList(let id)? = router.shoppingPath.first {
                        ShoppingListView(listID: id)
                            .id(id)
                    } else {
                        ContentUnavailableView("No List Selected", systemImage: "cart",
                                               description: Text("Choose a list, or create one with +."))
                            .screenBackground()
                    }
                }
                .navigationDestination(for: AppDestination.self) { destination in
                    AppDestinationView(destination: destination)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var selection: Binding<AppDestination?> {
        Binding {
            router.shoppingPath.first
        } set: { destination in
            guard destination != router.shoppingPath.first || router.shoppingPath.count > 1 else { return }
            router.shoppingPath = destination.map { [$0] } ?? []
        }
    }

    private var detailPath: Binding<[AppDestination]> {
        Binding {
            Array(router.shoppingPath.dropFirst())
        } set: { path in
            router.shoppingPath = Array(router.shoppingPath.prefix(1)) + path
        }
    }
}
