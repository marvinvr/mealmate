import Foundation
import Testing
@testable import MealMate

// MARK: - Shopping list layout

struct ShoppingListLayoutTests {
    private let produce = MultiPurposeLabel(id: "label-produce", name: "Produce", color: "#959595")
    private let dairy = MultiPurposeLabel(id: "label-dairy", name: "Dairy", color: "#4E7048")
    private let bakery = MultiPurposeLabel(id: "label-bakery", name: "Bakery", color: nil)

    private func item(_ id: String, _ text: String, label: MultiPurposeLabel? = nil, checked: Bool = false,
                      position: Int = 0, created: TimeInterval = 0, updated: TimeInterval? = nil) -> ShoppingListItem {
        var item = ShoppingListItem(id: id, shoppingListId: "list", quantity: 0, note: text, display: text,
                                    checked: checked, createdAt: Date(timeIntervalSince1970: created))
        item.label = label
        item.labelId = label?.id
        item.position = position
        item.updatedAt = updated.map(Date.init(timeIntervalSince1970:))
        return item
    }

    private func setting(_ label: MultiPurposeLabel, _ position: Int) -> ShoppingList.LabelSetting {
        ShoppingList.LabelSetting(id: "setting-\(label.id)", shoppingListId: "list", labelId: label.id, position: position, label: label)
    }

    @Test func groupsByLabelInListOrderWithNoLabelLast() {
        let items = [
            item("1", "Paper towels"),
            item("2", "Milk", label: dairy),
            item("3", "Apples", label: produce),
            item("4", "Rolls", label: bakery),
        ]
        let sections = ShoppingListLayout.sections(for: items, labelSettings: [setting(dairy, 0), setting(produce, 1)])
        // Ordered labels first (by position), then labels without a setting (by name), "No Label" last.
        #expect(sections.map(\.title) == ["Dairy", "Produce", "Bakery", "No Label"])
        #expect(sections.last?.id == ShoppingSection.noLabelID)
    }

    @Test func labelsWithoutSettingsSortByName() {
        let items = [item("1", "Rolls", label: bakery), item("2", "Apples", label: produce), item("3", "Milk", label: dairy)]
        #expect(ShoppingListLayout.sections(for: items).map(\.title) == ["Bakery", "Dairy", "Produce"])
    }

    @Test func fallsBackToTheFoodsLabel() {
        var milk = item("1", "Milk")
        milk.food = IngredientFood(id: "food-milk", name: "Milk", label: dairy)
        #expect(ShoppingListLayout.sections(for: [milk]).map(\.title) == ["Dairy"])
    }

    @Test func itemsSortByPositionThenAge() {
        let items = [
            item("late", "B", label: produce, position: 0, created: 200),
            item("early", "C", label: produce, position: 0, created: 100),
            item("first", "Z", label: produce, position: -1, created: 300),
        ]
        let section = ShoppingListLayout.sections(for: items).first
        #expect(section?.items.map(\.id) == ["first", "early", "late"])
    }

    @Test func checkedItemsLeaveTheirSectionNewestFirst() {
        let items = [
            item("open", "Apples", label: produce),
            item("old", "Milk", label: dairy, checked: true, updated: 100),
            item("new", "Rolls", label: bakery, checked: true, updated: 200),
        ]
        let sections = ShoppingListLayout.sections(for: items)
        #expect(sections.flatMap(\.items).map(\.id) == ["open"])
        #expect(ShoppingListLayout.checkedItems(items).map(\.id) == ["new", "old"])
        #expect(ShoppingListLayout.uncheckedCount(items) == 1)
    }

    @Test func justCheckedItemsStayInPlace() {
        let items = [item("a", "Apples", label: produce), item("b", "Milk", label: dairy, checked: true)]
        let sections = ShoppingListLayout.sections(for: items, keepInPlace: ["b"])
        #expect(sections.flatMap(\.items).map(\.id).sorted() == ["a", "b"])
        #expect(ShoppingListLayout.checkedItems(items, excluding: ["b"]).isEmpty)
    }

    @Test func emptySectionsAreDropped() {
        let items = [item("1", "Milk", label: dairy, checked: true)]
        #expect(ShoppingListLayout.sections(for: items).isEmpty)
    }

