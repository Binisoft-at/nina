import Testing
@testable import NinaCore

/// Deleting an own meal that entries or routines still use (D16): the question, the buttons and
/// the toast. Made-up meals.
@Suite("Meal removal")
struct MealRemovalTests {
    static let jause = MealSlot(id: "meal-1a2b3c4d", name: "Jause", emoji: "🥪", minutes: 10 * 60)
    static let meals: [MealSlot] = MealSlot.defaults + [jause]

    @Test func unusedMealGoesWithoutAQuestion() {
        let removal = NinaMealRemoval(slot: Self.jause, entries: 0, routines: 0, meals: Self.meals)
        #expect(!removal.isUsed)
        #expect(removal.toast(moved: true) == "Deleted \u{201C}Jause\u{201D}")
    }

    @Test func countsEntriesAndRoutines() {
        let removal = NinaMealRemoval(slot: Self.jause, entries: 12, routines: 1, meals: Self.meals)
        #expect(removal.isUsed)
        #expect(removal.usage == "12 entries and 1 routine")
        #expect(removal.question == "12 entries and 1 routine use \u{201C}Jause\u{201D}.")
        #expect(removal.moveTitle == "Move Them to Snacks")
        #expect(removal.keepTitle == "Keep Them as They Are")
        #expect(removal.toast(moved: true) == "Deleted \u{201C}Jause\u{201D} · 12 entries and 1 routine moved to Snacks")
        #expect(removal.toast(moved: false) == "Deleted \u{201C}Jause\u{201D}")
    }

    @Test func singularTexts() {
        let one = NinaMealRemoval(slot: Self.jause, entries: 1, routines: 0, meals: Self.meals)
        #expect(one.question == "1 entry uses \u{201C}Jause\u{201D}.")
        #expect(one.moveTitle == "Move It to Snacks")
        #expect(one.keepTitle == "Keep It as It Is")
        let routines = NinaMealRemoval(slot: Self.jause, entries: 0, routines: 2, meals: Self.meals)
        #expect(routines.usage == "2 routines")
    }

    @Test func movesToSnacksUnderItsOwnName() {
        var meals = Self.meals
        if let index = meals.firstIndex(where: { $0.id == "snack" }) { meals[index].name = "Zwischendurch" }
        let removal = NinaMealRemoval(slot: Self.jause, entries: 3, routines: 0, meals: meals)
        #expect(removal.target.id == "snack")
        #expect(removal.moveTitle == "Move Them to Zwischendurch")
    }

    @Test func emptyNameReadsMeal() {
        var unnamed = Self.jause
        unnamed.name = "  "
        let removal = NinaMealRemoval(slot: unnamed, entries: 2, routines: 0, meals: Self.meals)
        #expect(removal.question == "2 entries use \u{201C}Meal\u{201D}.")
    }
}
