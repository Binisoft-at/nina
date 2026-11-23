import Foundation
import Testing
@testable import NinaCore

// The "Set your goal" card on Today: when it applies, and "Not now" (7 days) / "Don't show again"
// (for good), stored as text on the device. All numbers are made up.

@Suite("Set your goal card")
struct GoalSetupPromptTests {
    let own = DailyTargets(energy: 2_350, protein: 150, carbs: 260, fat: 75)

    @Test func newPeopleSeeItWithTheStartingTargets() {
        #expect(GoalSetupPrompt.reason(planIsSetUp: false, targets: .standard, trainingTargets: nil, hasBody: false) == .standardTargets)
        // Body data alone sets no goal: the targets are still the starting ones.
        #expect(GoalSetupPrompt.reason(planIsSetUp: false, targets: .standard, trainingTargets: nil, hasBody: true) == .standardTargets)
    }

    @Test func ownTargetsWithoutBodyDataStillAsk() {
        #expect(GoalSetupPrompt.reason(planIsSetUp: false, targets: own, trainingTargets: nil, hasBody: false) == .missingBody)
        #expect(GoalSetupPrompt.reason(planIsSetUp: false, targets: own, trainingTargets: nil, hasBody: true) == nil)
    }

    @Test func trainingDayTargetsAreAGoal() {
        let training = DailyTargets(energy: 2_300, protein: 125, carbs: 260, fat: 67)
        #expect(GoalSetupPrompt.reason(planIsSetUp: false, targets: .standard, trainingTargets: training, hasBody: true) == nil)
        #expect(GoalSetupPrompt.reason(planIsSetUp: false, targets: .standard, trainingTargets: training, hasBody: false) == .missingBody)
    }

    @Test func aSetUpPlanNeverShowsIt() {
        #expect(GoalSetupPrompt.reason(planIsSetUp: true, targets: .standard, trainingTargets: nil, hasBody: false) == nil)
        #expect(GoalSetupPrompt.reason(planIsSetUp: true, targets: own, trainingTargets: nil, hasBody: false) == nil)
    }

    @Test func onlyCaloriesAndMacrosDecideWhatIsStandard() {
        var water = DailyTargets.standard
        water.water = 3_000
        water.fiber = 35
        #expect(GoalSetupPrompt.isStandard(water))
        // Stored as text and read back: still the starting values.
        #expect(GoalSetupPrompt.isStandard(DailyTargets(encoded: DailyTargets.standard.encoded)))
        #expect(GoalSetupPrompt.isStandard(DailyTargets(encoded: "")))
        var energy = DailyTargets.standard
        energy.energy = 2_100
        #expect(!GoalSetupPrompt.isStandard(energy))
        var protein = DailyTargets.standard
        protein.protein = 140
        #expect(!GoalSetupPrompt.isStandard(protein))
        #expect(!GoalSetupPrompt.isStandard(own))
    }

    @Test func notNowHidesItForSevenDays() {
        let today = DayKey(year: 2030, month: 3, day: 4)
        let dismissal = GoalSetupPrompt.Dismissal.notNow(today: today)
        #expect(dismissal == .until(DayKey(year: 2030, month: 3, day: 11)))
        #expect(dismissal.hides(on: today))
        #expect(dismissal.hides(on: today.adding(days: 6)))
        #expect(!dismissal.hides(on: today.adding(days: 7)))
        #expect(!GoalSetupPrompt.isVisible(.standardTargets, dismissal: dismissal, today: today.adding(days: 3)))
        #expect(GoalSetupPrompt.isVisible(.standardTargets, dismissal: dismissal, today: today.adding(days: 7)))
    }

    @Test func dontShowAgainIsForGood() {
        let today = DayKey(year: 2030, month: 3, day: 4)
        #expect(GoalSetupPrompt.Dismissal.forever.hides(on: today.adding(days: 900)))
        #expect(!GoalSetupPrompt.isVisible(.missingBody, dismissal: .forever, today: today))
    }

    @Test func itShowsOnlyWhenItApplies() {
        let today = DayKey(year: 2030, month: 3, day: 4)
        #expect(GoalSetupPrompt.isVisible(.standardTargets, dismissal: .none, today: today))
        #expect(!GoalSetupPrompt.isVisible(nil, dismissal: .none, today: today))
    }

    @Test func storedTextRoundTrips() {
        let day = DayKey(year: 2030, month: 3, day: 11)
        let cases: [GoalSetupPrompt.Dismissal] = [.none, .until(day), .forever]
        for dismissal in cases {
            #expect(GoalSetupPrompt.Dismissal(stored: dismissal.stored) == dismissal)
        }
        #expect(GoalSetupPrompt.Dismissal.forever.stored == "never")
        #expect(GoalSetupPrompt.Dismissal.until(day).stored == "2030-03-11")
        #expect(GoalSetupPrompt.Dismissal.none.stored == "")
        // Anything unreadable counts as nothing chosen.
        #expect(GoalSetupPrompt.Dismissal(stored: "soon") == .none)
        #expect(GoalSetupPrompt.Dismissal(stored: " never\n") == .forever)
    }
}