    @Test func onlyCustomLabelColoursShow() {
        #expect(produce.customColor == nil) // Mealie's default grey
        #expect(dairy.customColor != nil)
        #expect(bakery.customColor == nil)
        #expect(MultiPurposeLabel(id: "x", name: "x", color: "not a colour").customColor == nil)
    }
}

// MARK: - Parsed ingredient → shopping item

struct ShoppingItemDraftTests {
    private func parsed(quantity: Double?, unit: IngredientUnit?, food: IngredientFood?, note: String? = nil) -> ParsedIngredient {
        ParsedIngredient(input: nil, confidence: nil,
                         ingredient: RecipeIngredient(quantity: quantity, unit: unit, food: food, note: note))
    }

    @Test func fixtureMapsToKnownFoodAndUnit() throws {
        let result = try Fixture.decode(ParsedIngredient.self, from: "parsed-ingredient")
        let item = ShoppingItemDraft.item(from: result, input: "2 cups flour", listID: "list")
        #expect(item.shoppingListId == "list")
        #expect(item.quantity == 2)
        #expect(item.unitId == result.ingredient.unit?.id)
        #expect(item.foodId == result.ingredient.food?.id)
        #expect(item.labelId == result.ingredient.food?.labelId)
        #expect(item.note == "")
    }

    @Test func unknownFoodBecomesNoteWithKnownUnit() {
        let pack = IngredientUnit(id: "unit-pack", name: "pack")
        let result = parsed(quantity: 2, unit: pack, food: IngredientFood(id: nil, name: "dish soap"))
        let item = ShoppingItemDraft.item(from: result, input: "2 packs dish soap", listID: "list")
        #expect(item.quantity == 2)
        #expect(item.unitId == "unit-pack")
        #expect(item.foodId == nil)
        #expect(item.note == "dish soap")
    }

    @Test func nothingKnownKeepsTheTypedText() {
        let result = parsed(quantity: 0, unit: nil, food: IngredientFood(id: nil, name: "toilet paper"))
        let item = ShoppingItemDraft.item(from: result, input: "  Toilet paper ", listID: "list")
        #expect(item.note == "Toilet paper")
        #expect(item.foodId == nil && item.unitId == nil)
        #expect(item.quantity == 0)
    }

    @Test func parserFailureFallsBackToNote() {
        let item = ShoppingItemDraft.item(from: nil, input: "3 Zucchini, small", listID: "list")
        #expect(item.note == "3 Zucchini, small")
        #expect(item.quantity == 0)
        #expect(item.foodId == nil)
    }

    @Test func knownFoodWithoutQuantityAndCommentNote() {
        let milk = IngredientFood(id: "food-milk", name: "milk", labelId: "label-dairy")
        let result = parsed(quantity: 0, unit: nil, food: milk, note: "oat")
        let item = ShoppingItemDraft.item(from: result, input: "milk, oat", listID: "list")
        #expect(item.foodId == "food-milk")
        #expect(item.quantity == 0) // shows as "milk", not "1 milk"
        #expect(item.labelId == "label-dairy")
        #expect(item.note == "oat")
    }

    @Test func unknownUnitIsKeptInNote() {
        let basil = IngredientFood(id: "food-basil", name: "basil")
        let result = parsed(quantity: 2, unit: IngredientUnit(id: nil, name: "bunches"), food: basil)
        let item = ShoppingItemDraft.item(from: result, input: "2 bunches basil", listID: "list")
        #expect(item.unitId == nil)
        #expect(item.foodId == "food-basil")
        #expect(item.note == "bunches")
    }

    @Test func placeholderIsPending() {
        let placeholder = ShoppingItemDraft.placeholder(for: " eggs ", listID: "list")
        #expect(placeholder.isPending)
        #expect(placeholder.displayText == "eggs")
    }

    @Test func freeTextWithDefaultQuantityShowsOnlyTheNote() {
        var item = ShoppingListItem(id: "1", shoppingListId: "list", quantity: 1, note: "2 Lemons",
                                    display: "1 2 Lemons", checked: false, createdAt: nil)
        #expect(item.displayText == "2 Lemons")
        item.quantity = 3
        item.note = "Lemons"
        item.display = "3 Lemons"
        #expect(item.displayText == "3 Lemons")
        item.quantity = 1
        item.food = IngredientFood(id: "food-lemon", name: "lemon")
        item.note = nil
        item.display = "1 lemon"
        #expect(item.displayText == "1 lemon")
    }
}

// MARK: - Weeks

