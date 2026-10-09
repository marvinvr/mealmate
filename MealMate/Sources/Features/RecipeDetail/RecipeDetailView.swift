import SwiftUI

/// Recipe detail (`AppDestination.recipe`): hero photo, title, rating, times, servings
/// scaler, ingredients with check-off, steps, notes, nutrition, organizers, comments and
/// history; actions to cook, shop, plan, share and run household recipe actions.
struct RecipeDetailView: View {
    let slug: String
    @Environment(\.mealie) private var mealie

    var body: some View {
        RecipeDetailScreen(model: RecipeDetailModel(slug: slug, mealie: mealie))
            .id("\(mealie.cacheScope)|\(slug)")
    }
}

private struct RecipeDetailScreen: View {
    @State var model: RecipeDetailModel

    @Environment(\.mealie) private var mealie
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var userData = RecipeUserData.shared
    @State private var cooking = CookingSessionStore.shared
    @State private var sheet: RecipeSheet?
    @State private var toast: RecipeToast?
    @State private var isCommentsPresented = false
    @State private var isTimelinePresented = false
    @State private var isMadeItPresented = false
    @State private var showsNavigationTitle = false
    @State private var topInset: CGFloat = 0
    @State private var scrollTarget: String?
    @State private var shareText: ShareTextItem?
    @State private var isPublicLinkPresented = false
    @State private var confirmsDelete = false
    @State private var isWorking = false

