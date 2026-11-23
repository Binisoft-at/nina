import Foundation
import Testing
@testable import NinaCore

// The log sheet's Recent list sorted for the meal being logged: foods mostly logged at that meal
// first ("Mostly at breakfast"), then the rest by recency. All foods and logs are made up.

@Suite("Recent foods per meal")
struct RecentFoodsTests {
    /// A fixed "now" in 2030.
    let now = Date(timeIntervalSince1970: 1_900_000_000)

    func daysAgo(_ days: Double, hours: Double = 0) -> Date {
        now.addingTimeInterval(-(days * 86_400 + hours * 3_600))
    }

    /// Usage built the way the food library builds it: one `record` per eaten entry.
    func usage(_ logs: [(food: String, meal: String, daysAgo: Double)]) -> [FoodRef: FoodUsage] {
        var result: [FoodRef: FoodUsage] = [:]
        for log in logs {
            let ref = FoodRef(log.food)
            var use = result[ref] ?? FoodUsage()
            use.record(meal: log.meal, at: daysAgo(log.daysAgo), amount: 100)
            result[ref] = use
        }
        return result
    }

    // MARK: Recording

    @Test func recordingCountsPerMealInAnyOrder() {
        var use = FoodUsage()
        use.record(meal: "breakfast", at: daysAgo(1), amount: 150)
        use.record(meal: "breakfast", at: daysAgo(5), amount: 80)
        use.record(meal: "snack", at: daysAgo(3), amount: 40)
        #expect(use.count == 3)
        #expect(use.lastUsed == daysAgo(1))
        // The newest entry's amount, though an older one was counted after it.
        #expect(use.lastAmount == 150)
        #expect(use.meals["breakfast"] == FoodMealUse(count: 2, lastUsed: daysAgo(1)))
        #expect(use.meals["snack"] == FoodMealUse(count: 1, lastUsed: daysAgo(3)))
        #expect(abs(use.share(at: "breakfast") - 2.0 / 3.0) < 1e-9)
        #expect(use.share(at: "dinner") == 0)
        #expect(FoodUsage().share(at: "breakfast") == 0)
    }

    @Test func entriesWithoutAMealCountOnlyOverall() {
        var use = FoodUsage()
        use.record(meal: "", at: daysAgo(2), amount: 30)
        #expect(use.count == 1)
        #expect(use.meals.isEmpty)
        #expect(use.lastAmount == 30)
    }

    @Test func equalTimesLetTheLastCountedWin() {
        var use = FoodUsage()
        use.record(meal: "lunch", at: daysAgo(1), amount: 100)
        use.record(meal: "lunch", at: daysAgo(1), amount: 120)
        #expect(use.lastAmount == 120)
    }

    // MARK: Mostly at a meal

    @Test func mostlyAtNeedsTwoFreshLogsAndAFairShare() {
        let table = usage([
            ("oats", "breakfast", 1), ("oats", "breakfast", 2), ("oats", "breakfast", 3),
            ("once", "breakfast", 1),
            ("oil", "dinner", 1), ("oil", "dinner", 2), ("oil", "dinner", 3), ("oil", "dinner", 4),
            ("oil", "dinner", 5), ("oil", "dinner", 6), ("oil", "breakfast", 7), ("oil", "breakfast", 8),
            ("coffee", "breakfast", 1), ("coffee", "breakfast", 2), ("coffee", "breakfast", 3),
            ("coffee", "snack", 1), ("coffee", "snack", 2),
            ("old", "breakfast", 61), ("old", "breakfast", 70), ("old", "breakfast", 80),
        ])
        #expect(RecentFoods.isMostlyAt("breakfast", table[FoodRef("oats")]!, now: now))
        // Once is no habit.
        #expect(!RecentFoods.isMostlyAt("breakfast", table[FoodRef("once")]!, now: now))
        // 2 of 8 at breakfast (25 %): a dinner food.
        #expect(!RecentFoods.isMostlyAt("breakfast", table[FoodRef("oil")]!, now: now))
        #expect(RecentFoods.isMostlyAt("dinner", table[FoodRef("oil")]!, now: now))
        // 3 of 5 at breakfast and 2 of 5 (40 %) as a snack: both.
        #expect(RecentFoods.isMostlyAt("breakfast", table[FoodRef("coffee")]!, now: now))
        #expect(RecentFoods.isMostlyAt("snack", table[FoodRef("coffee")]!, now: now))
        // Last at breakfast 61 days ago: an old habit.
        #expect(!RecentFoods.isMostlyAt("breakfast", table[FoodRef("old")]!, now: now))
        // No meal: nothing leads.
        #expect(!RecentFoods.isMostlyAt("", table[FoodRef("oats")]!, now: now))
    }