struct MealPlanWeekTests {
    private func calendar(firstWeekday: Int, timeZone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = firstWeekday
        calendar.timeZone = TimeZone(identifier: timeZone)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    @Test func mondayFirstWeek() {
        let cal = calendar(firstWeekday: 2, timeZone: "Europe/Zurich")
        let week = MealPlanWeek(containing: MealieDay(year: 2026, month: 10, day: 8), calendar: cal) // Thursday
        #expect(week.start == MealieDay(year: 2026, month: 10, day: 5))
        #expect(week.end == MealieDay(year: 2026, month: 10, day: 11))
        #expect(week.days.count == 7)
    }

    @Test func sundayFirstWeek() {
        let cal = calendar(firstWeekday: 1, timeZone: "America/New_York")
        let week = MealPlanWeek(containing: MealieDay(year: 2026, month: 10, day: 8), calendar: cal)
        #expect(week.start == MealieDay(year: 2026, month: 10, day: 4))
        #expect(week.end == MealieDay(year: 2026, month: 10, day: 10))
    }

    @Test func firstDayOfWeekIsItsOwnStart() {
        let cal = calendar(firstWeekday: 2, timeZone: "Europe/Zurich")
        let monday = MealieDay(year: 2026, month: 10, day: 5)
        #expect(MealPlanWeek(containing: monday, calendar: cal).start == monday)
        let sunday = MealieDay(year: 2026, month: 10, day: 11)
        #expect(MealPlanWeek(containing: sunday, calendar: cal).start == monday)
    }

    @Test func daylightSavingWeeksHaveSevenConsecutiveDays() {
        // Europe ends DST on Sunday 2026-10-25; the US on Sunday 2026-11-01.
        for (zone, first, day) in [("Europe/Zurich", 2, MealieDay(year: 2026, month: 10, day: 25)),
                                   ("America/New_York", 1, MealieDay(year: 2026, month: 11, day: 1)),
                                   ("Europe/Zurich", 2, MealieDay(year: 2026, month: 3, day: 29))] {
            let cal = calendar(firstWeekday: first, timeZone: zone)
            let week = MealPlanWeek(containing: day, calendar: cal)
            #expect(week.days.contains(day))
            for (lhs, rhs) in zip(week.days, week.days.dropFirst()) {
                #expect(lhs.adding(days: 1, calendar: cal) == rhs)
            }
            #expect(week.offset(by: 1, calendar: cal).start == week.start.adding(days: 7, calendar: cal))
        }
    }

    @Test func midnightSkippingDSTStillWorks() {
        // São Paulo skipped 2018-11-04 00:00 (clocks jumped to 01:00).
        let cal = calendar(firstWeekday: 1, timeZone: "America/Sao_Paulo")
        let day = MealieDay(year: 2018, month: 11, day: 4)
        let week = MealPlanWeek(containing: day, calendar: cal)
        #expect(week.start == day) // a Sunday
        #expect(week.end == MealieDay(year: 2018, month: 11, day: 10))
    }

    @Test func offsetsAcrossYearBoundary() {
        let cal = calendar(firstWeekday: 2, timeZone: "Europe/Zurich")
        let week = MealPlanWeek(containing: MealieDay(year: 2026, month: 12, day: 30), calendar: cal)
        #expect(week.start == MealieDay(year: 2026, month: 12, day: 28))
        #expect(week.end == MealieDay(year: 2027, month: 1, day: 3))
        #expect(week.offset(by: 1, calendar: cal).start == MealieDay(year: 2027, month: 1, day: 4))
        #expect(week.offset(by: -1, calendar: cal).start == MealieDay(year: 2026, month: 12, day: 21))
        #expect(week.contains(MealieDay(year: 2027, month: 1, day: 1)))
        #expect(!week.contains(MealieDay(year: 2027, month: 1, day: 4)))
    }

    @Test func titleShowsYearOnlyWhenNeeded() {
        let cal = calendar(firstWeekday: 2, timeZone: "Europe/Zurich")
        let today = MealieDay(year: 2026, month: 10, day: 8)
        let thisYear = MealPlanWeek(containing: today, calendar: cal).title(calendar: cal, today: today)
        #expect(!thisYear.contains("2026"))
        let spanning = MealPlanWeek(containing: MealieDay(year: 2026, month: 12, day: 30), calendar: cal).title(calendar: cal, today: today)
        #expect(spanning.contains("2026") && spanning.contains("2027"))
    }
}

// MARK: - Meal types

struct MealPlanLayoutTests {
    private func entry(_ id: Int, _ type: PlanEntryType, day: MealieDay = MealieDay(year: 2030, month: 1, day: 7)) -> MealPlanEntry {
        MealPlanEntry(id: id, date: day, entryType: type, title: "Entry \(id)")
    }

