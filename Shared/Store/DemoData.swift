import Foundation
import SwiftData
import NinaCore

/// Sample data. It lives only in separate in-memory stores (`-Demo` launches for screenshots, the
/// tour's practice day) and never syncs. Food values are per 100 g from the bundled catalog's
/// sources; everything about the person (weights, tape, body fat, targets, plan) is made up.
@MainActor
enum DemoData {
    struct DemoFood {
        let ref: String
        let name: String
        let category: FoodCategory
        let unit: BaseUnit
        let per100: NutrientValues
        let portion: (label: String, amount: Double)?
    }

    /// One line of the demo diary: the seed inserts it as a `LogEntry`, the demo check-ins add it up.
    struct Line {
        let name: String
        let amount: Double?
        let count: Double?
        let day: DayKey
        let meal: String
        let minutes: Int
        let status: EntryStatus
    }

    static let foods: [String: DemoFood] = {
        func n(_ kcal: Double, _ protein: Double, _ carbs: Double, _ fat: Double, fiber: Double = 0, sugar: Double = 0) -> NutrientValues {
            NutrientValues([.energy: kcal, .protein: protein, .carbs: carbs, .fat: fat, .fiber: fiber, .sugar: sugar])
        }
        let list = [
            DemoFood(ref: "usda:20038", name: "Oats", category: .cereals, unit: .gram, per100: n(389, 16.9, 66.3, 6.9, fiber: 10.6, sugar: 0), portion: nil),
            DemoFood(ref: "nina:milch-1-5", name: "Milk 2%", category: .dairy, unit: .milliliter, per100: n(51, 3.4, 4.9, 2.0, sugar: 5.2), portion: ("glass", 250)),
            DemoFood(ref: "usda:09040", name: "Banana", category: .fruit, unit: .gram, per100: n(89, 1.1, 22.8, 0.3, fiber: 2.6, sugar: 12.2), portion: ("medium", 118)),
            DemoFood(ref: "usda:09003", name: "Apple", category: .fruit, unit: .gram, per100: n(52, 0.3, 13.8, 0.2, fiber: 2.4, sugar: 10.4), portion: ("medium", 182)),
            DemoFood(ref: "usda:05064", name: "Chicken breast, roasted", category: .poultry, unit: .gram, per100: n(165, 31, 0, 3.6), portion: nil),
            DemoFood(ref: "usda:20445", name: "White rice, cooked", category: .grains, unit: .gram, per100: n(130, 2.7, 28.2, 0.3, fiber: 0.4), portion: nil),
            DemoFood(ref: "usda:11252", name: "Lettuce", category: .vegetables, unit: .gram, per100: n(15, 1.4, 2.9, 0.2, fiber: 1.3, sugar: 0.8), portion: nil),
            DemoFood(ref: "usda:04053", name: "Olive oil", category: .fats, unit: .gram, per100: n(884, 0, 0, 100), portion: ("tbsp", 13.5)),
            DemoFood(ref: "nina:skyr", name: "Skyr, plain", category: .dairy, unit: .gram, per100: n(63, 11, 4, 0.2, sugar: 4), portion: ("pot", 150)),
            DemoFood(ref: "usda:20421", name: "Spaghetti, cooked", category: .grains, unit: .gram, per100: n(158, 5.8, 30.9, 0.9, fiber: 1.8, sugar: 0.6), portion: nil),
            DemoFood(ref: "usda:11529", name: "Tomato", category: .vegetables, unit: .gram, per100: n(18, 0.9, 3.9, 0.2, fiber: 1.2, sugar: 2.6), portion: ("medium", 123)),
            DemoFood(ref: "usda:01123", name: "Egg", category: .eggs, unit: .gram, per100: n(143, 12.6, 0.7, 9.5), portion: ("large", 50)),
            DemoFood(ref: "nina:roggenvollkornbrot", name: "Whole-grain bread", category: .bread, unit: .gram, per100: n(220, 8, 38, 2.5, fiber: 7.5, sugar: 3), portion: ("slice", 45)),
            DemoFood(ref: "usda:12061", name: "Almonds", category: .nuts, unit: .gram, per100: n(579, 21.2, 21.6, 49.9, fiber: 12.5, sugar: 4.4), portion: ("handful", 28)),
            DemoFood(ref: "usda:15237", name: "Salmon, baked", category: .fish, unit: .gram, per100: n(206, 22.1, 0, 12.4), portion: ("fillet", 154)),
            DemoFood(ref: "usda:11367", name: "Potatoes, boiled", category: .vegetables, unit: .gram, per100: n(87, 1.9, 20.1, 0.1, fiber: 1.8, sugar: 0.9), portion: nil),
            DemoFood(ref: "usda:19904", name: "Dark chocolate 70%", category: .sweets, unit: .gram, per100: n(598, 7.8, 45.9, 42.6, fiber: 10.9, sugar: 24), portion: ("square", 10)),
            DemoFood(ref: "usda:14209", name: "Coffee", category: .beverages, unit: .milliliter, per100: n(1, 0.1, 0, 0), portion: ("mug", 250)),
        ]
        var map: [String: DemoFood] = [:]
        for food in list { map[food.name] = food }
        return map
    }()