    var body: some View {
        Group {
            if let recipe = model.recipe {
                content(recipe)
            } else if let error = model.loadError {
                ContentUnavailableView {
                    Label("Can’t Load Recipe", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await model.load() } }
                        .buttonStyle(.bordered)
                }
                .screenBackground()
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .screenBackground()
            }
        }
        .navigationTitle(model.recipe?.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(model.recipe?.displayName ?? "")
                    .font(.headline)
                    .lineLimit(1)
                    .opacity(showsNavigationTitle ? 1 : 0)
                    .animation(.smooth(duration: 0.2), value: showsNavigationTitle)
                    .accessibilityHidden(!showsNavigationTitle)
            }
            if let recipe = model.recipe {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    favoriteButton(recipe)
                    shareMenu(recipe)
                    moreMenu(recipe)
                }
            }
        }
        .task { await model.load() }
        .task { await userData.load(mealie) }
        .onAppear(perform: consumeIntent)
        .onChange(of: model.recipe != nil) { _, _ in consumeIntent() }
        .sheet(item: $sheet) { sheet in
            RecipeSheetView(sheet: sheet, onRecipeSaved: { updated in model.apply(updated) })
        }
        .sheet(isPresented: $isCommentsPresented) {
            RecipeCommentsSheet(model: model)
        }
        .sheet(isPresented: $isTimelinePresented) {
            RecipeTimelineSheet(model: model)
        }
        .sheet(isPresented: $isMadeItPresented) {
            MadeItSheet(recipeName: model.recipe?.displayName ?? "") { date, note, photo in
                let photoSaved = try await model.markMade(at: date, note: note, photo: photo,
                                                          userName: session.currentUser?.displayName, userID: session.currentUser?.id)
                toast = photoSaved
                    ? RecipeToast(message: "Nice! Added to the recipe’s history.", systemImage: "checkmark.circle.fill")
                    : RecipeToast(message: "Saved, but the photo couldn’t be uploaded", systemImage: "exclamationmark.triangle", isError: true)
            }
        }
        .sheet(isPresented: $isPublicLinkPresented) {
            if let recipe = model.recipe {
                RecipePublicLinkSheet(recipe: recipe)
            }
        }
        .confirmationDialog("Delete “\(model.recipe?.displayName ?? "")”?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Recipe", role: .destructive) { deleteRecipe() }
        } message: {
            Text("This removes the recipe from your Mealie server for everyone, including its history and comments.")
        }
        .sheet(item: $shareText) { item in
            ActivityView(items: [item.text])
                .presentationDetents([.medium, .large])
        }
        .recipeToast($toast)
    }

    // MARK: Content

    private func content(_ recipe: Recipe) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if recipe.hasImage {
                        StretchyHero(recipe: recipe)
                            .padding(.top, -topInset)
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                        RecipeHeader(model: model, recipe: recipe, onRate: { rate(recipe, $0) })
                        actionRow(recipe)
                        if let error = model.refreshError {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if !recipe.ingredients.isEmpty {
                            IngredientsSection(model: model, recipe: recipe, onAddToList: {
                                sheet = .addRecipeToShoppingList(recipe, scale: model.scale)
                            })
                            .id("ingredients")
                        }
                        if !recipe.instructions.isEmpty {
                            StepsSection(model: model, recipe: recipe)
                                .id("steps")
                        }
                        if !recipe.noteList.isEmpty {
                            NotesSection(notes: recipe.noteList)
                                .id("notes")
                        }
                        if let nutrition = recipe.nutrition, !nutrition.isEmpty {
                            NutritionSection(nutrition: nutrition)
                        }
                        OrganizersSection(recipe: recipe)
                        if let link = sourceURL(recipe) {
                            SourceLink(url: link)
                        }
                        if recipe.settings?.disableComments != true {
                            CommentsSection(model: model, onShowAll: { isCommentsPresented = true })
                                .id("comments")
                        }
                        HistorySection(model: model, onMadeIt: { isMadeItPresented = true }, onShowAll: { isTimelinePresented = true })
                            .id("history")
                    }
                    .padding(.horizontal, Theme.Spacing.screen)
                    .padding(.top, recipe.hasImage ? Theme.Spacing.l : Theme.Spacing.s)
                    .padding(.bottom, Theme.Spacing.xxxl)
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentInsets.top
            } action: { _, inset in
                topInset = recipe.hasImage ? inset : 0
            }
            .scrollEdgeEffectHidden(recipe.hasImage && !showsNavigationTitle, for: .top)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let threshold = recipe.hasImage ? min(geometry.containerSize.width / Theme.Aspect.hero, 520) - geometry.contentInsets.top : 40
                return geometry.contentOffset.y + geometry.contentInsets.top > threshold
            } action: { _, past in
                showsNavigationTitle = past
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.smooth) { proxy.scrollTo(target, anchor: .top) }
                scrollTarget = nil
            }
            .screenBackground()
        }
    }

    // MARK: Actions

    @ViewBuilder
    private func actionRow(_ recipe: Recipe) -> some View {
        let hasSteps = !recipe.instructions.isEmpty
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.s) {
                if hasSteps { startCookingButton(recipe) }
                recipeActionsControl(recipe)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                if hasSteps { startCookingButton(recipe) }
                recipeActionsControl(recipe)
            }
        }
    }

    private func startCookingButton(_ recipe: Recipe) -> some View {
        Button {
            router.present(.cookMode(slug: recipe.slug))
        } label: {
            Label("Start Cooking", systemImage: "flame")
                .font(.body.weight(.semibold))
                .padding(.horizontal, Theme.Spacing.xxs)
        }
        .primaryActionStyle()
        .controlSize(.large)
    }

    /// One action → direct button (one tap from the recipe); several → a menu.
    @ViewBuilder
    private func recipeActionsControl(_ recipe: Recipe) -> some View {
        let actions = model.actions
        if actions.count == 1, let action = actions.first {
            Button {
                run(action, recipe: recipe)
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    if model.runningActionID == action.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: action.isLink ? "arrow.up.forward.app" : "paperplane")
                    }
                    Text(action.title).lineLimit(1)
                }
                .font(.body.weight(.medium))
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(model.runningActionID != nil)
            .accessibilityHint(action.isLink ? "Opens a link for this recipe." : "Runs this household recipe action.")
        } else if actions.count > 1 {
            Menu {
                actionsMenuContent(recipe)
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    if model.runningActionID != nil {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "paperplane")
                    }
                    Text("Actions")
                }
                .font(.body.weight(.medium))
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private func actionsMenuContent(_ recipe: Recipe) -> some View {
        ForEach(model.actions) { action in
            Button {
                run(action, recipe: recipe)
            } label: {
                Label(action.title, systemImage: action.isLink ? "arrow.up.forward.app" : "paperplane")
            }
        }
    }

    private func run(_ action: RecipeAction, recipe: Recipe) {
        if action.isLink {
            if let url = model.linkURL(for: action, recipeURL: webURL(recipe)) {
                openURL(url)
            } else {
                toast = RecipeToast(message: "“\(action.title)” has an invalid link", systemImage: "exclamationmark.triangle", isError: true)
            }
            return
        }
        Task {
            do {
                try await model.trigger(action)
                toast = RecipeToast(message: "Sent to “\(action.title)”", systemImage: "checkmark.circle.fill")
            } catch {
                let message = (error as? MealieError)?.errorDescription ?? "Please try again."
                toast = RecipeToast(message: "“\(action.title)” failed. \(message)", systemImage: "exclamationmark.triangle", isError: true)
            }
        }
    }

    private func rate(_ recipe: Recipe, _ rating: Double?) {
        Task {
            do {
                try await userData.setRating(rating, recipeID: recipe.id, slug: recipe.slug, mealie: mealie, userID: session.currentUser?.id)
            } catch {
                toast = RecipeToast(message: "Couldn’t save your rating", systemImage: "exclamationmark.triangle", isError: true)
            }
        }
    }

    // MARK: Toolbar

    private func favoriteButton(_ recipe: Recipe) -> some View {
        let isFavorite = userData.isFavorite(recipe.id)
        return Button {
            Task {
                do {
                    try await userData.setFavorite(!isFavorite, recipeID: recipe.id, slug: recipe.slug, mealie: mealie, userID: session.currentUser?.id)
                } catch {
                    toast = RecipeToast(message: "Couldn’t update favorites", systemImage: "exclamationmark.triangle", isError: true)
                }
            }
        } label: {
            Label(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "heart.fill" : "heart")
                .contentTransition(.symbolEffect(.replace))
        }
        .tint(isFavorite ? .accentColor : nil)
    }

    private func shareMenu(_ recipe: Recipe) -> some View {
        Menu {
            if let url = webURL(recipe) {
                ShareLink(item: url, subject: Text(recipe.displayName)) {
                    Label("Share Link", systemImage: "link")
                }
            }
            ShareLink(item: RecipeLinks.plainText(recipe, scale: model.scale, servings: model.baseServings == nil ? nil : model.servings),
                      subject: Text(recipe.displayName)) {
                Label("Share as Text", systemImage: "doc.plaintext")
            }
            if session.currentUser?.groupSlug != nil {
                Button {
                    isPublicLinkPresented = true
                } label: {
                    Label("Public Link…", systemImage: "link.badge.plus")
                }
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }

    private func moreMenu(_ recipe: Recipe) -> some View {
        Menu {
            Section {
                if !recipe.instructions.isEmpty {
                    Button {
                        router.present(.cookMode(slug: recipe.slug))
                    } label: {
                        Label("Start Cooking", systemImage: "flame")
                    }
                }
                Button {
                    sheet = .addRecipeToShoppingList(recipe, scale: model.scale)
                } label: {
                    Label("Add to Shopping List", systemImage: "cart.badge.plus")
                }
                Button {
                    sheet = .addToMealPlan(recipe.summary)
                } label: {
                    Label("Add to Meal Plan", systemImage: "calendar.badge.plus")
                }
                Button {
                    isMadeItPresented = true
                } label: {
                    Label("I Made This", systemImage: "checkmark.seal")
                }
            }
            if model.actions.count > 1 {
                Section("Recipe Actions") { actionsMenuContent(recipe) }
            }
            Section {
                Button {
                    sheet = .edit(recipe)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                if let source = sourceURL(recipe) {
                    Link(destination: source) {
                        Label("Open Original", systemImage: "safari")
                    }
                }
                if let url = webURL(recipe) {
                    Link(destination: url) {
                        Label("Open in Mealie", systemImage: "globe")
                    }
                }
            }
            Section {
                Button {
                    duplicateRecipe()
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                Button(role: .destructive) {
                    confirmsDelete = true
                } label: {
                    Label("Delete Recipe…", systemImage: "trash")
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .disabled(isWorking)
    }

    private func duplicateRecipe() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let copy = try await model.duplicate()
                router.push(.recipe(slug: copy.slug))
            } catch {
                let message = (error as? MealieError)?.errorDescription ?? "Please try again."
                toast = RecipeToast(message: "Couldn’t duplicate. \(message)", systemImage: "exclamationmark.triangle", isError: true)
            }
        }
    }

    private func deleteRecipe() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await model.delete()
                dismiss()
            } catch {
                let message = (error as? MealieError)?.errorDescription ?? "Please try again."
                toast = RecipeToast(message: "Couldn’t delete. \(message)", systemImage: "exclamationmark.triangle", isError: true)
            }
        }
    }

    private func webURL(_ recipe: Recipe) -> URL? {
        RecipeLinks.webURL(server: mealie.baseURL, groupSlug: session.currentUser?.groupSlug, slug: recipe.slug)
    }

    private func sourceURL(_ recipe: Recipe) -> URL? {
        guard let raw = recipe.orgURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let url = URL(string: raw), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    // MARK: Debug routes

    private func consumeIntent() {
        guard let recipe = model.recipe, let intent = router.consumeIntent("recipe-") else { return }
        switch intent {
        case "recipe-scaled":
            model.setServings((model.baseServings ?? 1) * 2)
            scrollTarget = "ingredients"
        case "recipe-cooking":
            for index in recipe.ingredients.indices.prefix(3) where !model.isChecked(index) {
                model.toggleIngredient(index)
            }
            scrollTarget = "ingredients"
        case "recipe-steps": scrollTarget = "steps"
        case "recipe-notes": scrollTarget = recipe.noteList.isEmpty ? "comments" : "notes"
        case "recipe-history": scrollTarget = "history"
        case "recipe-add-to-list": sheet = .addRecipeToShoppingList(recipe, scale: model.scale)
        case "recipe-edit": sheet = .edit(recipe)
        case "recipe-comments": isCommentsPresented = true
        case "recipe-timeline": isTimelinePresented = true
        case "recipe-madeit": isMadeItPresented = true
        case "recipe-actions": scrollTarget = nil
        case "recipe-public-link": isPublicLinkPresented = true
        case "recipe-delete": confirmsDelete = true
        case "recipe-share":
            shareText = ShareTextItem(text: RecipeLinks.plainText(recipe, scale: model.scale))
        default: break
        }
    }
}

private struct ShareTextItem: Identifiable {
    let id = UUID()
    let text: String
}

// MARK: - Hero

/// Full-bleed 4:3 photo that stretches when pulled down.
private struct StretchyHero: View {
    let recipe: Recipe

    var body: some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .scrollView).minY
            let stretch = max(minY, 0)
            RecipeImage(recipe: recipe, size: .original)
                .frame(width: proxy.size.width, height: proxy.size.height + stretch)
                .offset(y: -stretch)
        }
        .aspectRatio(Theme.Aspect.hero, contentMode: .fit)
        .frame(maxHeight: 520)
        .clipped(antialiased: false)
        .accessibilityHidden(true)
    }
}