    @Test func mealTypesSortInDayOrderWithUnknownLast() {
        let entries = [entry(1, .dessert), entry(2, "brunch"), entry(3, .breakfast), entry(4, .dinner), entry(5, .lunch), entry(6, .side)]
        #expect(MealPlanLayout.sorted(entries).map(\.entryType) == [.breakfast, .lunch, .dinner, .side, .dessert, "brunch"])
    }

    @Test func sameTypeKeepsCreationOrder() {
        let entries = [entry(9, .dinner), entry(3, .dinner), entry(5, .lunch)]
        #expect(MealPlanLayout.sorted(entries).map(\.id) == [5, 3, 9])
    }

    @Test func groupsEveryDayOfTheWeek() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let monday = MealieDay(year: 2030, month: 1, day: 7)
        let week = MealPlanWeek(containing: monday, calendar: cal)
        let outside = entry(7, .dinner, day: MealieDay(year: 2030, month: 1, day: 14))
        let byDay = MealPlanLayout.entriesByDay([entry(1, .dinner), entry(2, .breakfast), outside], in: week)
        #expect(byDay.count == 7)
        #expect(byDay[monday]?.map(\.id) == [2, 1])
        #expect(byDay.values.flatMap { $0 }.contains { $0.id == 7 } == false)
    }

    @Test func allMealieMealTypesAreOffered() {
        #expect(MealPlanLayout.mealTypes.map(\.rawValue) == ["breakfast", "lunch", "dinner", "side", "snack", "drink", "dessert"])
    }

    @Test func suggestedMealTypeFollowsTheClockToday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let morning = cal.date(from: DateComponents(year: 2030, month: 1, day: 7, hour: 8))!
        let noon = cal.date(from: DateComponents(year: 2030, month: 1, day: 7, hour: 12))!
        let evening = cal.date(from: DateComponents(year: 2030, month: 1, day: 7, hour: 18))!
        let today = MealieDay(year: 2030, month: 1, day: 7)
        #expect(MealPlanLayout.suggestedMealType(for: today, now: morning, calendar: cal) == .breakfast)
        #expect(MealPlanLayout.suggestedMealType(for: today, now: noon, calendar: cal) == .lunch)
        #expect(MealPlanLayout.suggestedMealType(for: today, now: evening, calendar: cal) == .dinner)
        #expect(MealPlanLayout.suggestedMealType(for: today.adding(days: 1, calendar: cal), now: morning, calendar: cal) == .dinner)
    }

    @Test func dragPayloadRoundTrips() {
        let payload = MealPlanDrag.payload(for: entry(42, .dinner))
        #expect(MealPlanDrag.entryID(payload) == 42)
        #expect(MealPlanDrag.entryID("42") == nil)
    }
}

// MARK: - Add to shopping list

@MainActor
struct AddToShoppingListModelTests {
    private func recipe(onHandFoodIndex: Int, household: String) throws -> Recipe {
        var recipe = try Fixture.decode(Recipe.self, from: "recipe-full")
        recipe.recipeIngredient?[onHandFoodIndex].food?.householdsWithIngredientFood = [household]
        return recipe
    }

    @Test func onHandFoodsStartUnticked() throws {
        let model = AddToShoppingListModel(recipe: try recipe(onHandFoodIndex: 1, household: "home"), scale: 1, householdSlug: "home")
        let onHand = try #require(model.ingredients.first { $0.ingredient.food?.name == "Egg" })
        #expect(!model.selection.contains(onHand.index))
        #expect(model.selection.count == model.ingredients.count - 1)
    }

    @Test func householdArrivingLaterUnticksOnHandFoods() throws {
        let model = AddToShoppingListModel(recipe: try recipe(onHandFoodIndex: 1, household: "home"), scale: 1, householdSlug: nil)
        #expect(model.selection.count == model.ingredients.count)
        model.applyHousehold("home")
        #expect(model.selection.count == model.ingredients.count - 1)
        // Only the first known household applies; later manual choices stay.
        model.selectAll(true)
        model.applyHousehold("home")
        #expect(model.selection.count == model.ingredients.count)
    }
}