    @Test func freshnessCountsTheMealNotTheFood() {
        // Logged yesterday as a snack, but at breakfast only 65 days ago.
        let table = usage([("toast", "breakfast", 65), ("toast", "breakfast", 66), ("toast", "breakfast", 67),
                           ("toast", "snack", 1)])
        let toast = table[FoodRef("toast")]!
        #expect(!RecentFoods.isMostlyAt("breakfast", toast, now: now))
        #expect(toast.lastUsed == daysAgo(1))
    }

    @Test func sixtyDaysIsStillFresh() {
        let table = usage([("muesli", "breakfast", 60), ("muesli", "breakfast", 90)])
        #expect(RecentFoods.isMostlyAt("breakfast", table[FoodRef("muesli")]!, now: now))
    }

    // MARK: The split

    @Test func breakfastFoodsLeadThenTheRestByRecency() {
        let table = usage([
            ("eggs", "breakfast", 1), ("eggs", "breakfast", 3),
            ("oats", "breakfast", 2), ("oats", "breakfast", 4), ("oats", "breakfast", 6), ("oats", "breakfast", 8),
            ("rice", "dinner", 0.5),
            ("apple", "snack", 0.2),
            ("salad", "lunch", 1), ("salad", "lunch", 3),
        ])
        let split = RecentFoods.split(table, meal: "breakfast", now: now)
        // Oats 4× before eggs 2×.
        #expect(split.forMeal == [FoodRef("oats"), FoodRef("eggs")])
        // The rest, the most recent first.
        #expect(split.others == [FoodRef("apple"), FoodRef("rice"), FoodRef("salad")])
        #expect(split.all.count == 5)

        let lunch = RecentFoods.split(table, meal: "lunch", now: now)
        #expect(lunch.forMeal == [FoodRef("salad")])
        #expect(lunch.others == [FoodRef("apple"), FoodRef("rice"), FoodRef("eggs"), FoodRef("oats")])
    }

    @Test func equalCountsGoByTheLatestAtTheMeal() {
        let table = usage([("tea", "breakfast", 5), ("tea", "breakfast", 6),
                           ("jam", "breakfast", 1), ("jam", "breakfast", 9)])
        #expect(RecentFoods.split(table, meal: "breakfast", now: now).forMeal == [FoodRef("jam"), FoodRef("tea")])
    }

    @Test func withoutAMealItIsTheOldRecencyOrder() {
        let table = usage([("oats", "breakfast", 3), ("oats", "breakfast", 4),
                           ("rice", "dinner", 1), ("apple", "snack", 2)])
        let split = RecentFoods.split(table, meal: "", now: now)
        #expect(split.forMeal.isEmpty)
        #expect(split.others == [FoodRef("rice"), FoodRef("apple"), FoodRef("oats")])
    }

    @Test func aMealNobodyLogsToLeavesTheOrderAlone() {
        let table = usage([("oats", "breakfast", 3), ("oats", "breakfast", 4), ("rice", "dinner", 1)])
        let split = RecentFoods.split(table, meal: "meal-1a2b3c4d", now: now)
        #expect(split.forMeal.isEmpty)
        #expect(split.others == [FoodRef("rice"), FoodRef("oats")])
    }