    /// Grams (or ml) of a demo line: `count` portions when the food has a portion, else `amount`.
    static func grams(of food: DemoFood, amount: Double?, count: Double?) -> Double {
        if let count, let portion = food.portion { return count * portion.amount }
        return amount ?? 100
    }

    /// A demo line as the diary's totals read it (nil for a food the demo doesn't know).
    static func facts(_ line: Line) -> EntryFacts? {
        guard let food = foods[line.name] else { return nil }
        let nutrients = food.per100.scaled(by: grams(of: food, amount: line.amount, count: line.count) / 100)
        return EntryFacts(day: line.day, meal: line.meal, status: line.status, nutrients: nutrients, name: food.name,
                          time: line.day.date(minutes: line.minutes))
    }

    @discardableResult
    static func add(_ name: String, amount: Double? = nil, count: Double? = nil, day: DayKey, meal: String, minutes: Int,
                    status: EntryStatus = .eaten, context: ModelContext) -> LogEntry? {
        add(Line(name: name, amount: amount, count: count, day: day, meal: meal, minutes: minutes, status: status), context: context)
    }

    @discardableResult
    static func add(_ line: Line, context: ModelContext) -> LogEntry? {
        guard let food = foods[line.name] else { return nil }
        let entry = LogEntry(day: line.day, time: line.day.date(minutes: line.minutes), meal: line.meal, name: food.name)
        entry.foodRef = food.ref
        entry.category = food.category.rawValue
        entry.baseUnit = food.unit.rawValue
        if let count = line.count, let portion = food.portion {
            entry.quantity = count
            entry.unitLabel = portion.label
            entry.unitAmount = portion.amount
        } else {
            entry.quantity = line.amount ?? 100
            entry.unitLabel = food.unit.symbol
            entry.unitAmount = 1
        }
        entry.nutrients = food.per100.scaled(by: grams(of: food, amount: line.amount, count: line.count) / 100).encoded
        entry.status = line.status.rawValue
        entry.source = "demo"
        context.insert(entry)
        return entry
    }

    // MARK: - -Demo launches

    /// `-Demo` launches: six weeks for screenshots. A coach plan (maintenance done, a lean gain in
    /// its fourth week, a fat-loss phase planned) with gym, tennis and rest days, morning
    /// weigh-ins, tape and body-fat records, daily checks and two saved check-ins. Today is half
    /// logged with dinner planned; it is the check-in day, so Today shows the check-in card.
    static func seed(_ context: ModelContext) {
        let today = DayKey.today()
        let coach = DemoCoach(today: today)

        let profile = NinaProfile()
        profile.targets = DemoCoach.rest.encoded
        profile.sex = Sex.female.rawValue
        profile.birthYear = 1991
        profile.heightCm = 171
        profile.activity = ActivityLevel.moderate.rawValue
        profile.focusNutrients = "protein,carbs,fat,fiber"
        write(coach.plan, to: profile, on: today)
        context.insert(profile)

        let lines = diary(coach)
        for line in lines { add(line, context: context) }
        let drinks = coach.drinks
        for drink in drinks {
            context.insert(WaterLog(day: drink.day, time: drink.day.date(minutes: drink.minutes), amount: drink.amount))
        }
        insertBody(coach, context: context)
        insertMarks(coach, totals: DemoCoach.totals(lines.compactMap { facts($0) }, drinks: drinks), context: context)
        insertLibrary(context)
    }

