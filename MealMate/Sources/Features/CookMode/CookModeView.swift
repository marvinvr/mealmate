import SwiftUI
import UIKit

/// Cook mode (`AppDestination.cookMode`, full screen): one step per page in large type,
/// each with the ingredients it uses, an ingredients overview with check-off, and a done
/// page with "I made this". Keeps the screen awake while visible; works in landscape.
/// On wide screens (iPad) the ingredients stay beside the steps (`CookIngredientsPanel`)
/// instead of a sheet. Keyboard: ← / → step, Esc closes.
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
    @State private var width: CGFloat = 0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// iPad (13" in both orientations, 11" in landscape): ingredients beside the steps.
    private var showsIngredientsPanel: Bool {
        horizontalSizeClass == .regular && width >= 1000 && model.recipe?.ingredients.isEmpty == false
    }

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
            .onGeometryChange(for: CGFloat.self) { $0.size.width.rounded(.down) } action: { width = $0 }
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
            MadeItSheet(recipeName: model.recipe?.displayName ?? "") { date, note, photo in
                // A failed photo upload still counts as made; the entry shows without a photo.
                try await model.markMade(at: date, note: note, photo: photo,
                                         userName: session.currentUser?.displayName, userID: session.currentUser?.id)
                madeIt = true
            }
        }
        .sensoryFeedback(.success, trigger: madeIt) { _, new in new }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Close", systemImage: "xmark") { dismiss() }
                .keyboardShortcut(.cancelAction)
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
        if model.recipe?.ingredients.isEmpty == false && !showsIngredientsPanel {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Ingredients", systemImage: "list.bullet") { isIngredientsPresented = true }
                    .keyboardShortcut("i", modifiers: .command)
            }
        }
    }

    // MARK: Pager

    private func pager(_ recipe: Recipe) -> some View {
        let steps = recipe.instructions
        let sectionTitles = Self.sectionTitles(steps)
        let showsPanel = showsIngredientsPanel
        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                stepPager(recipe, sectionTitles: sectionTitles, showsIngredients: !showsPanel)
                controls(stepCount: steps.count)
            }
            if showsPanel {
                Divider()
                    .ignoresSafeArea(edges: .bottom)
                CookIngredientsPanel(model: model, currentStep: page < steps.count ? steps[page] : nil)
                    .frame(width: min(400, max(340, width * 0.3)))
            }
        }
    }

    private func stepPager(_ recipe: Recipe, sectionTitles: [String?], showsIngredients: Bool) -> some View {
        let steps = recipe.instructions
        return TabView(selection: $page.animation(.smooth)) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                CookStepPage(number: index + 1, sectionTitle: sectionTitles[index], step: step, model: model,
                             showsIngredients: showsIngredients)
                    .tag(index)
            }
            CookDonePage(recipe: recipe, madeIt: madeIt, onMadeIt: { isMadeItPresented = true }, onClose: {
                model.resetCooking()
                dismiss()
            })
            .tag(steps.count)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
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
                .keyboardShortcut(.leftArrow, modifiers: [])

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
                    .keyboardShortcut(.rightArrow, modifiers: [])
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
    /// `false` when the ingredients panel beside the pager already shows them (iPad).
    var showsIngredients = true

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppSession.self) private var session

    var body: some View {
        let ingredients = showsIngredients ? model.referencedIngredients(for: step) : []
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
            .padding(.vertical, horizontalSizeClass == .regular ? Theme.Spacing.xxl : Theme.Spacing.l)
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
                .font(horizontalSizeClass == .regular ? .cookStepRegular : .cookStep)
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

// MARK: - Ingredients panel (iPad)

/// All ingredients beside the steps on wide screens, with servings and check-off; the ones the
/// current step uses are highlighted and scrolled into view.
private struct CookIngredientsPanel: View {
    let model: RecipeDetailModel
    let currentStep: RecipeStep?

    @Environment(AppSession.self) private var session

    var body: some View {
        let used = Set(currentStep.map { model.referencedIngredients(for: $0).map(\.index) } ?? [])
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Ingredients")
                            .font(.sectionTitle)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        if model.checkedCount > 0 {
                            Button("Uncheck All") { withAnimation(.smooth) { model.resetCooking() } }
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    ServingsStepper(model: model)
                    if let recipe = model.recipe {
                        ForEach(RecipeSections.ingredients(recipe.ingredients)) { section in
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                if let title = section.title {
                                    Text(title)
                                        .font(.headline)
                                        .padding(.top, Theme.Spacing.xs)
                                        .accessibilityAddTraits(.isHeader)
                                }
                                ForEach(section.items) { entry in
                                    IngredientRow(ingredient: entry.item, scale: model.scale, isChecked: model.isChecked(entry.index),
                                                  isOnHand: entry.item.food?.isOnHand(householdSlug: session.currentUser?.householdSlug) ?? false,
                                                  font: .cookIngredient,
                                                  toggle: { withAnimation(.smooth) { model.toggleIngredient(entry.index) } })
                                        .padding(.horizontal, Theme.Spacing.xs)
                                        .background {
                                            if used.contains(entry.index) {
                                                RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
                                                    .fill(Color.accentColor.opacity(0.12))
                                            }
                                        }
                                        .accessibilityHint(used.contains(entry.index) ? "Used in this step." : "")
                                        .id(entry.index)
                                }
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .sensoryFeedback(.selection, trigger: model.checkedCount)
            .onChange(of: used.min()) { _, first in
                guard let first else { return }
                withAnimation(.smooth) { proxy.scrollTo(first, anchor: .center) }
            }
        }
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
