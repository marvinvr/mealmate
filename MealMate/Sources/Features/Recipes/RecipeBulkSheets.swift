import SwiftUI

/// Checkmark for selection mode. On a photo it sits on a dark disc so it reads on light and dark food.
struct RecipeSelectionMark: View {
    var isSelected: Bool
    var onPhoto: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(onPhoto ? .title2.weight(.semibold) : .title3)
            .symbolRenderingMode(onPhoto && isSelected ? .palette : .monochrome)
            .foregroundStyle(primary, secondary)
            .background {
                if onPhoto {
                    Circle()
                        .fill(.black.opacity(0.38))
                        .padding(isSelected ? 3 : 1)
                }
            }
            .accessibilityHidden(true)
    }

    private var primary: AnyShapeStyle {
        if onPhoto, isSelected { return AnyShapeStyle(.white) }
        if isSelected { return AnyShapeStyle(.tint) }
        if onPhoto { return AnyShapeStyle(.white) }
        return AnyShapeStyle(.secondary)
    }

    private var secondary: AnyShapeStyle {
        onPhoto && isSelected ? AnyShapeStyle(Color.accentColor) : primary
    }
}

// MARK: - Progress and summary

/// Progress while a bulk run is going, then the success or failure summary.
/// Partial failures stay on screen until the user dismisses them.
struct RecipeBulkJobSheet: View {
    let job: RecipeBulkJob

    private var detents: Set<PresentationDetent> {
        if case .finished(let result) = job.phase, result.failures.count > 1, result.sharedFailureMessage == nil {
            return [.large]
        }
        return [.medium, .large]
    }

    var body: some View {
        NavigationStack {
            RecipeBulkJobContent(job: job)
        }
        .presentationDetents(detents)
        .presentationSizing(.page)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(job.isRunning)
    }
}