    /// The demo diary: the same kind of meals every day, sized to the day type (a little more on
    /// gym and tennis days), a few days without a log and none on the holiday; today half logged
    /// with dinner planned.
    static func diary(_ coach: DemoCoach) -> [Line] {
        var lines: [Line] = []
        func eat(_ name: String, amount: Double? = nil, count: Double? = nil, _ day: DayKey, _ meal: String, _ minutes: Int,
                 _ status: EntryStatus = .eaten) {
            lines.append(Line(name: name, amount: amount, count: count, day: day, meal: meal, minutes: minutes, status: status))
        }
        for offset in (1...DemoCoach.history).reversed() where coach.isLogged(offset) {
            let day = coach.day(offset)
            let type = coach.typeID(on: day) ?? "rest"
            let variant = offset % 3
            eat("Oats", amount: 60, day, "breakfast", 450)
            eat("Milk 2%", amount: 250, day, "breakfast", 450)
            eat(variant == 0 ? "Apple" : "Banana", count: 1, day, "breakfast", 452)
            eat("Egg", count: 2, day, "breakfast", 455)
            eat("Whole-grain bread", count: 1, day, "breakfast", 455)
            if variant == 2 {
                eat("Salmon, baked", count: 1, day, "lunch", 750)
                eat("Potatoes, boiled", amount: 250, day, "lunch", 750)
            } else {
                eat("Chicken breast, roasted", amount: 150, day, "lunch", 750)
                eat("White rice, cooked", amount: 175 + Double(variant) * 40, day, "lunch", 750)
            }
            eat("Lettuce", amount: 80, day, "lunch", 752)
            eat("Olive oil", count: 0.5, day, "lunch", 752)
            eat("Skyr, plain", count: 1, day, "snack", 960)
            if type != "rest" {
                eat("Almonds", count: 1, day, "snack", 962)
                eat("Banana", count: 1, day, "snack", 962)
            } else if offset % 4 == 0 {
                eat("Dark chocolate 70%", count: 2, day, "snack", 1230)
            }
            let pasta = 210 + Double(offset % 5) * 15 + (type == "gym" ? 40 : (type == "tennis" ? 20 : 0))
            eat("Spaghetti, cooked", amount: pasta, day, "dinner", 1125)
            eat("Tomato", count: 2, day, "dinner", 1125)
            eat("Olive oil", count: 1, day, "dinner", 1125)
            eat("Chicken breast, roasted", amount: 80, day, "dinner", 1125)
        }

        let today = coach.today
        eat("Oats", amount: 60, today, "breakfast", 445)
        eat("Milk 2%", amount: 250, today, "breakfast", 445)
        eat("Banana", count: 1, today, "breakfast", 446)
        eat("Coffee", count: 1, today, "breakfast", 450)
        eat("Chicken breast, roasted", amount: 150, today, "lunch", 760)
        eat("White rice, cooked", amount: 220, today, "lunch", 760)
        eat("Lettuce", amount: 80, today, "lunch", 761)
        eat("Skyr, plain", count: 1, today, "snack", 960)
        eat("Almonds", count: 1, today, "snack", 961)
        eat("Salmon, baked", count: 1, today, "dinner", 1110, .planned)
        eat("Potatoes, boiled", amount: 250, today, "dinner", 1110, .planned)
        eat("Tomato", count: 2, today, "dinner", 1110, .planned)
        return lines
    }

    /// The plan and what every plan save mirrors into the profile (as `NinaStore.updatePlan`
    /// does), so the profile's own targets, goal and pace match the running phase.
    static func write(_ plan: CoachPlan, to profile: NinaProfile, on day: DayKey) {
        profile.coachPlan = plan.encoded
        guard let mirror = plan.mirror(on: day) else { return }
        let state = mirror.applied(to: SettingsState(profile: profile, weight: 0))
        profile.targets = state.targets.encoded
        profile.trainingTargets = state.trainingTargets?.encoded ?? ""
        profile.trainingDays = state.trainingTargets == nil ? "" : state.trainingDays.encoded
        profile.goal = state.goal.rawValue
        profile.ratePerWeek = state.ratePerWeek
        profile.targetWeight = state.targetWeight
    }

    /// Weigh-ins, tape and body-fat records.
    static func insertBody(_ coach: DemoCoach, context: ModelContext) {
        for weighIn in coach.weighIns {
            let entry = WeightEntry(day: weighIn.day, time: weighIn.day.date(minutes: weighIn.minutes), kilograms: weighIn.kilograms)
            entry.note = weighIn.note
            context.insert(entry)
        }
        for record in coach.records {
            let time = record.day.date(minutes: record.minutes)
            let measurement = BodyMeasurement(day: record.day, time: time, kind: record.kind, values: record.values)
            BodyMeasurementDraft(day: record.day, time: time, kind: record.kind, values: record.values, method: record.method,
                                 conditions: record.conditions).write(to: measurement)
            measurement.createdAt = time
            measurement.modifiedAt = time
            context.insert(measurement)
        }
    }

    /// Day types picked by hand, check ticks, phase decisions and the saved check-ins.
    static func insertMarks(_ coach: DemoCoach, totals: [DayKey: DayTotals], context: ModelContext) {
        for (day, typeID) in coach.dayTypes {
            insertMark(.dayType, day: day, key: typeID, meta: [:], minutes: 420, context: context)
        }
        for tick in coach.ticks {
            insertMark(.check, day: tick.day, key: tick.checkID, meta: ["state": tick.state.rawValue], minutes: 465, context: context)
        }
        for event in coach.events {
            insertMark(.phase, day: event.day, key: event.phaseID, meta: ["event": event.event.rawValue], minutes: 480, context: context)
        }
        for checkIn in coach.checkIns(totals: totals) {
            let time = checkIn.snapshot.day.date(minutes: 1140)
            let mark = DayMark(day: checkIn.snapshot.day, kind: .checkIn, key: checkIn.snapshot.key(), time: time)
            mark.values = checkIn.snapshot.values
            mark.meta = checkIn.snapshot.meta
            mark.note = checkIn.note
            mark.createdAt = time
            mark.modifiedAt = time
            context.insert(mark)
        }
    }

