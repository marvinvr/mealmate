import SwiftUI

/// Meal Plan tab root: a week (locale's first weekday first) with entries per day in meal order
/// (empty days are just a header with a + menu), add / move / delete, and "Suggest a recipe".
struct MealPlanView: View {
    @Environment(\.mealie) private var mealie
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = MealPlanViewModel()
    @State private var editor: EditorItem?
    @State private var addRecipeSlug: String?
    @State private var shoppingSlug: String?
    @State private var deleting: MealPlanEntry?
    /// Scrolls the list to a day's section (today on first appear and after "Today").
    @State private var scrollRequest: ScrollRequest?
    @State private var didScrollToToday = false

    struct ScrollRequest: Equatable {
        let id = UUID()
        let day: MealieDay
        let animated: Bool
    }

    struct EditorItem: Identifiable {
        let id = UUID()
        let mode: MealPlanEntryEditor.Mode
    }

    var body: some View {
        @Bindable var model = model
        ScrollViewReader { proxy in
            List {
                Section {
                    WeekStrip(week: model.week, entriesByDay: model.entriesByDay,
                              previous: { Task { await model.showWeek(offset: -1) } },
                              next: { Task { await model.showWeek(offset: 1) } },
                              select: { day in
                                  withAnimation(.smooth) { proxy.scrollTo(day.description, anchor: .top) }
                              })
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } footer: {
                    if model.phase == .loaded, model.isEmpty {
                        Text("Nothing planned this week. Tap + on a day to add a recipe or a note.")
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                }
                .listSectionSpacing(Theme.Spacing.xs)

                content
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(Theme.Spacing.l)
            .screenBackground()
            .refreshable { await model.refresh() }
            .animation(.snappy, value: model.week)
            .onChange(of: scrollRequest) { _, request in
                guard let request else { return }
                if request.animated {
                    withAnimation(.smooth) { proxy.scrollTo(request.day.description, anchor: .top) }
                } else {
                    proxy.scrollTo(request.day.description, anchor: .top)
                }
            }
        }
        .navigationTitle("Meal Plan")
        .toolbar {
            if !model.isCurrentWeek {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") {
                        Task {
                            await model.showToday()
                            scrollToToday(animated: true)
                        }
                    }
                }
            }
        }
        .task {
            await model.load(using: mealie)
            if !didScrollToToday {
                didScrollToToday = true
                // Let the loaded days lay out first; no animation on first load.
                await Task.yield()
                scrollToToday(animated: false)
            }
            await consumeIntent()
        }
        .onChange(of: router.pendingIntent) { Task { await consumeIntent() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
        .sensoryFeedback(.success, trigger: model.successFeedback)
        .sensoryFeedback(.error, trigger: model.errorFeedback)
        .actionToast($model.toast) {
            Task { await model.undoSuggestion() }
        }
        .sheet(item: $editor) { item in
            MealPlanEntryEditor(mode: item.mode, onAdd: { create in
                await model.add(create) != nil
            }, onSave: { updated in
                if case .edit(let original) = item.mode {
                    Task { await model.save(updated, original: original) }
                }
            }, onDelete: { entry in
                Task { await model.delete(entry) }
            })
        }
        .sheet(item: slugBinding($addRecipeSlug)) { item in
            AddToMealPlanSheet(slug: item.id)
                .onDisappear { Task { await model.refresh() } }
        }
        .sheet(item: slugBinding($shoppingSlug)) { item in
            AddToShoppingListSheet(slug: item.id)
        }
        .alert(isPresented: errorBinding, error: model.actionError) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.recoverySuggestion ?? "Your change was undone. Try again.")
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            Section {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .listRowBackground(Color.clear)
            }
        case .failed(let error):
            Section {
                ContentUnavailableView {
                    Label("Can’t Load Meal Plan", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error.errorDescription ?? "Check your connection, then try again.")
                } actions: {
                    Button("Try Again") { Task { await model.refresh() } }
                        .buttonStyle(.bordered)
                }
                .listRowBackground(Color.clear)
            }
        case .loaded:
            if let refreshError = model.refreshError {
                Label(refreshError, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            days
        }
    }

    private var days: some View {
        let byDay = model.entriesByDay
        return ForEach(model.week.days, id: \.self) { day in
            Section {
                // Empty days are just their header (with the + menu): the week stays short
                // and calm instead of seven "plan a meal" rows.
                ForEach(byDay[day] ?? []) { entry in
                    entryRow(entry)
                }
            } header: {
                DayHeader(day: day, isSuggesting: model.suggestingDays.contains(day),
                          add: { kind in addEntry(on: day, kind: kind) },
                          suggest: { type in Task { await model.suggest(on: day, type: type) } })
                    .dropDestination(for: String.self) { items, _ in drop(items, on: day) }
            }
            .id(day.description)
        }
    }

    private func entryRow(_ entry: MealPlanEntry) -> some View {
        Group {
            if let slug = entry.recipe?.slug {
                NavigationLink(value: AppDestination.recipe(slug: slug)) {
                    MealPlanEntryRow(entry: entry)
                }
            } else {
                Button { edit(entry) } label: {
                    MealPlanEntryRow(entry: entry)
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(model.busyEntries.contains(entry.id) ? 0.6 : 1)
        .draggable(MealPlanDrag.payload(for: entry)) {
            MealPlanEntryRow(entry: entry)
                .padding(Theme.Spacing.s)
                .frame(width: 280)
                .background(.mealMateSurface, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .dropDestination(for: String.self) { items, _ in drop(items, on: entry.date) }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await model.delete(entry) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button { edit(entry) } label: {
                Label("Edit", systemImage: "pencil")
            }
        }
        .contextMenu {
            if let slug = entry.recipe?.slug {
                NavigationLink(value: AppDestination.recipe(slug: slug)) {
                    Label("Open Recipe", systemImage: "book.pages")
                }
                Button("Add to Shopping List…", systemImage: "cart.badge.plus") { shoppingSlug = slug }
            }
            Button("Edit…", systemImage: "pencil") { edit(entry) }
            Menu {
                ForEach(model.week.days.filter { $0 != entry.date }, id: \.self) { day in
                    Button("\(day.relativeName()), \(day.shortDate)") {
                        Task { await model.move(entry, to: day) }
                    }
                }
                Divider()
                Button("Same Day Next Week") {
                    Task { await model.move(entry, to: entry.date.adding(days: 7)) }
                }
            } label: {
                Label("Move To", systemImage: "calendar")
            }
            Menu {
                ForEach(MealPlanLayout.mealTypes.filter { $0 != entry.entryType }, id: \.self) { type in
                    Button(type.title, systemImage: type.systemImage) {
                        Task { await model.move(entry, to: entry.date, type: type) }
                    }
                }
            } label: {
                Label("Change Meal", systemImage: entry.entryType.systemImage)
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { await model.delete(entry) }
            }
        }
    }

    // MARK: Actions

    /// Brings today's section to the top in the current week. Skipped when today is the first
    /// day, so the week strip stays visible.
    private func scrollToToday(animated: Bool) {
        guard model.phase == .loaded, model.isCurrentWeek,
              model.week.days.contains(.today), model.week.days.first != .today else { return }
        scrollRequest = ScrollRequest(day: .today, animated: animated)
    }

    private func addEntry(on day: MealieDay, kind: MealPlanEntryEditor.Kind) {
        editor = EditorItem(mode: .add(day: day, type: MealPlanLayout.suggestedMealType(for: day), kind: kind))
    }

    private func edit(_ entry: MealPlanEntry) {
        editor = EditorItem(mode: .edit(entry))
    }

    private func drop(_ items: [String], on day: MealieDay) -> Bool {
        guard let id = items.compactMap(MealPlanDrag.entryID).first,
              let entry = model.entries.first(where: { $0.id == id }) else { return false }
        guard entry.date != day else { return true }
        Task { await model.move(entry, to: day) }
        return true
    }

    /// Deep link / DEBUG route states (see `AppRoute.registry`).
    private func consumeIntent() async {
        if let intent = router.consumeIntent("mealplan-week/"), let day = MealieDay(string: intent.suffix(after: "mealplan-week/")) {
            await model.show(MealPlanWeek(containing: day))
        } else if let intent = router.consumeIntent("mealplan-add-recipe/") {
            addRecipeSlug = intent.suffix(after: "mealplan-add-recipe/")
        } else if let intent = router.consumeIntent("mealplan-add/"), let day = MealieDay(string: intent.suffix(after: "mealplan-add/")) {
            await model.show(MealPlanWeek(containing: day))
            addEntry(on: day, kind: .recipe)
        } else if let intent = router.consumeIntent("mealplan-note/"), let day = MealieDay(string: intent.suffix(after: "mealplan-note/")) {
            await model.show(MealPlanWeek(containing: day))
            addEntry(on: day, kind: .note)
        } else if let intent = router.consumeIntent("mealplan-suggest/"), let day = MealieDay(string: intent.suffix(after: "mealplan-suggest/")) {
            await model.show(MealPlanWeek(containing: day))
            await model.suggest(on: day, type: .dinner)
        } else if let intent = router.consumeIntent("mealplan-entry/"), let id = Int(intent.suffix(after: "mealplan-entry/")) {
            if let entry = model.entries.first(where: { $0.id == id }) {
                edit(entry)
            } else if let entry = try? await mealie.mealPlanEntry(id: id) {
                await model.show(MealPlanWeek(containing: entry.date))
                edit(entry)
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding { model.actionError != nil } set: { if !$0 { model.actionError = nil } }
    }

    private struct SlugItem: Identifiable { let id: String }

    private func slugBinding(_ slug: Binding<String?>) -> Binding<SlugItem?> {
        Binding { slug.wrappedValue.map(SlugItem.init) } set: { slug.wrappedValue = $0?.id }
    }
}

/// Drag payload for moving entries between days (a plain string, so it never leaves the app
/// as anything meaningful).
enum MealPlanDrag {
    static let prefix = "mealmate-mealplan-entry:"
    static func payload(for entry: MealPlanEntry) -> String { prefix + String(entry.id) }
    static func entryID(_ payload: String) -> Int? {
        guard payload.hasPrefix(prefix) else { return nil }
        return Int(payload.dropFirst(prefix.count))
    }
}

private extension String {
    func suffix(after prefix: String) -> String { String(dropFirst(prefix.count)) }
}

// MARK: - Rows & headers

struct MealPlanEntryRow: View {
    let entry: MealPlanEntry

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            PlanningRecipeThumbnail(recipe: entry.recipe, size: 56, systemImage: "note.text")
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Image(systemName: entry.entryType.systemImage)) \(entry.entryType.title)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(entry.displayTitle)
                    .font(entry.recipe != nil ? .recipeRowTitle : .body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if entry.recipe == nil, let text = entry.text, !text.isEmpty, text != entry.displayTitle {
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.entryType.title): \(entry.displayTitle)" + (entry.isNote ? ", note" : ""))
    }
}

private struct DayHeader: View {
    let day: MealieDay
    var isSuggesting: Bool
    var add: (MealPlanEntryEditor.Kind) -> Void
    var suggest: (PlanEntryType) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text(day.relativeName())
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(day == .today ? day.date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) : day.shortDate)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            if isSuggesting {
                ProgressView().controlSize(.small)
            }
            Menu {
                Button("Add Recipe…", systemImage: "book.pages") { add(.recipe) }
                Button("Add Note…", systemImage: "note.text") { add(.note) }
                Divider()
                Menu {
                    ForEach(MealPlanLayout.mealTypes, id: \.self) { type in
                        Button(type.title, systemImage: type.systemImage) { suggest(type) }
                    }
                } label: {
                    Label("Suggest a Recipe", systemImage: "sparkles")
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 32, alignment: .trailing)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Add to \(day.relativeName())")
        }
        .textCase(nil)
    }
}

/// Week navigation: range title with arrows, and the seven days (tap to jump, swipe to
/// change week). Days with entries get a dot.
private struct WeekStrip: View {
    let week: MealPlanWeek
    let entriesByDay: [MealieDay: [MealPlanEntry]]
    var previous: () -> Void
    var next: () -> Void
    var select: (MealieDay) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack {
                Button("Previous Week", systemImage: "chevron.left", action: previous)
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                Spacer()
                Text(week.title())
                    .font(.headline)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                Button("Next Week", systemImage: "chevron.right", action: next)
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
            // Borderless: in a List row, default-style buttons all fire on any tap in the row
            // (previous + next cancelled each other out).
            .buttonStyle(.borderless)
            .fontWeight(.semibold)

            HStack(spacing: 0) {
                ForEach(week.days, id: \.self) { day in
                    Button { select(day) } label: {
                        DayColumn(day: day, hasEntries: !(entriesByDay[day] ?? []).isEmpty)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.xs)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height),
                          abs(value.translation.width) > 50 else { return }
                    if value.translation.width < 0 { next() } else { previous() }
                }
        )
        .accessibilityAction(named: "Previous Week", previous)
        .accessibilityAction(named: "Next Week", next)
        // Seven columns can't grow further on iPhone; the day list below scales fully.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

private struct DayColumn: View {
    let day: MealieDay
    let hasEntries: Bool

    @ScaledMetric(relativeTo: .body) private var circleSide: CGFloat = 36

    var body: some View {
        let isToday = day == .today
        VStack(spacing: Theme.Spacing.xxs) {
            Text(day.date().formatted(.dateTime.weekday(.narrow)))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(day.date().formatted(.dateTime.day()))
                .font(.body.weight(isToday ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .frame(width: circleSide, height: circleSide)
                .background {
                    if isToday {
                        Circle().fill(Color.accentColor.opacity(0.16))
                    }
                }
            Circle()
                .fill(hasEntries ? AnyShapeStyle(.secondary) : AnyShapeStyle(.clear))
                .frame(width: 5, height: 5)
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.date().formatted(date: .complete, time: .omitted) + (hasEntries ? ", has meals" : ""))
        .accessibilityAddTraits(.isButton)
    }
}