struct RecipeBulkJobContent: View {
    let job: RecipeBulkJob
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch job.phase {
            case .running(let done, let total, let current):
                running(done: done, total: total, current: current)
            case .finished(let result):
                finished(result)
            }
        }
        .screenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if job.isRunning {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { job.cancel() }
                }
            } else {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .sensoryFeedback(trigger: job.finishCount) { _, count in
            guard count > 0 else { return nil }
            return job.finishIsError ? .error : .success
        }
    }

    private var title: String {
        if case .finished(let result) = job.phase { return result.title }
        return job.progressTitle
    }

    private func running(done: Int, total: Int, current: String) -> some View {
        VStack(spacing: Theme.Spacing.l) {
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .padding(.horizontal, Theme.Spacing.xxl)
            Text("\(done) of \(total)")
                .font(.metadata)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(current)
                .font(.recipeRowTitle)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.progressTitle) \(current), \(done) of \(total)")
    }

    @ViewBuilder
    private func finished(_ result: RecipeBulkResult) -> some View {
        if result.failures.count > 1, result.sharedFailureMessage == nil {
            List {
                Section {
                    summaryHeader(result)
                }
                Section("Couldn’t Finish") {
                    ForEach(result.failures) { failure in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(failure.recipeName)
                                .font(.recipeRowTitle)
                                .foregroundStyle(.primary)
                            Text(failure.message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .readableContentWidth()
        } else {
            VStack(spacing: Theme.Spacing.m) {
                Image(systemName: result.failureCount == 0 && result.notAttempted == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(result.failureCount == 0 && result.notAttempted == 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.orange))
                    .accessibilityHidden(true)
                summaryHeader(result)
                if result.failures.count > 1, let shared = result.sharedFailureMessage {
                    Text(shared)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(result.failures.map(\.recipeName).formatted(.list(type: .and, width: .short)))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                } else if let failure = result.failures.first, result.failures.count == 1 {
                    Text(failure.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func summaryHeader(_ result: RecipeBulkResult) -> some View {
        Text(result.summary)
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Add to a shopping list

/// Picks a list, then adds every ingredient of the selected recipes (servings as written)
/// with the bulk `POST …/lists/{id}/recipe` endpoint.
struct RecipeBulkShoppingSheet: View {
    let recipes: [RecipeSummary]
    /// Called when the add starts, so closing the sheet afterwards leaves selection mode.
    var onStarted: () -> Void

    @Environment(\.mealie) private var mealie
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ShoppingListChoice.lastListKey) private var lastListID = ""
    @State private var choice = ShoppingListChoice()
    @State private var job: RecipeBulkJob?

    var body: some View {
        NavigationStack {
            if let job {
                RecipeBulkJobContent(job: job)
            } else {
                form
            }
        }
        .presentationSizing(.page)
        .interactiveDismissDisabled(job?.isRunning == true)
        .task {
            guard job == nil else { return }
            await choice.load(using: mealie, lastListID: lastListID)
        }
    }

    private var form: some View {
        @Bindable var choice = choice
        return Form {
            Section {
                LabeledContent("Recipes", value: "\(recipes.count)")
                Text(recipes.map(\.displayName).formatted(.list(type: .and, width: .short)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            Section {
                ShoppingListPickerRow(choice: choice)
            } footer: {
                Text("Adds every ingredient, at the servings each recipe is written for.")
            }
        }
        .screenBackground()
        .navigationTitle("Add to Shopping List")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add", systemImage: "checkmark") { add() }
                    .disabled(choice.selectedListID == nil || recipes.isEmpty)
            }
        }
    }

    private func add() {
        guard let list = choice.selectedList else { return }
        let listID = list.id
        let phrase = "to “\(list.displayName)”"
        let recipes = recipes
        let service = mealie
        lastListID = listID
        onStarted()
        job = RecipeBulkJob.batch(
            progressTitle: "Adding",
            recipes: recipes,
            successVerb: "Added",
            failureVerb: "added",
            destinationPhrase: phrase
        ) {
            let requests = recipes.map {
                ShoppingListAddRecipe(recipeId: $0.id, recipeIncrementQuantity: 1, recipeIngredients: nil)
            }
            let updated = try await service.addRecipesToShoppingList(listID: listID, recipes: requests)
            await service.storeInCache(updated, key: "shopping.list.\(listID)")
        }
    }
}

// MARK: - Add to the meal plan

/// One day and one meal for every selected recipe. Each entry is its own request,
/// so one rejection doesn't hide the ones that were planned.
struct RecipeBulkMealPlanSheet: View {
    let recipes: [RecipeSummary]
    var onStarted: () -> Void

    @Environment(\.mealie) private var mealie
    @Environment(\.dismiss) private var dismiss
    @State private var day = MealieDay.today
    @State private var type: PlanEntryType = MealPlanLayout.suggestedMealType(for: .today)
    @State private var showsCalendar = false
    @State private var job: RecipeBulkJob?

    private var quickDays: [MealieDay] {
        (0..<7).map { MealieDay.today.adding(days: $0) }
    }

    var body: some View {
        NavigationStack {
            if let job {
                RecipeBulkJobContent(job: job)
            } else {
                form
            }
        }
        .presentationSizing(.page)
        .interactiveDismissDisabled(job?.isRunning == true)
        .sensoryFeedback(.selection, trigger: day)
    }

    private var form: some View {
        Form {
            Section {
                LabeledContent("Recipes", value: "\(recipes.count)")
                Text(recipes.map(\.displayName).formatted(.list(type: .and, width: .short)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            Section("Day") {
                ScrollView(.horizontal) {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(quickDays, id: \.self) { option in
                            Button {
                                withAnimation(.snappy) { day = option }
                            } label: {
                                DayChip(day: option, isSelected: option == day)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, Theme.Spacing.xxs)
                }
                .scrollIndicators(.hidden)
                .listRowInsets(EdgeInsets(top: Theme.Spacing.xs, leading: 0, bottom: Theme.Spacing.xs, trailing: 0))

                DisclosureGroup(isExpanded: $showsCalendar.animation(.snappy)) {
                    DatePicker("Date", selection: dateBinding, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                } label: {
                    LabeledContent("Other Date", value: quickDays.contains(day) ? "" : day.date().formatted(date: .abbreviated, time: .omitted))
                }
            }

            Section {
                Picker("Meal", selection: $type) {
                    ForEach(MealPlanLayout.mealTypes, id: \.self) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.menu)
            } footer: {
                Text("Plans each recipe for this day and meal.")
            }
        }
        .screenBackground()
        .navigationTitle("Add to Meal Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add", systemImage: "checkmark") { add() }
                    .disabled(recipes.isEmpty)
            }
        }
    }

    private var dateBinding: Binding<Date> {
        Binding { day.date() } set: { day = MealieDay($0) }
    }

    private func add() {
        let day = day
        let type = type
        let phrase = "for \(type.title.lowercased()) \(day.phraseInSentence)"
        let recipes = recipes
        let service = mealie
        onStarted()
        job = RecipeBulkJob.each(
            progressTitle: "Planning",
            recipes: recipes,
            successVerb: "Planned",
            failureVerb: "planned",
            destinationPhrase: phrase
        ) { recipe in
            _ = try await service.createMealPlanEntry(MealPlanEntryCreate(date: day, entryType: type, recipeId: recipe.id))
        }
    }
}

private extension MealieDay {
    /// "today", "tomorrow", or "on Saturday" inside a sentence.
    var phraseInSentence: String {
        switch relativeName() {
        case "Today": "today"
        case "Tomorrow": "tomorrow"
        case "Yesterday": "yesterday"
        case let name: "on \(name)"
        }
    }
}
