import SwiftUI
import UIKit

/// Cook mode (`AppDestination.cookMode`, full screen): one step per page in large type,
/// each with the ingredients it uses, an ingredients overview with check-off, and a done
/// page with "I made this". Keeps the screen awake while visible; works in landscape.
/// Shares servings and check marks with the recipe detail (`CookingSessionStore`).
struct CookModeView: View {
    let slug: String
    @Environment(\.mealie) private var mealie

    var body: some View {
        CookModeScreen(model: RecipeDetailModel(slug: slug, mealie: mealie))
    }
}

private struct CookModeScreen: View {
    @State var model: RecipeDetailModel

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var page = 0
    @State private var isIngredientsPresented = false
    @State private var isMadeItPresented = false
    @State private var madeIt = false

    var body: some View {
        NavigationStack {
            Group {
                if let recipe = model.recipe {
                    if recipe.instructions.isEmpty {
                        ContentUnavailableView("No Steps", systemImage: "list.number",
                                               description: Text("This recipe has no steps yet. Add them in Mealie to cook step by step."))
                    } else {
                        pager(recipe)
                    }
                } else if let error = model.loadError {
                    ContentUnavailableView {
                        Label("Can’t Load Recipe", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") { Task { await model.load() } }.buttonStyle(.bordered)
                    }
                } else {
                    ProgressView().controlSize(.large)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .screenBackground()
            .toolbar { toolbar }
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await model.load()
            if let recipe = model.recipe {
                page = min(model.session.currentStep, recipe.instructions.count)
                consumeIntent(recipe)
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: page) { _, page in
            guard let recipe = model.recipe else { return }
            model.cooking.update(recipe.id) { $0.currentStep = page }
        }
        .sheet(isPresented: $isIngredientsPresented) {
            CookIngredientsSheet(model: model)
        }
        .sheet(isPresented: $isMadeItPresented) {
            MadeItSheet(recipeName: model.recipe?.displayName ?? "") { date, note in
                try await model.markMade(at: date, note: note, userName: session.currentUser?.displayName, userID: session.currentUser?.id)
                madeIt = true
            }
        }
        .sensoryFeedback(.success, trigger: madeIt) { _, new in new }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Close", systemImage: "xmark") { dismiss() }
        }
        ToolbarItem(placement: .principal) {
            if let recipe = model.recipe, !recipe.instructions.isEmpty {
                let count = recipe.instructions.count
                VStack(spacing: Theme.Spacing.xxs) {
                    Text(page < count ? "Step \(page + 1) of \(count)" : "Done")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(page)))
                    ProgressView(value: Double(min(page + 1, count)), total: Double(count))
                        .frame(width: 120)
                        .tint(.accentColor)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(page < count ? "Step \(page + 1) of \(count)" : "All steps done")
            }
        }
        if model.recipe?.ingredients.isEmpty == false {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Ingredients", systemImage: "list.bullet") { isIngredientsPresented = true }
            }
        }
    }

    // MARK: Pager

    private func pager(_ recipe: Recipe) -> some View {
        let steps = recipe.instructions
        let sectionTitles = Self.sectionTitles(steps)
        return VStack(spacing: 0) {
            TabView(selection: $page.animation(.smooth)) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    CookStepPage(number: index + 1, sectionTitle: sectionTitles[index], step: step, model: model)
                        .tag(index)
                }
                CookDonePage(recipe: recipe, madeIt: madeIt, onMadeIt: { isMadeItPresented = true }, onClose: {
                    model.resetCooking()
                    dismiss()
                })
                .tag(steps.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            controls(stepCount: steps.count)
        }
    }

    private func controls(stepCount: Int) -> some View {
        GlassEffectContainer(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                Button {
                    withAnimation(.smooth) { page = max(page - 1, 0) }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title2.weight(.semibold))
                        .frame(width: 60, height: 60)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .disabled(page == 0)
                .accessibilityLabel("Previous Step")

                if page < stepCount {
                    Button {
                        withAnimation(.smooth) { page = min(page + 1, stepCount) }
                    } label: {
                        Text(page == stepCount - 1 ? "Finish" : "Next Step")
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .primaryActionStyle()
                    .buttonBorderShape(.capsule)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.bottom, Theme.Spacing.s)
        .padding(.top, Theme.Spacing.xs)
        .frame(maxWidth: 680)
    }

    /// Section title in effect for each step (Mealie marks the first step of a section).
    static func sectionTitles(_ steps: [RecipeStep]) -> [String?] {
        var current: String?
        return steps.map { step in
            if let title = step.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { current = title }
            return current
        }
    }

    private func consumeIntent(_ recipe: Recipe) {
        guard let intent = router.consumeIntent("cook-") else { return }
        if intent == "cook-ingredients" {
            isIngredientsPresented = true
        } else if intent == "cook-done" {
            page = recipe.instructions.count
        } else if intent.hasPrefix("cook-step/"), let number = Int(intent.dropFirst("cook-step/".count)) {
            page = min(max(number - 1, 0), recipe.instructions.count)
        }
    }
}

// MARK: - Pages

private struct CookStepPage: View {
    let number: Int
    let sectionTitle: String?
    let step: RecipeStep
    let model: RecipeDetailModel

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(AppSession.self) private var session

    var body: some View {
        let ingredients = model.referencedIngredients(for: step)
        ScrollView {
            Group {
                if verticalSizeClass == .compact && !ingredients.isEmpty {
                    HStack(alignment: .top, spacing: Theme.Spacing.xxl) {
                        stepText.frame(maxWidth: .infinity, alignment: .leading)
                        ingredientList(ingredients).frame(maxWidth: 320, alignment: .leading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                        stepText
                        if !ingredients.isEmpty { ingredientList(ingredients) }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.l)
            .frame(maxWidth: verticalSizeClass == .compact ? .infinity : 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var stepText: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let sectionTitle {
                Text(sectionTitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Text("Step \(number)")
                .font(.stepLabel)
                .foregroundStyle(.secondary)
                .textCase(nil)
            Text(LocalizedStringKey(step.text.trimmingCharacters(in: .whitespacesAndNewlines)))
                .font(.cookStep)
                .lineSpacing(Theme.LineSpacing.cook)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func ingredientList(_ ingredients: [(index: Int, ingredient: RecipeIngredient)]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(model.isScaled ? "You’ll need · \(RecipeFormatting.servings(model.servings) ?? "")" : "You’ll need")
                .font(.stepLabel)
                .foregroundStyle(.secondary)
            ForEach(ingredients, id: \.index) { entry in
                IngredientRow(ingredient: entry.ingredient, scale: model.scale, isChecked: model.isChecked(entry.index),
                              isOnHand: entry.ingredient.food?.isOnHand(householdSlug: session.currentUser?.householdSlug) ?? false,
                              font: .cookIngredient,
                              toggle: { withAnimation(.smooth) { model.toggleIngredient(entry.index) } })
            }
        }
        .sensoryFeedback(.selection, trigger: model.checkedCount)
    }
}

private struct CookDonePage: View {
    let recipe: Recipe
    let madeIt: Bool
    let onMadeIt: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            Image(systemName: madeIt ? "checkmark.seal.fill" : "fork.knife")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(.tint)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            VStack(spacing: Theme.Spacing.xs) {
                Text(madeIt ? "Added to Your History" : "Enjoy Your Meal")
                    .font(.title.weight(.semibold))
                Text(recipe.displayName)
                    .font(.recipeRowTitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: Theme.Spacing.s) {
                if !madeIt {
                    Button(action: onMadeIt) {
                        Label("I Made This", systemImage: "checkmark.seal")
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, Theme.Spacing.s)
                    }
                    .primaryActionStyle()
                    .controlSize(.large)
                }
                Button("Close Cook Mode", action: onClose)
                    .buttonStyle(.bordered)
                    .tint(.primary)
                    .controlSize(.large)
            }
            Spacer()
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Ingredients sheet

private struct CookIngredientsSheet: View {
    let model: RecipeDetailModel

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ServingsStepper(model: model)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                if let recipe = model.recipe {
                    ForEach(RecipeSections.ingredients(recipe.ingredients)) { section in
                        Section(section.title ?? "") {
                            ForEach(section.items) { entry in
                                IngredientRow(ingredient: entry.item, scale: model.scale, isChecked: model.isChecked(entry.index),
                                              isOnHand: entry.item.food?.isOnHand(householdSlug: session.currentUser?.householdSlug) ?? false,
                                              font: .cookIngredient,
                                              toggle: { withAnimation(.smooth) { model.toggleIngredient(entry.index) } })
                                // Partial-height sheets give grouped rows a grey fill; match the
                                // servings card above instead.
                                .listRowBackground(Color.mealMateSurface)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .screenBackground()
            .sensoryFeedback(.selection, trigger: model.checkedCount)
            .navigationTitle("Ingredients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if model.checkedCount > 0 {
                        Button("Uncheck All") { withAnimation(.smooth) { model.resetCooking() } }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