    private static func insertMark(_ kind: DayMarkKind, day: DayKey, key: String, meta: [String: String], minutes: Int,
                                   context: ModelContext) {
        // A day planned ahead was picked now, not on that day.
        let time = min(day.date(minutes: minutes), Date())
        let mark = DayMark(day: day, kind: kind, key: key, time: time)
        mark.meta = KeyValueText(meta).encoded
        mark.createdAt = time
        mark.modifiedAt = time
        context.insert(mark)
    }

    /// A saved meal with its weekday routine and a favourite own food.
    static func insertLibrary(_ context: ModelContext) {
        let breakfast = Recipe(name: "Usual breakfast", kind: .meal)
        breakfast.emoji = "🥣"
        breakfast.isFavorite = true
        breakfast.defaultMeal = "breakfast"
        context.insert(breakfast)
        let lines: [(name: String, amount: Double, count: Double?)] = [("Oats", 60, nil), ("Milk 2%", 250, nil), ("Banana", 0, 1)]
        for (index, line) in lines.enumerated() {
            guard let food = foods[line.name] else { continue }
            let item = RecipeItem(name: food.name)
            item.foodRef = food.ref
            item.category = food.category.rawValue
            item.baseUnit = food.unit.rawValue
            let grams: Double
            if let count = line.count, let portion = food.portion {
                item.quantity = count
                item.unitLabel = portion.label
                item.unitAmount = portion.amount
                grams = count * portion.amount
            } else {
                item.quantity = line.amount
                item.unitLabel = food.unit.symbol
                grams = line.amount
            }
            item.nutrients = food.per100.scaled(by: grams / 100).encoded
            item.sortOrder = Double(index)
            item.recipe = breakfast
            context.insert(item)
        }
        let rule = PlanRule(recipeID: breakfast.uuid, title: breakfast.name, meal: "breakfast", minutes: 450, weekdays: .workdays)
        context.insert(rule)

        let skyr = Food(name: "Skyr, plain")
        skyr.catalogID = "nina:skyr"
        skyr.category = FoodCategory.dairy.rawValue
        skyr.nutrients = NutrientValues([.energy: 63, .protein: 11, .carbs: 4, .fat: 0.2, .sugar: 4]).encoded
        skyr.servings = Serving.encode([Serving(en: "pot", de: "Becher", amount: 150)])
        skyr.isFavorite = true
        skyr.tags = "high-protein|snack"
        context.insert(skyr)
    }

    // MARK: - The tour's practice day

    /// The tour's practice day: breakfast logged, dinner planned, and a small coach plan a week
    /// in (gym, tennis and rest days, creatine still open today, weighed in this morning), so the
    /// day-type chip, the week strip's menu and the checks strip can be tried. No coach card shows.
    static func seedPractice(_ context: ModelContext) {
        let today = DayKey.today()
        let coach = DemoCoach.practice(today: today)
        let profile = NinaProfile()
        profile.sex = Sex.female.rawValue
        profile.birthYear = 1991
        profile.heightCm = 171
        profile.activity = ActivityLevel.moderate.rawValue
        write(coach.plan, to: profile, on: today)
        context.insert(profile)

        add("Oats", amount: 60, day: today, meal: "breakfast", minutes: 450, context: context)
        add("Milk 2%", amount: 200, day: today, meal: "breakfast", minutes: 450, context: context)
        add("Coffee", count: 1, day: today, meal: "breakfast", minutes: 455, context: context)
        add("Spaghetti, cooked", amount: 250, day: today, meal: "dinner", minutes: 1110, status: .planned, context: context)
        add("Tomato", count: 2, day: today, meal: "dinner", minutes: 1110, status: .planned, context: context)
        context.insert(WaterLog(day: today, time: today.date(minutes: 500), amount: 250))
        insertBody(coach, context: context)
        for tick in coach.ticks {
            insertMark(.check, day: tick.day, key: tick.checkID, meta: ["state": tick.state.rawValue], minutes: 465, context: context)
        }
        for event in coach.events {
            insertMark(.phase, day: event.day, key: event.phaseID, meta: ["event": event.event.rawValue], minutes: 480, context: context)
        }
    }
}

// MARK: - The coach part of the demo