    @Test func limitsHoldAndOverflowGoesToTheRest() {
        var logs: [(food: String, meal: String, daysAgo: Double)] = []
        for index in 0..<15 {
            let food = "food" + (index < 10 ? "0" : "") + String(index)
            // food00 most often at breakfast … food14 least (but always at least twice).
            for repeat_ in 0..<(17 - index) {
                logs.append((food, "breakfast", Double(repeat_) + 1))
            }
        }
        logs.append(("rice", "dinner", 0.1))
        let table = usage(logs)
        let split = RecentFoods.split(table, meal: "breakfast", now: now, limit: 40)
        #expect(split.forMeal.count == RecentFoods.mealLimit)
        #expect(split.forMeal.first == FoodRef("food00"))
        #expect(split.forMeal.last == FoodRef("food11"))
        // The three that didn't fit come back in the rest, with the rice.
        #expect(Set(split.others) == [FoodRef("food12"), FoodRef("food13"), FoodRef("food14"), FoodRef("rice")])
        #expect(split.others.first == FoodRef("rice"))

        let small = RecentFoods.split(table, meal: "breakfast", now: now, limit: 5)
        #expect(small.forMeal.count == 5)
        #expect(small.others.isEmpty)
        #expect(RecentFoods.split(table, meal: "breakfast", now: now, limit: 0) == RecentFoods.Split())
        #expect(RecentFoods.split(table, meal: "breakfast", now: now, limit: 14).all.count == 14)
    }

    @Test func unavailableFoodsStayOut() {
        let table = usage([("oats", "breakfast", 1), ("oats", "breakfast", 2),
                           ("gone", "breakfast", 1), ("gone", "breakfast", 2), ("gone", "breakfast", 3),
                           ("rice", "dinner", 1)])
        let split = RecentFoods.split(table, meal: "breakfast", now: now) { $0 != FoodRef("gone") }
        #expect(split.forMeal == [FoodRef("oats")])
        #expect(split.others == [FoodRef("rice")])
    }

    @Test func savedMealsMoveToTheFrontForTheirMeal() {
        let table = usage([("recipe:bowl", "breakfast", 1), ("recipe:bowl", "breakfast", 2),
                           ("recipe:chili", "dinner", 1), ("recipe:chili", "dinner", 2), ("recipe:chili", "dinner", 3)])
        let refs = [FoodRef("recipe:chili"), FoodRef("recipe:salad"), FoodRef("recipe:bowl")]
        #expect(RecentFoods.sortedForMeal(refs, usage: table, meal: "breakfast", now: now)
                == [FoodRef("recipe:bowl"), FoodRef("recipe:chili"), FoodRef("recipe:salad")])
        #expect(RecentFoods.sortedForMeal(refs, usage: table, meal: "dinner", now: now) == refs)
        #expect(RecentFoods.sortedForMeal(refs, usage: table, meal: "", now: now) == refs)
    }

    // MARK: The hint

    @Test func hintReadsNaturally() {
        #expect(RecentFoods.hint(for: .breakfast) == "Mostly at breakfast")
        #expect(RecentFoods.hint(for: .lunch) == "Mostly at lunch")
        #expect(RecentFoods.hint(for: .dinner) == "Mostly at dinner")
        #expect(RecentFoods.hint(for: .snack) == "Mostly as a snack")
        // Own and renamed meals keep their names as typed.
        #expect(RecentFoods.hint(for: MealSlot(id: "meal-1a2b3c4d", name: "Second Breakfast", emoji: "🥨", minutes: 600))
                == "Mostly at Second Breakfast")
        #expect(RecentFoods.hint(for: MealSlot(id: "breakfast", name: "Frühstück", emoji: "🥐", minutes: 450))
                == "Mostly at Frühstück")
        #expect(RecentFoods.hint(for: MealSlot(id: "meal-x", name: "  ", emoji: "🍽️", minutes: 600)) == "Mostly at this meal")
    }
}
