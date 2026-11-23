import Foundation
import Testing
@testable import NinaCore

@Suite("Meal notifications")
struct MealPromptRulesTests {
    let rule = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
    let day = DayKey(year: 2030, month: 3, day: 14)

    @Test func theRoutineIsReadFromThePlanKey() {
        let key = PlanSchedule.key(rule: rule, day: day)
        #expect(MealPromptRules.ruleID(planKey: key) == rule.uuidString)
        #expect(MealPromptRules.ruleID(planKey: "") == nil)
        #expect(MealPromptRules.ruleID(planKey: "rule::2030-03-14") == nil)
        #expect(MealPromptRules.ruleID(planKey: "copy:abc") == nil)
    }

    @Test func onlyActiveRoutinesThatAskPrompt() {
        let key = PlanSchedule.key(rule: rule, day: day)
        // Planned by hand: always asks.
        #expect(MealPromptRules.asks(planKey: "", asking: []))
        // A routine that is on with "Remind me".
        #expect(MealPromptRules.asks(planKey: key, asking: [rule.uuidString]))
        // Paused, deleted or without "Remind me": not in `asking`.
        #expect(!MealPromptRules.asks(planKey: key, asking: []))
        #expect(!MealPromptRules.asks(planKey: key, asking: ["another"]))
        #expect(!MealPromptRules.asks(planKey: "rule:", asking: [rule.uuidString]))
    }

    @Test func aPlannedOrEatenMealGetsNoReminder() {
        #expect(MealPromptRules.remindsAbout(meal: "lunch", eaten: [], prompted: []))
        #expect(!MealPromptRules.remindsAbout(meal: "lunch", eaten: ["lunch"], prompted: []))
        #expect(!MealPromptRules.remindsAbout(meal: "lunch", eaten: [], prompted: ["lunch"]))
        #expect(MealPromptRules.remindsAbout(meal: "dinner", eaten: ["lunch"], prompted: ["breakfast"]))
    }
}
