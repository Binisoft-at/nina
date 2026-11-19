import Foundation
import Testing
@testable import NinaCore

// Made-up: 80 kg, 35–45 g per protein meal, 4 protein meals a day.

private let proteinDayKey = DayKey(year: 2030, month: 1, day: 7)

private func proteinEntry(_ meal: String, _ protein: Double, _ status: EntryStatus = .eaten,
                          day: DayKey = proteinDayKey) -> EntryFacts {
    EntryFacts(day: day, meal: meal, status: status, nutrients: NutrientValues([.energy: protein * 8, .protein: protein]),
               name: meal, time: Date(timeIntervalSince1970: 1_894_000_000))
}

@Suite("Protein meals")
struct ProteinMealsTests {
    static let slots = ["breakfast", "lunch", "snack", "dinner"]
    static let plan = CoachPlan.Protein(mealMin: 35, mealMax: 45, count: 4, meals: ["breakfast", "lunch", "snack", "dinner"])

    @Test func ruleFromThePlan() {
        let rule = ProteinMeals.Rule(protein: Self.plan, weightKg: 80, mealSlots: Self.slots + ["jause"])
        #expect(rule.minimum == 35)
        #expect(rule.maximum == 45)
        #expect(rule.meals == Self.slots)
        #expect(rule.count == 4)
        #expect(rule.isActive)
        #expect(!rule.counts("jause"))

        // No minimum set: 0.4 g/kg of the 7-day average, at most 0.55 g/kg, every meal slot counts.
        let derived = ProteinMeals.Rule(protein: CoachPlan.Protein(), weightKg: 80, mealSlots: Self.slots + ["jause"])
        #expect(derived.minimum == 32)
        #expect(derived.maximum == 44)
        #expect(derived.meals.count == 5)
        #expect(derived.count == 5)
        // A count of 3 out of the listed meals.
        let three = ProteinMeals.Rule(protein: CoachPlan.Protein(count: 3), weightKg: 80, mealSlots: Self.slots)
        #expect(three.count == 3)
        #expect(three.meals == Self.slots)

        // Without a minimum and without a weight there is nothing to compare with.
        let off = ProteinMeals.Rule(protein: CoachPlan.Protein(), weightKg: 0, mealSlots: Self.slots)
        #expect(!off.isActive)
        let day = ProteinMeals.day(proteinDayKey, entries: [proteinEntry("lunch", 50)], rule: off)
        #expect(day.meals.isEmpty)
        #expect(day.target == 0)
        #expect(!day.isEnough)
    }

    @Test func mealsFromEntries() {
        let rule = ProteinMeals.Rule(protein: Self.plan, weightKg: 80, mealSlots: Self.slots)
        let entries = [
            proteinEntry("breakfast", 20), proteinEntry("breakfast", 15),
            proteinEntry("lunch", 22), proteinEntry("lunch", 10, .planned), proteinEntry("lunch", 30, .skipped),
            proteinEntry("dinner", 50),
            proteinEntry("jause", 40), // not a counted meal
            proteinEntry("snack", 60, day: DayKey(year: 2030, month: 1, day: 8)), // another day
        ]
        let day = ProteinMeals.day(proteinDayKey, entries: entries, rule: rule)
        #expect(day.meals.map(\.id) == Self.slots)

        let breakfast = day.meal("breakfast")
        #expect(breakfast?.eaten == 35)
        #expect(breakfast?.fill == .reached)
        #expect(breakfast?.isProteinMeal == true)
        #expect(breakfast?.missing == 0)

        let lunch = day.meal("lunch")
        #expect(lunch?.eaten == 22)
        #expect(lunch?.planned == 10)
        #expect(lunch?.total == 32)
        #expect(lunch?.fill == .below)
        #expect(lunch?.isProteinMeal == false)
        #expect(lunch?.missing == 3)

        let snack = day.meal("snack")
        #expect(snack?.total == 0)
        #expect(snack?.missing == 35)

        let dinner = day.meal("dinner")
        #expect(dinner?.fill == .above)
        #expect(dinner?.isProteinMeal == true)
        #expect(day.meal("jause") == nil)

        #expect(day.count == 2)
        #expect(day.target == 4)
        #expect(day.text == "2 of 4")
        #expect(!day.isEnough)

        // Planned food fills the pill but isn't a protein meal until it's eaten.
        let planned = ProteinMeals.day(proteinDayKey, entries: [proteinEntry("lunch", 40, .planned)], rule: rule)
        #expect(planned.meal("lunch")?.fill == .reached)
        #expect(planned.count == 0)

        // From the day's totals (eaten only).
        let totals = DayTotals(day: proteinDayKey, entries: entries)
        let fromTotals = ProteinMeals.day(totals, rule: rule)
        #expect(fromTotals.meal("lunch")?.total == 22)
        #expect(fromTotals.count == 2)
    }