/// The coach part of the demo as plain values (Foundation and NinaCore only), all relative to
/// `today`: a maintenance phase that ended three weeks ago (with a short holiday pause), a lean
/// gain running since then and a fat-loss phase planned after it; gym, tennis and rest days, two
/// daily checks, morning weigh-ins rising a little slower than planned, tape and body-fat
/// records, and the check-ins of the last two weeks. This week's check-in is left open: it is the
/// second slow week in a row, so the check-in proposes a small calorie step. Made-up numbers only.
struct DemoCoach {
    struct WeighIn {
        let day: DayKey
        let minutes: Int
        let kilograms: Double
        let note: String
    }

    struct Record {
        let day: DayKey
        let minutes: Int
        let kind: BodyRecordKind
        let values: BodyValues
        let method: BodyMethod?
        let conditions: String
    }

    struct Tick {
        let day: DayKey
        let checkID: String
        let state: CheckState
    }

    struct Event {
        let day: DayKey
        let phaseID: String
        let event: PhaseEvent
    }

    struct Drink {
        let day: DayKey
        let minutes: Int
        let amount: Double
    }

    /// A saved check-in: the snapshot (with ratings and the waist) and the note.
    struct CheckIn {
        var snapshot: CheckInSnapshot
        var result: CheckInResult
        var note: String
    }

    /// Days of history before today.
    static let history = 42
    /// The lean gain started this many days ago; the maintenance phase ended the day before.
    static let gainStart = 21
    /// The holiday pause, in days before today.
    static let pause = 31...35

    static func targets(_ energy: Double, _ protein: Double, _ carbs: Double, _ fat: Double) -> DailyTargets {
        DailyTargets(energy: energy, protein: protein, carbs: carbs, fat: fat, fiber: 30, sugarMax: 55, saturatedFatMax: 24,
                     sodiumMax: 2000, water: 2400)
    }

    /// The lean gain's targets per day type.
    static let rest = targets(2150, 125, 255, 70)
    static let gym = targets(2450, 130, 315, 72)
    static let tennis = targets(2400, 125, 305, 72)
    /// The lean gain's baseline: its planned week average (3 gym, 2 tennis, 2 rest days ≈ 2,350),
    /// so the plan editor shows no week-average warning.
    static let gainBaseline = targets(2350, 128, 290, 72)

    let today: DayKey
    let calendar: Calendar
    let plan: CoachPlan
    /// The practice day's smaller set of records (the tour), else the full demo.
    let isPractice: Bool

    init(today: DayKey, calendar: Calendar = .current) {
        self.today = today
        self.calendar = calendar
        self.plan = DemoCoach.demoPlan(today: today, calendar: calendar)
        self.isPractice = false
    }

    private init(practice today: DayKey, calendar: Calendar) {
        self.today = today
        self.calendar = calendar
        self.plan = DemoCoach.practicePlan(today: today, calendar: calendar)
        self.isPractice = true
    }

    /// The tour's practice day: the same day types, a lean gain started a week ago, creatine only.
    static func practice(today: DayKey, calendar: Calendar = .current) -> DemoCoach {
        DemoCoach(practice: today, calendar: calendar)
    }

    /// The day `offset` days before today (negative: ahead).
    func day(_ offset: Int) -> DayKey { today.adding(days: -offset, calendar: calendar) }

    /// Days with a diary (some days aren't logged, the holiday isn't).
    func isLogged(_ offset: Int) -> Bool { offset % 11 != 0 && !DemoCoach.pause.contains(offset) }

    // MARK: Plan

    static func planDayTypes() -> [CoachPlan.DayType] {
        [
            CoachPlan.DayType(id: "gym", name: "Gym", emoji: "🏋️", schedule: .fixed, weekdays: Weekdays([1, 3, 5]),
                              workouts: ["strength"]),
            CoachPlan.DayType(id: "tennis", name: "Tennis", emoji: "🎾", schedule: .flexible, perWeek: 2, workouts: ["tennis"]),
            CoachPlan.DayType(id: "rest", name: "Rest", emoji: "🛋️", schedule: .default),
        ]
    }

    static func gainPhase(start: DayKey, startedAt: Date, end: DayKey) -> CoachPlan.Phase {
        CoachPlan.Phase(id: "2", name: "Lean gain", goal: .gain, start: start, end: end, endApprox: true,
                        rateMin: 0.15, rateMax: 0.25, reviewMin: 68.6, reviewMax: 69, targetWeight: 69,
                        startedAt: startedAt, status: .active, note: "Slow and steady, so most of the gain is muscle.",
                        revisions: [CoachPlan.Revision(from: start, baseline: gainBaseline,
                                                       byType: ["gym": gym, "tennis": tennis, "rest": rest], reason: "import")])
    }