// MARK: - Shopping for the meal plan

struct MealPlanShoppingTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return cal
    }()
    private let monday = MealieDay(year: 2030, month: 1, day: 7)
    private var week: MealPlanWeek { MealPlanWeek(containing: monday, calendar: calendar) }

    private func day(_ offset: Int) -> MealieDay { monday.adding(days: offset, calendar: calendar) }

    private func recipe(_ id: Int, _ recipeID: String, day: MealieDay, type: PlanEntryType = .dinner) -> MealPlanEntry {
        MealPlanEntry(id: id, date: day, entryType: type, recipeId: recipeID)
    }

    private func note(_ id: Int, day: MealieDay) -> MealPlanEntry {
        MealPlanEntry(id: id, date: day, entryType: .dinner, title: "Leftovers")
    }

    @Test func offersRecipesByDayWithoutNotesOrOtherWeeks() {
        let entries = [
            recipe(1, "soup", day: day(2)),
            note(2, day: day(2)),
            recipe(3, "porridge", day: day(2), type: .breakfast),
            recipe(4, "pasta", day: day(0)),
            note(5, day: day(4)),
            recipe(6, "curry", day: day(7)),
        ]
        let days = MealPlanShopping.days(entries, in: week)
        #expect(days.map(\.day) == [day(0), day(2)])
        #expect(days.last?.entries.map(\.id) == [3, 1])
    }

    @Test func recipeKnownOnlyFromTheSummaryCounts() {
        var entry = MealPlanEntry(id: 1, date: monday, entryType: .lunch)
        #expect(MealPlanShopping.recipeID(of: entry) == nil)
        entry.recipe = RecipeSummary(id: "r1", slug: "lemon-herb-chicken")
        #expect(MealPlanShopping.recipeID(of: entry) == "r1")
    }

    @Test func todayAndLaterStartTicked() {
        let entries = [recipe(1, "a", day: day(0)), recipe(2, "b", day: day(2)), recipe(3, "c", day: day(3)), recipe(4, "d", day: day(6))]
        let days = MealPlanShopping.days(entries, in: week)
        #expect(MealPlanShopping.defaultSelection(days, today: day(2)) == [2, 3, 4])
        // A past week starts empty, a future week fully ticked.
        #expect(MealPlanShopping.defaultSelection(days, today: day(9)).isEmpty)
        #expect(MealPlanShopping.defaultSelection(days, today: day(-3)) == [1, 2, 3, 4])
    }

    @Test func oneDayTicksOnlyThatDayEvenInThePast() {
        let entries = [recipe(1, "a", day: day(0)), recipe(2, "b", day: day(0), type: .lunch), recipe(3, "c", day: day(3))]
        let days = MealPlanShopping.days(entries, in: week)
        #expect(MealPlanShopping.defaultSelection(days, today: day(2), only: day(0)) == [1, 2])
    }

    @Test func repeatedRecipesMergeIntoOneScaledRequest() {
        let entries = [recipe(1, "soup", day: day(0)), recipe(2, "pasta", day: day(1)), recipe(3, "soup", day: day(4)), note(4, day: day(5))]
        let requests = MealPlanShopping.requests(for: entries)
        #expect(requests.map(\.recipeId) == ["soup", "pasta"])
        #expect(requests.map(\.recipeIncrementQuantity) == [2, 1])
        #expect(requests.allSatisfy { $0.recipeIngredients == nil })
        #expect(MealPlanShopping.requests(for: [note(1, day: monday)]).isEmpty)
    }

    @MainActor
    @Test func modelForOneDayShowsOnlyThatDay() {
        let entries = [recipe(1, "a", day: day(0)), recipe(2, "b", day: day(3)), note(3, day: day(3))]
        let model = MealPlanShoppingModel(week: week, entries: entries, day: day(3), today: day(1))
        #expect(model.days.map(\.day) == [day(3)])
        #expect(model.selection == [2])
        model.toggle(2)
        #expect(model.selection.isEmpty)
        #expect(!model.canAdd)

        let empty = MealPlanShoppingModel(week: week, entries: [note(3, day: day(3))], day: nil, today: day(1))
        #expect(empty.days.isEmpty)
    }
}