    @Test func weekCountAndAdherence() {
        let rule = ProteinMeals.Rule(minimum: 35, meals: Self.slots, count: 4)
        func day(_ proteins: [Double]) -> ProteinMeals.Day {
            let entries = zip(Self.slots, proteins).map { proteinEntry($0.0, $0.1) }
            return ProteinMeals.day(proteinDayKey, entries: entries, rule: rule)
        }
        let four = day([40, 36, 35, 50])
        let three = day([40, 36, 20, 50])
        let two = day([40, 10, 20, 50])
        #expect(four.isEnough)
        #expect(three.isEnough) // at least count − 1
        #expect(!two.isEnough)

        // A fifth protein meal doesn't make up for a missing one on another day.
        let five = ProteinMeals.day(proteinDayKey, entries: [proteinEntry("breakfast", 40), proteinEntry("lunch", 40), proteinEntry("snack", 40),
                                                            proteinEntry("dinner", 40), proteinEntry("supper", 40)],
                                    rule: ProteinMeals.Rule(minimum: 35, meals: Self.slots + ["supper"], count: 4))
        #expect(five.count == 5)
        #expect(five.counted == 4)

        let week = ProteinMeals.period([four, three, two, five, four, three, four])
        #expect(week.days == 7)
        #expect(week.meals == 4 + 3 + 2 + 4 + 4 + 3 + 4)
        #expect(week.target == 28)
        #expect(week.text == "24 of 28")
        #expect(week.enoughDays == 6)
        #expect(abs(week.share - 24.0 / 28.0) < 1e-12)
        #expect(ProteinMeals.period([]).share == 0)
    }

    @Test func pillAndHint() {
        // Whole grams, as shown.
        #expect(ProteinMeals.fill(34.6, minimum: 35) == .reached)
        #expect(ProteinMeals.fill(34.4, minimum: 35) == .below)
        #expect(ProteinMeals.fill(45.4, minimum: 35, maximum: 45) == .reached)
        #expect(ProteinMeals.fill(46, minimum: 35, maximum: 45) == .above)
        #expect(ProteinMeals.fill(60, minimum: 35) == .reached)
        #expect(ProteinMeals.fill(60, minimum: 0) == .below)
        #expect(ProteinMeals.missing(34.4, minimum: 35) == 1)
        #expect(ProteinMeals.missing(17, minimum: 35) == 18)
        #expect(ProteinMeals.missing(36, minimum: 35) == 0)
        #expect(ProteinMeals.hint(17, minimum: 35) == "+18 g protein to reach 35")
        #expect(ProteinMeals.hint(17.2, minimum: 35) == "+18 g protein to reach 35")
        #expect(ProteinMeals.hint(35, minimum: 35) == nil)
        #expect(ProteinMeals.hint(10, minimum: 0) == nil)
    }

    @Test func gramsPerKilogram() {
        let ratio = ProteinMeals.ratio(grams: 160, weightKg: 80, bodyFat: 20)
        #expect(ratio?.perKg == 2)
        #expect(ratio?.perLeanKg == 2.5)
        #expect(ratio?.text == "2.0 g/kg · 2.5 g/kg lean mass")
        let plain = ProteinMeals.ratio(grams: 150, weightKg: 80)
        #expect(plain?.perLeanKg == nil)
        #expect(plain?.text == "1.9 g/kg")
        // A measured lean mass wins over the body-fat estimate.
        #expect(ProteinMeals.ratio(grams: 160, weightKg: 80, leanKg: 64, bodyFat: 30)?.perLeanKg == 2.5)
        #expect(ProteinMeals.ratio(grams: 160, weightKg: 0) == nil)
    }
}
