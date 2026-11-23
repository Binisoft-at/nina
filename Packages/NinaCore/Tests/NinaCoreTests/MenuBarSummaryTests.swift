import Foundation
import Testing
@testable import NinaCore

/// The Mac's menu bar extra: calories left or over, protein and water of the diary day. Made-up
/// numbers; on Linux `DisplayNumber` groups with ",".
@Suite("Menu bar summary")
struct MenuBarSummaryTests {
    static let day = DayKey(year: 2030, month: 3, day: 4)
    static let noon = Date(timeIntervalSince1970: 1_900_000_000)
    static let targets = DailyTargets(energy: 2400, protein: 150, carbs: 280, fat: 75, water: 2500)

    static func entry(_ kcal: Double, protein: Double = 0, status: EntryStatus = .eaten) -> EntryFacts {
        EntryFacts(day: day, meal: "lunch", status: status, nutrients: NutrientValues([.energy: kcal, .protein: protein]),
                   name: "Made-up meal", time: noon)
    }

    static func summary(_ entries: [EntryFacts], water: Double = 0, targets: DailyTargets = targets,
                        bonus: Double = 0, emoji: String? = nil) -> NinaMenuBarSummary {
        let totals = DayTotals(day: day, entries: entries, water: water)
        return NinaMenuBarSummary(progress: DayProgress(totals: totals, targets: targets, activityBonus: bonus), emoji: emoji)
    }

    @Test func leftWithProteinAndWater() {
        let summary = Self.summary([Self.entry(700, protein: 45.4), Self.entry(466, protein: 40)], water: 750)
        #expect(summary.energyLeft == 1234)
        #expect(!summary.isOver)
        #expect(summary.title == "1,234 left")
        #expect(summary.energyLine == "1,234 kcal left today")
        #expect(summary.proteinLine == "Protein 85 of 150 g")
        #expect(summary.waterLine == "Water 750 of 2,500 ml")
        #expect(summary.accessibilityLabel(appName: "Nina") == "Nina, 1,234 kcal left today")
    }

    @Test func overTheTarget() {
        let summary = Self.summary([Self.entry(2550)])
        #expect(summary.isOver)
        #expect(summary.title == "150 over")
        #expect(summary.energyLine == "150 kcal over today")
    }

    @Test func plannedAndSkippedFoodDoNotCount() {
        let summary = Self.summary([Self.entry(400), Self.entry(900, protein: 60, status: .planned),
                                    Self.entry(300, status: .skipped)])
        #expect(summary.energyLeft == 2000)
        #expect(summary.protein == 0)
    }

    @Test func aFractionOverIsStillZeroLeft() {
        // 2,400.4 eaten rounds to 0 left, not "0 over".
        let summary = Self.summary([Self.entry(2400.4)])
        #expect(!summary.isOver)
        #expect(summary.title == "0 left")
    }

    @Test func dayTypeEmojiGoesInFrontOfTheMenuLineOnly() {
        let summary = Self.summary([Self.entry(1200)], emoji: " 🎾 ")
        #expect(summary.emoji == "🎾")
        #expect(summary.energyLine == "🎾 1,200 kcal left today")
        #expect(summary.title == "1,200 left")
        #expect(summary.accessibilityLabel(appName: "Nina") == "Nina, 1,200 kcal left today")
        #expect(Self.summary([], emoji: "").emoji == nil)
    }

    @Test func activityBonusRaisesTheBudget() {
        let summary = Self.summary([Self.entry(2400)], bonus: 200)
        #expect(summary.energyTarget == 2600)
        #expect(summary.title == "200 left")
    }

    @Test func withoutTargetsItSaysWhatWasEaten() {
        let none = DailyTargets(energy: 0, protein: 0, carbs: 0, fat: 0, water: 0)
        let summary = Self.summary([Self.entry(1234, protein: 30)], water: 500, targets: none)
        #expect(!summary.hasEnergyTarget)
        #expect(!summary.isOver)
        #expect(summary.title == "1,234 kcal")
        #expect(summary.energyLine == "1,234 kcal eaten today")
        #expect(summary.proteinLine == "Protein 30 g")
        #expect(summary.waterLine == "Water 500 ml")
        #expect(Self.summary([], targets: none).title == "0 kcal")
    }

    @Test func brokenNumbersShowNothingStrange() {
        // A broken bonus makes the budget infinite: the title stays a plain number.
        let summary = Self.summary([Self.entry(500)], bonus: .infinity)
        #expect(summary.energyLeft == 0)
        #expect(summary.title == "0 left")
    }
}
