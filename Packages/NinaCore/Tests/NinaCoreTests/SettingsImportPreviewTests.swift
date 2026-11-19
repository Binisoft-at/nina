import Foundation
import Testing
@testable import NinaCore

// A file with exactly the keys of a real coach plan an AI wrote (gain then cut, gym/tennis/rest,
// creatine, protein per meal, notes) – every number and date is made up.

private var previewUTC: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

@Suite("Settings import: the preview of a whole plan")
struct SettingsImportPreviewTests {
    static let file = """
    setting,value
    weight_kg,74.2
    activity,moderate
    goal,gain
    rate_kg_per_week,0.15-0.25
    target_weight_kg,77
    macro_split,25/50/25
    calories,2600
    protein_g,150
    carbs_g,335
    fat_g,75
    fiber_g,28
    water_ml,2400
    focus_nutrients,protein;carbs;fat;fiber
    body_fat_percent,18
    body_fat_method,estimate
    long_term.weight_kg,76
    long_term.body_fat_percent,13
    long_term.note,Stronger and leaner
    day_type.gym.name,Gym
    day_type.gym.days,mon;wed;fri
    day_type.gym.workouts,strength
    day_type.tennis.name,Tennis
    day_type.tennis.days,flexible
    day_type.tennis.per_week,2
    day_type.tennis.workouts,tennis
    day_type.rest.name,Rest
    day_type.rest.days,default
    phase.1.name,Strength block
    phase.1.goal,gain
    phase.1.start,2030-02-04
    phase.1.end,~2030-05-31
    phase.1.rate_kg_per_week,0.15-0.25
    phase.1.review_weight_kg,76-77
    phase.1.target_weight_kg,77
    phase.1.gym.calories,2600
    phase.1.gym.macros_g,150/335/75
    phase.1.tennis.calories,2850
    phase.1.tennis.macros_g,150/380/78
    phase.1.rest.calories,2400
    phase.1.rest.macros_g,150/290/75
    phase.2.name,Lean out
    phase.2.goal,lose
    phase.2.start,~2030-06
    phase.2.end,~2030-08
    phase.2.target_weight_kg,74
    phase.2.target_body_fat_percent,13
    checkin.day,sun
    checkin.adjust_after_weeks,2-3
    checkin.step_kcal,100-150
    measure.weigh_in,daily 07:00
    measure.weekly,waist
    measure.full,waist;chest;arm;thigh;hip
    measure.full_every_weeks,8
    measure.body_fat_every_weeks,8
    check.creatine.name,Creatine monohydrate
    check.creatine.dose,3-5 g
    check.creatine.when,breakfast
    check.creatine.optional,yes
    meal_protein_g,35-45
    protein_meals,4
    note,An extra gym session on a tennis week counts as a gym day.
    note,Keep training hard and recover well.
    note,The lean-out start depends on progress.
    """

    static let today = DayKey(year: 2030, month: 2, day: 4)

    static func result(to state: SettingsState = SettingsState()) -> (draft: SettingsDraft, result: SettingsResult) {
        let draft = SettingsCSV.parse(file)
        let now = today.date(minutes: 8 * 60, calendar: previewUTC)
        return (draft, SettingsCSV.apply(draft, to: state, year: 2030, today: today, now: now, calendar: previewUTC))
    }

    @Test func everyPlanRowHasAHome() {
        let (draft, result) = Self.result()
        #expect(draft.skipped.isEmpty, "\(draft.skipped)")
        #expect(draft.wishes.isEmpty)
        #expect(result.wishes.isEmpty)
        #expect(result.notes.isEmpty, "\(result.notes)")
        #expect(!result.sections.contains { $0.group == .notSupported })
        #expect(result.hasChanges)
    }

    @Test func groupsInPreviewOrder() {
        let sections = Self.result().result.sections
        #expect(sections.map(\.group) == [.body, .targets, .dayTypes, .phases, .checks, .measuring, .checkIn, .longTerm, .notes, .preferences])
        #expect(sections.map(\.title).contains("Day types (3)"))
        #expect(sections.map(\.title).contains("Phases (2)"))
        #expect(sections.map(\.title).contains("Daily checks (1)"))
        let notes = sections.first { $0.group == .notes }
        #expect(notes?.changes.count == 3)
        // Rows that match the defaults add no line: with a Monday check-in there is no Check-in group.
        let monday = SettingsCSV.apply(SettingsCSV.parse(Self.file.replacingOccurrences(of: "checkin.day,sun", with: "checkin.day,mon")),
                                       to: SettingsState(), year: 2030, today: Self.today,
                                       now: Self.today.date(minutes: 8 * 60, calendar: previewUTC), calendar: previewUTC)
        #expect(!monday.sections.contains { $0.group == .checkIn })
    }

    @Test func bodyRecordsCanBeUnticked() throws {
        let result = Self.result().result
        #expect(result.bodyRecords.map(\.kind) == [.assessment])
        let body = try #require(result.sections.first { $0.group == .body })
        let fat = try #require(body.changes.first { $0.key == BodyValues.bodyFatKey })
        #expect(fat.new.hasPrefix("18 %"))
        #expect(result.newWeight == 74.2)
        let without = result.removingBodyValues([BodyValues.bodyFatKey])
        #expect(without.bodyRecords.isEmpty)
        #expect(!without.changes.contains { $0.key == BodyValues.bodyFatKey })
        // The plan and the weight still make it an import.
        #expect(without.hasChanges)
        #expect(without.plan?.isSetUp == true)
    }

    @Test func importingAgainChangesNothing() throws {
        let first = Self.result().result
        var state = first.state
        state.weightKg = first.newWeight ?? state.weightKg
        let again = Self.result(to: state).result
        #expect(again.changes.filter { $0.group != .body }.isEmpty, "\(again.changes.map(\.title))")
        #expect(again.newWeight == nil)
    }
}