    static func demoPlan(today: DayKey, calendar: Calendar) -> CoachPlan {
        func day(_ offset: Int) -> DayKey { today.adding(days: -offset, calendar: calendar) }
        let maintenance = CoachPlan.Revision(
            from: day(history), baseline: targets(2210, 122, 265, 70),
            byType: ["gym": targets(2300, 125, 290, 70), "tennis": targets(2250, 120, 285, 70), "rest": targets(2050, 120, 240, 68)],
            reason: "import")
        let phases = [
            CoachPlan.Phase(id: "1", name: "Maintenance", goal: .maintain, start: day(history), end: day(gainStart + 1),
                            startedAt: day(history).date(minutes: 480, calendar: calendar), status: .done,
                            revisions: [maintenance]),
            gainPhase(start: day(gainStart), startedAt: day(gainStart).date(minutes: 470, calendar: calendar),
                      end: day(gainStart - 98)),
            CoachPlan.Phase(id: "3", name: "Fat loss", goal: .lose, start: day(gainStart - 99), startApprox: true,
                            end: day(gainStart - 155), endApprox: true, rateMin: 0.3, rateMax: 0.5, targetWeight: 67.5,
                            status: .planned),
        ]
        var routine = CoachPlan.Routine.defaults(for: .female)
        routine.checkInWeekday = today.weekday(calendar: calendar)
        routine.bodyFatMethod = .scale
        let checks = [
            CoachPlan.Check(id: "creatine", name: "Creatine", emoji: "💊", dose: "3–5 g", timing: .meal("breakfast"), remind: true),
            CoachPlan.Check(id: "vitamind", name: "Vitamin D", emoji: "☀️", timing: .anytime, isOptional: true),
        ]
        return CoachPlan(dayTypes: planDayTypes(), phases: phases, longTerm: CoachPlan.LongTerm(weightKg: 67.5, bodyFat: 23),
                         protein: CoachPlan.Protein(mealMin: 25, count: 3, meals: ["breakfast", "lunch", "dinner"]),
                         checks: checks, routine: routine,
                         pauses: [CoachPlan.Pause(start: day(pause.upperBound), end: day(pause.lowerBound), reason: .holiday)],
                         notes: ["Eat a carb-rich snack about an hour before tennis."])
    }

    /// The practice plan: the check-in falls on tomorrow's weekday, so no card covers the diary
    /// and this week's waist is already measured.
    static func practicePlan(today: DayKey, calendar: Calendar) -> CoachPlan {
        let start = today.adding(days: -7, calendar: calendar)
        var routine = CoachPlan.Routine.defaults(for: .female)
        routine.checkInWeekday = today.adding(days: 1, calendar: calendar).weekday(calendar: calendar)
        routine.bodyFatMethod = .scale
        let creatine = CoachPlan.Check(id: "creatine", name: "Creatine", emoji: "💊", dose: "3–5 g", timing: .meal("breakfast"))
        return CoachPlan(dayTypes: planDayTypes(),
                         phases: [gainPhase(start: start, startedAt: start.date(minutes: 470, calendar: calendar),
                                            end: today.adding(days: 84, calendar: calendar))],
                         protein: CoachPlan.Protein(mealMin: 25, count: 3, meals: ["breakfast", "lunch", "dinner"]),
                         checks: [creatine], routine: routine)
    }

    // MARK: Days and marks

    /// Day types picked by hand: tennis on Tuesdays and Saturdays (not on holiday), this week's
    /// next one planned ahead. None on the practice day (that is for the tour to try).
    var dayTypes: [DayKey: String] {
        guard !isPractice else { return [:] }
        var marks: [DayKey: String] = [:]
        let end = today.startOfWeek(calendar: calendar).adding(days: 6, calendar: calendar)
        for date in DayKey.range(day(DemoCoach.history), through: end, calendar: calendar) {
            let offset = date.days(to: today, calendar: calendar)
            guard [2, 6].contains(date.weekday(calendar: calendar)), !DemoCoach.pause.contains(offset) else { continue }
            marks[date] = "tennis"
        }
        return marks
    }

    /// The marks as the plan's resolvers read them (DayKey raw value → type id).
    var dayTypeMarks: [String: String] {
        var marks: [String: String] = [:]
        for (date, typeID) in dayTypes { marks[date.rawValue] = typeID }
        return marks
    }

    func typeID(on date: DayKey) -> String? { plan.dayType(on: date, marks: dayTypeMarks, calendar: calendar)?.id }

