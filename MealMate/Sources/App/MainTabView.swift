import SwiftUI

/// The signed-in shell: four tabs, each with its own NavigationStack.
///
/// Feature root views (RecipesView, MealPlanView, ...) must NOT create their
/// own NavigationStack; they get one here, plus the account button and the
/// `AppDestination` navigation destinations.
struct MainTabView: View {
    @Environment(AppRouter.self) private var router

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
                TabRoot(path: $router.shoppingPath) { ShoppingListsView() }
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
    }
}

/// NavigationStack + shared toolbar/destinations for one tab.
private struct TabRoot<Content: View>: View {
    @Binding var path: NavigationPath
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack(path: $path) {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        AccountButton()
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                .navigationDestination(for: AppDestination.self) { destination in
                    AppDestinationView(destination: destination)
                }
        }
    }
}
