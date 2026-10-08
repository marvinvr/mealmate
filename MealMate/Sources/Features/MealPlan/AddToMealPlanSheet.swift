import SwiftUI

/// "Add to Meal Plan" for a recipe: pick a day (next 7 days or any date) and a meal.
///
/// Present it from the recipe screen:
/// ```swift
/// .sheet(isPresented: $plansMeal) { AddToMealPlanSheet(recipe: recipe) }
/// ```
struct AddToMealPlanSheet: View {
    private let source: Source

    private enum Source {
        case recipe(RecipeSummary)
        case slug(String)
    }

    init(recipe: RecipeSummary) {
        source = .recipe(recipe)
    }

    init(recipe: Recipe) {
        source = .recipe(recipe.summary)
    }

    /// Loads the recipe first (deep links, DEBUG routes).
    init(slug: String) {
        source = .slug(slug)
    }

    var body: some View {
        switch source {
        case .recipe(let recipe):
            AddToMealPlanForm(recipe: recipe)
        case .slug(let slug):
            RecipeLoadingSheet(slug: slug, title: "Add to Meal Plan") { recipe in
                AddToMealPlanForm(recipe: recipe.summary)
            }
        }
    }
}

private struct AddToMealPlanForm: View {
    let recipe: RecipeSummary

    @Environment(\.mealie) private var mealie
    @Environment(\.dismiss) private var dismiss
    @State private var day = MealieDay.today
    @State private var type: PlanEntryType = MealPlanLayout.suggestedMealType(for: .today)
    @State private var showsCalendar = false
    @State private var dayEntries: [MealPlanEntry] = []
    @State private var isSaving = false
    @State private var error: MealieError?
    @State private var toast: ActionToast?
    @State private var successFeedback = 0
    @State private var errorFeedback = 0

    private var quickDays: [MealieDay] {
        (0..<7).map { MealieDay.today.adding(days: $0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: Theme.Spacing.s) {
                        RecipeImage(recipe: recipe, size: .tiny)
                            .frame(width: 44, height: 44)
                            .recipeImageShape(cornerRadius: Theme.Radius.thumbnail)
                        Text(recipe.displayName)
                            .font(.recipeRowTitle)
                            .lineLimit(2)
                    }
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
                }

                if !dayEntries.isEmpty {
                    Section("Already Planned") {
                        ForEach(dayEntries) { entry in
                            LabeledContent {
                                Text(entry.entryType.title)
                            } label: {
                                Text(entry.displayTitle)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
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
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Add", systemImage: "checkmark") { Task { await add() } }
                            .disabled(toast != nil)
                    }
                }
            }
            .actionToast($toast)
            .task(id: day) { await loadDayEntries() }
            .alert(isPresented: errorBinding, error: error) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.recoverySuggestion ?? "Nothing was added. Try again.")
            }
        }
        .sensoryFeedback(.selection, trigger: day)
        .sensoryFeedback(.success, trigger: successFeedback)
        .sensoryFeedback(.error, trigger: errorFeedback)
    }

    private var dateBinding: Binding<Date> {
        Binding { day.date() } set: { day = MealieDay($0) }
    }

    private var errorBinding: Binding<Bool> {
        Binding { error != nil } set: { if !$0 { error = nil } }
    }

    private func loadDayEntries() async {
        let entries = (try? await mealie.mealPlan(from: day, to: day)) ?? []
        withAnimation(.snappy) { dayEntries = MealPlanLayout.sorted(entries) }
    }

    private func add() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let entry = try await mealie.createMealPlanEntry(MealPlanEntryCreate(date: day, entryType: type, recipeId: recipe.id))
            successFeedback += 1
            toast = ActionToast(message: "Planned for \(entry.date.relativeName().lowercasedIfRelative), \(type.title.lowercased())",
                                systemImage: "calendar.badge.checkmark", duration: .seconds(2))
            try? await Task.sleep(for: .seconds(1.2))
            dismiss()
        } catch {
            let error = MealieError.wrap(error)
            guard error != .cancelled else { return }
            errorFeedback += 1
            self.error = error
        }
    }
}

/// Day option chip: "Today", "Tomorrow", "Sat 10".
struct DayChip: View {
    let day: MealieDay
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(topLine)
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            Text(day.date().formatted(.dateTime.day()))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .frame(minWidth: 52, minHeight: 52)
        .padding(.horizontal, Theme.Spacing.xs)
        .background(
            isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.16)) : AnyShapeStyle(.mealMateSurfaceSecondary),
            in: .rect(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
        )
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.relativeName() + ", " + day.date().formatted(date: .long, time: .omitted))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var topLine: String {
        let today = MealieDay.today
        if day == today { return "Today" }
        if day == today.adding(days: 1) { return "Tomorrow" }
        return day.date().formatted(.dateTime.weekday(.abbreviated))
    }
}

private extension String {
    /// "Today" → "today" inside a sentence; weekday names stay capitalised.
    var lowercasedIfRelative: String {
        ["Today", "Tomorrow", "Yesterday"].contains(self) ? lowercased() : self
    }
}