    /// Morning weigh-ins (07:00–07:10) on most days: flat while maintaining, then rising about
    /// 0.08 kg a week – slower than the plan's 0.15–0.25. One salty morning, one evening weigh-in.
    var weighIns: [WeighIn] {
        let noise = [0.15, -0.1, 0.25, 0.0, -0.2, 0.1, -0.15]
        let first = isPractice ? 7 : DemoCoach.history
        let start = isPractice ? 7 : DemoCoach.gainStart
        var list: [WeighIn] = []
        for offset in (0...first).reversed() where isPractice || (!DemoCoach.pause.contains(offset) && ![17, 26].contains(offset)) {
            let gained = offset < start ? Double(start - offset) / 7 * 0.08 : 0
            var kilograms = 66.9 + gained + noise[offset % noise.count]
            var note = ""
            if !isPractice, offset == 10 {
                kilograms += 0.6
                note = WeightSignal.Tag.salty.token
            }
            list.append(WeighIn(day: day(offset), minutes: 420 + (offset % 3) * 5, kilograms: (kilograms * 10).rounded() / 10, note: note))
            if !isPractice, offset == 4 {
                list.append(WeighIn(day: day(offset), minutes: 1150, kilograms: ((kilograms + 0.9) * 10).rounded() / 10, note: ""))
            }
        }
        return list
    }

    /// Full tape sets with a body-fat reading from the same scale at the start of each phase,
    /// the narrow waist every check-in day in between (morning, fasted).
    var records: [Record] {
        let standard = BodyProtocol.encode([.morning, .fasted])
        func fullSet(_ offset: Int, _ sites: [BodySite: Double]) -> Record {
            Record(day: day(offset), minutes: 435, kind: .tape, values: BodyValues(sites), method: nil, conditions: standard)
        }
        func weekly(_ offset: Int, _ centimeters: Double) -> Record {
            Record(day: day(offset), minutes: 435, kind: .tape, values: BodyValues([.waistNarrow: centimeters]), method: nil,
                   conditions: standard)
        }
        func bodyFat(_ offset: Int, _ percent: Double) -> Record {
            Record(day: day(offset), minutes: 425, kind: .assessment, values: BodyValues([BodyValues.bodyFatKey: percent]),
                   method: .scale, conditions: standard)
        }
        if isPractice {
            return [fullSet(7, [.waistNarrow: 71.2, .hip: 98.4, .chest: 90.8, .arm: 28.8, .thigh: 55.4, .neck: 32.6]),
                    bodyFat(7, 26.1), weekly(6, 71.3)]
        }
        return [
            fullSet(42, [.waistNarrow: 71.0, .hip: 98.0, .chest: 90.5, .arm: 28.5, .thigh: 55.0, .neck: 32.5]), bodyFat(42, 26.4),
            fullSet(21, [.waistNarrow: 71.2, .hip: 98.4, .chest: 90.8, .arm: 28.8, .thigh: 55.4, .neck: 32.6]), bodyFat(21, 26.1),
            weekly(14, 71.3), weekly(7, 71.5),
        ]
    }

    /// Creatine ticked on most days since the lean gain started (missed twice, "Not today" once,
    /// still open today); the optional vitamin D on about two days in three, today included.
    var ticks: [Tick] {
        var list: [Tick] = []
        for offset in (0...(isPractice ? 7 : DemoCoach.gainStart)).reversed() {
            if offset > 0, isPractice || ![5, 12].contains(offset) {
                list.append(Tick(day: day(offset), checkID: "creatine", state: offset == 9 ? .skipped : .done))
            }
            if !isPractice, offset % 3 != 1 { list.append(Tick(day: day(offset), checkID: "vitamind", state: .done)) }
        }
        return list
    }

    /// When each phase was started (and the maintenance phase ended).
    var events: [Event] {
        if isPractice { return [Event(day: day(7), phaseID: "2", event: .started)] }
        return [
            Event(day: day(DemoCoach.history), phaseID: "1", event: .started),
            Event(day: day(DemoCoach.gainStart + 1), phaseID: "1", event: .ended),
            Event(day: day(DemoCoach.gainStart), phaseID: "2", event: .started),
        ]
    }

    /// 7 to 9 glasses on logged days, 5 so far today.
    var drinks: [Drink] {
        var list: [Drink] = []
        for offset in (1...DemoCoach.history).reversed() where isLogged(offset) {
            for index in 0..<(7 + offset % 3) { list.append(Drink(day: day(offset), minutes: 480 + index * 90, amount: 250)) }
        }
        for index in 0..<5 { list.append(Drink(day: today, minutes: 480 + index * 90, amount: 250)) }
        return list
    }

    // MARK: Check-ins

    /// Diary and water totals per day.
    static func totals(_ facts: [EntryFacts], drinks: [Drink]) -> [DayKey: DayTotals] {
        let byDay = Dictionary(grouping: facts, by: { $0.day })
        var water: [DayKey: Double] = [:]
        for drink in drinks { water[drink.day, default: 0] += drink.amount }
        var totals: [DayKey: DayTotals] = [:]
        for date in Set(byDay.keys).union(water.keys) {
            totals[date] = DayTotals(day: date, entries: byDay[date] ?? [], water: water[date] ?? 0)
        }
        return totals
    }