// MARK: - Header

private struct RecipeHeader: View {
    let model: RecipeDetailModel
    let recipe: Recipe
    let onRate: (Double?) -> Void

    @State private var userData = RecipeUserData.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(recipe.displayName)
                .font(.recipeTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            RatingControl(myRating: userData.rating(for: recipe.id), average: recipe.rating, onRate: onRate)

            if let description = recipe.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                Text(description)
                    .font(.body)
                    .lineSpacing(Theme.LineSpacing.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TimesRow(recipe: recipe)
        }
    }
}

/// Five stars: the user's own rating (tap to set, tap again to clear); shows the household
/// average when the user hasn't rated.
struct RatingControl: View {
    let myRating: Double?
    let average: Double?
    let onRate: (Double?) -> Void

    var body: some View {
        let shown = myRating ?? average ?? 0
        let stars = HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                starButton(star, shown: shown)
            }
        }
        .fixedSize()
        .sensoryFeedback(.selection, trigger: myRating)
        let label = Text(caption)
            .font(.metadata)
            .foregroundStyle(.secondary)
        // At large text sizes the caption moves under the stars instead of squeezing them.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.s) { stars; label }
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) { stars; label }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            let current = Int((myRating ?? 0).rounded())
            switch direction {
            case .increment: onRate(Double(min(current + 1, 5)))
            case .decrement: onRate(current <= 1 ? nil : Double(current - 1))
            @unknown default: break
            }
        }
    }

    private func starButton(_ star: Int, shown: Double) -> some View {
        let current: Int? = myRating.map { Int($0.rounded()) }
        let style: AnyShapeStyle
        if myRating != nil {
            style = AnyShapeStyle(.tint)
        } else if shown > 0 {
            style = AnyShapeStyle(Color.accentColor.opacity(0.45))
        } else {
            style = AnyShapeStyle(.tertiary)
        }
        return Button {
            onRate(current == star ? nil : Double(star))
        } label: {
            Image(systemName: symbol(for: star, value: shown))
                .font(.title3)
                .foregroundStyle(style)
                .frame(minWidth: 32, minHeight: 36)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var caption: String {
        if myRating != nil { return "Your rating" }
        if let average = RecipeFormatting.rating(average) { return "\(average) average" }
        return "Tap to rate"
    }

    private var accessibilityValue: String {
        if let myRating { return "Your rating: \(Int(myRating.rounded())) of 5 stars" }
        if let average = RecipeFormatting.rating(average) { return "Average \(average) of 5 stars, not rated by you" }
        return "Not rated"
    }

    private func symbol(for star: Int, value: Double) -> String {
        if value >= Double(star) - 0.25 { return "star.fill" }
        if value >= Double(star) - 0.75 { return "star.leadinghalf.filled" }
        return "star"
    }
}

/// Prep / cook / total time and yield.
private struct TimesRow: View {
    let recipe: Recipe

    var body: some View {
        let items = entries
        if !items.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Theme.Spacing.xl) { cells(items) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: Theme.Spacing.s) {
                    cells(items)
                }
            }
        }
    }

    private struct Entry: Hashable {
        var label: String
        var value: String
        var spoken: String
    }

    private var entries: [Entry] {
        var result: [Entry] = []
        func add(_ label: String, _ raw: String?) {
            guard let value = RecipeFormatting.duration(raw) else { return }
            result.append(Entry(label: label, value: value, spoken: RecipeFormatting.spokenDuration(raw) ?? value))
        }
        add("Prep", recipe.prepTime)
        add("Cook", recipe.cookTime ?? recipe.performTime)
        add("Total", recipe.totalTime)
        if let yield = recipe.recipeYield?.trimmingCharacters(in: .whitespacesAndNewlines), !yield.isEmpty {
            let quantity = recipe.recipeYieldQuantity.flatMap { $0 > 0 ? IngredientFormatting.quantity($0) : nil }
            let value = [quantity, yield].compactMap { $0 }.joined(separator: " ")
            result.append(Entry(label: "Makes", value: value, spoken: value))
        }
        return result
    }

    @ViewBuilder
    private func cells(_ items: [Entry]) -> some View {
        ForEach(items, id: \.self) { entry in
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.label)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(entry.value)
                    .font(.body.weight(.medium))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(entry.label): \(entry.spoken)")
        }
    }
}

// MARK: - Activity sheet

/// Share sheet for plain text (ShareLink can't be triggered programmatically).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