    /// The morning weight signal of the demo weigh-ins.
    var signal: WeightSignal {
        let readings = weighIns.map { weighIn in
            WeightSignal.Reading(day: weighIn.day, time: weighIn.day.date(minutes: weighIn.minutes, calendar: calendar),
                                 kilograms: weighIn.kilograms, note: weighIn.note)
        }
        return WeightSignal(readings, cutoffMinutes: plan.routine.morningCutoffMinutes, calendar: calendar)
    }

    /// The check-ins of the two weeks before this one, as the check-in sheet computed them on
    /// their day, saved with a few ratings, that week's waist and (once) a note. This week's
    /// check-in is left open.
    func checkIns(totals: [DayKey: DayTotals]) -> [CheckIn] {
        guard !isPractice else { return [] }
        let signal = self.signal
        let ratings = [CheckInRatings(hunger: 3, energy: 4, sleep: 4, performance: 3),
                       CheckInRatings(hunger: 3, energy: 3, sleep: 2, performance: 4, stress: 4)]
        let notes = ["", "Busy week at work – slept a bit less."]
        let waists = records.filter { $0.kind == .tape }
        var saved: [CheckIn] = []
        for (index, offset) in [14, 7].enumerated() {
            let date = day(offset)
            var checkIn = evaluate(on: date, history: saved.map(\.snapshot), totals: totals, signal: signal)
            checkIn.snapshot.ratings = ratings[index]
            checkIn.snapshot.waist = waists.first { $0.day == date }?.values[.waistNarrow]
            checkIn.snapshot.decision = checkIn.result.delta != 0 ? .kept : nil
            checkIn.note = notes[index]
            saved.append(checkIn)
        }
        return saved
    }

    /// The check-in of `date` with the recipe of the app's `CheckInEvaluation`: the weight
    /// signal, adherence over the decision window and the week before, and the engine's result.
    func evaluate(on date: DayKey, history: [CheckInSnapshot], totals: [DayKey: DayTotals], signal: WeightSignal) -> CheckIn {
        let done = ticks.filter { $0.state == .done }
        let body = BodyProfile(sex: .female, age: date.year - 1991, heightCm: 171,
                               weightKg: signal.bodyWeight(on: date)?.kilograms ?? 67, activity: .moderate, goal: .gain,
                               ratePerWeek: 0.2)
        var input = CheckInInput(day: date, plan: plan, fallback: DemoCoach.rest, history: history,
                                 weightCheck: CheckInEngine.weightCheck(in: plan, ticks: done.map { (day: $0.day, checkID: $0.checkID) }),
                                 bmr: GoalCalculator.bmr(body), sex: .female)
        input.use(signal: signal)
        // Measured maintenance up to the day before (the check-in day is still being logged),
        // without paused days, as the app's check-in reads it.
        let end = date.adding(days: -1, calendar: calendar)
        let window = end.adding(days: -27, calendar: calendar)
        let recent = totals.values.filter { $0.day >= window && $0.day <= end }.sorted { $0.day < $1.day }
        let paused = Set(recent.map(\.day).filter { plan.isPaused(on: $0) })
        input.maintenance = Insights.maintenance(totals: recent, weights: signal.morningWeights, today: end, excluding: paused,
                                                 calendar: calendar)

        var doneByDay: [DayKey: Set<String>] = [:]
        for tick in done { doneByDay[tick.day, default: []].insert(tick.checkID) }
        let marks = dayTypeMarks
        let weightKg = input.weightKg
        func adherence(_ day: DayKey) -> DayAdherence {
            DayAdherence(plan: plan, totals: totals[day] ?? DayTotals(day: day, entries: []), marks: marks,
                         fallback: DemoCoach.rest, weightKg: weightKg, mealSlots: MealSlot.defaults.count,
                         doneChecks: doneByDay[day] ?? [], calendar: calendar)
        }
        let windowSummary = Adherence.summary(input.adherenceDays(calendar: calendar).map { adherence($0) }, plan: plan)
        let weekSummary = Adherence.summary(input.weekDays(calendar: calendar).map { adherence($0) }, plan: plan)
        input.use(window: windowSummary, week: weekSummary)

        let result = CheckInEngine.evaluate(input, calendar: calendar)
        var snapshot = CheckInSnapshot(day: date)
        snapshot.record(signal, plan: plan)
        snapshot.record(weekSummary)
        snapshot.record(result, phaseID: plan.activePhase(on: date)?.id ?? "")
        return CheckIn(snapshot: snapshot, result: result, note: "")
    }
}
