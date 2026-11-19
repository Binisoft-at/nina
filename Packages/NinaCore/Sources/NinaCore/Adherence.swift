import Foundation

/// How well days followed the plan (F11): per day "logged", "kcal in band", "protein",
/// "protein meals" and "on plan", and a summary over a week or a decision window with the
/// averages the weekly check-in shows. Pure functions over plain values; nothing is stored.
public enum Adherence {
    /// A day is in the kcal band within ±10 % of its target …
    public static let kcalBandShare = 0.10
    /// … or within ±150 kcal, whichever is larger.
    public static let kcalBandMinimum = 150.0
    /// Protein counts as reached from 90 % of the target.
    public static let proteinShare = 0.9
    /// Weekly grade: 85 % or more of the days on plan is good …
    public static let goodShare = 0.85
    /// … 70–84 % is "watch", below 70 % is off.
    public static let watchShare = 0.70

    /// The allowed distance from a day's kcal target: max(10 % of it, 150 kcal).
    public static func kcalBand(target: Double) -> Double {
        max(kcalBandShare * max(0, target), kcalBandMinimum)
    }

    /// Eaten kcal within the band around the target.
    public static func isInKcalBand(eaten: Double, target: Double) -> Bool {
        abs(eaten - target) <= kcalBand(target: target) + 1e-9
    }

    /// Protein at least 90 % of the target (always true for a target of 0).
    public static func isProteinReached(eaten: Double, target: Double) -> Bool {
        target <= 0 || eaten + 1e-9 >= proteinShare * target
    }

    /// Meals that reached the protein minimum: of `meals` (meal slot ids; empty = every meal with
    /// something eaten), the ones with at least `minimum` g protein in whole grams, as the meal
    /// header pill shows it (`ProteinMeals.reaches`), at most `count` (0 = no cap). Without a
    /// minimum nothing is counted.
    public static func proteinMeals(byMeal: [String: NutrientValues], minimum: Double, meals: [String] = [], count: Int = 0) -> Int {
        guard minimum > 0 else { return 0 }
        let ids = meals.isEmpty ? Array(byMeal.keys) : meals
        let reached = Set(ids).filter { ProteinMeals.reaches(byMeal[$0]?.value(.protein) ?? 0, minimum: minimum) }.count
        return count > 0 ? min(reached, count) : reached
    }
}

/// The weekly grade: share of the counted (not paused) days on plan.
public enum AdherenceGrade: String, Codable, Sendable, CaseIterable, Identifiable {
    /// 85 % or more.
    case good
    /// 70–84 %.
    case watch
    /// Below 70 %.
    case off

    public var id: String { rawValue }

    public init(share: Double) {
        if share + 1e-9 >= Adherence.goodShare { self = .good }
        else if share + 1e-9 >= Adherence.watchShare { self = .watch }
        else { self = .off }
    }

    public var title: String {
        switch self {
        case .good: "Good"
        case .watch: "Watch"
        case .off: "Off"
        }
    }
}

/// One day measured against its resolved targets.
public struct DayAdherence: Equatable, Sendable, Identifiable {
    public var day: DayKey
    /// The day type the day resolved to (nil without day types).
    public var dayTypeID: String?
    /// Coaching was paused: the day is left out of every count.
    public var isPaused: Bool
    /// Something eaten was logged, and the day isn't marked "incomplete log".
    public var isLogged: Bool
    /// Eaten kcal, protein g, fiber g; water ml from the water log.
    public var energy: Double
    public var protein: Double
    public var fiber: Double
    public var water: Double
    /// The targets that applied on the day (day type > baseline > profile).
    public var targets: DailyTargets
    /// Meals that reached the per-meal protein minimum (at most `proteinMealsTarget`).
    public var proteinMeals: Int
    /// Protein meals the plan asks for (0 = not tracked).
    public var proteinMealsTarget: Int
    /// Ids of the checks due that day (plus any ticked although not due), in plan order.
    public var checksDue: [String]
    /// Ids of the checks ticked done that day.
    public var checksDone: [String]

    public var id: String { day.rawValue }

    public init(day: DayKey, dayTypeID: String? = nil, isPaused: Bool = false, isLogged: Bool, energy: Double = 0, protein: Double = 0,
                fiber: Double = 0, water: Double = 0, targets: DailyTargets, proteinMeals: Int = 0, proteinMealsTarget: Int = 0,
                checksDue: [String] = [], checksDone: [String] = []) {
        self.day = day
        self.dayTypeID = dayTypeID
        self.isPaused = isPaused
        self.isLogged = isLogged
        self.energy = energy
        self.protein = protein
        self.fiber = fiber
        self.water = water
        self.targets = targets
        self.proteinMealsTarget = max(0, proteinMealsTarget)
        self.proteinMeals = proteinMealsTarget > 0 ? min(max(0, proteinMeals), proteinMealsTarget) : max(0, proteinMeals)
        self.checksDue = checksDue
        self.checksDone = checksDone
    }

    /// A diary day against given targets.
    /// - Parameters:
    ///   - incomplete: the day is marked "incomplete log" (it then doesn't count as logged).
    ///   - proteinMinimum: g per protein meal (0 = protein meals not tracked).
    ///   - proteinMealCount: protein meals per day.
    ///   - proteinMealIDs: the meal slots that count (empty = all).
    ///   - checks: the plan's daily checks; `doneChecks` the ids ticked done that day.
    public init(totals: DayTotals, targets: DailyTargets, dayTypeID: String? = nil, isPaused: Bool = false, incomplete: Bool = false,
                proteinMinimum: Double = 0, proteinMealCount: Int = 0, proteinMealIDs: [String] = [],
                checks: [CoachPlan.Check] = [], doneChecks: Set<String> = [], calendar: Calendar = .current) {
        let tracked = proteinMinimum > 0 && proteinMealCount > 0
        let meals = tracked ? Adherence.proteinMeals(byMeal: totals.byMeal, minimum: proteinMinimum, meals: proteinMealIDs, count: proteinMealCount) : 0
        let done = checks.filter { doneChecks.contains($0.id) }.map(\.id)
        let due = checks.filter { $0.isDue(on: totals.day, dayTypeID: dayTypeID, calendar: calendar) || doneChecks.contains($0.id) }.map(\.id)
        self.init(day: totals.day, dayTypeID: dayTypeID, isPaused: isPaused, isLogged: totals.isLogged && !incomplete,
                  energy: totals.eaten.energy, protein: totals.eaten.value(.protein), fiber: totals.eaten.value(.fiber),
                  water: totals.water, targets: targets, proteinMeals: meals, proteinMealsTarget: tracked ? proteinMealCount : 0,
                  checksDue: due, checksDone: done)
    }

    /// A diary day resolved through the plan: its day type (`marks`: DayKey raw value → type id),
    /// targets (`fallback` = the profile's), pause, protein meals (minimum from the plan or
    /// 0.4 g/kg of `weightKg`; count from the plan or one per meal slot) and checks.
    public init(plan: CoachPlan, totals: DayTotals, marks: [String: String], fallback: DailyTargets, weightKg: Double = 0,
                mealSlots: Int = MealSlot.defaults.count, doneChecks: Set<String> = [], incomplete: Bool = false,
                calendar: Calendar = .current) {
        let day = totals.day
        let type = plan.dayType(on: day, marks: marks, calendar: calendar)
        self.init(totals: totals, targets: plan.targets(on: day, marks: marks, fallback: fallback, calendar: calendar),
                  dayTypeID: type?.id, isPaused: plan.isPaused(on: day), incomplete: incomplete,
                  proteinMinimum: plan.protein.minimum(weightKg: weightKg),
                  proteinMealCount: plan.protein.effectiveCount(mealSlots: mealSlots), proteinMealIDs: plan.protein.meals,
                  checks: plan.checks, doneChecks: doneChecks, calendar: calendar)
    }

    /// The allowed distance from the kcal target: max(10 %, 150 kcal).
    public var kcalBand: Double { Adherence.kcalBand(target: targets.energy) }

    /// Logged and within the kcal band of the day's target.
    public var isKcalInBand: Bool { isLogged && Adherence.isInKcalBand(eaten: energy, target: targets.energy) }

    /// Logged with at least 90 % of the protein target.
    public var isProteinReached: Bool { isLogged && Adherence.isProteinReached(eaten: protein, target: targets.protein) }

    /// At least count − 1 protein meals (always true when protein meals aren't tracked).
    public var isProteinMealsReached: Bool {
        guard proteinMealsTarget > 0 else { return true }
        return isLogged && proteinMeals >= proteinMealsTarget - 1
    }

    /// Logged, kcal in band and protein reached.
    public var isOnPlan: Bool { isLogged && isKcalInBand && isProteinReached }

    /// Eaten minus target kcal (negative = under).
    public var balance: Double { energy - targets.energy }
}

/// Days of a week (or a decision window) summed up for the check-in's "How it went" page.
/// Paused days are left out of every count and average; averages are over the logged days.
public struct AdherenceSummary: Equatable, Sendable {
    /// Average eaten vs. average target on the logged days of one day type: "Tennis days avg 2,750 of 2,800".
    public struct TypeAverage: Equatable, Sendable, Identifiable {
        /// "" = days without a day type.
        public var typeID: String
        /// Counted days of this type, and the logged ones among them.
        public var days: Int
        public var loggedDays: Int
        public var averageIntake: Double
        public var averageTarget: Double

        public var id: String { typeID }
    }

    /// A daily check: "Creatine 6 of 7". Optional checks never count as missed.
    public struct CheckTally: Equatable, Sendable, Identifiable {
        public var checkID: String
        public var done: Int
        public var due: Int
        public var isOptional: Bool

        public var id: String { checkID }
        public var missed: Int { isOptional ? 0 : max(0, due - done) }
    }

    /// A flexible day type's count: "Tennis 2 of 2".
    public struct FlexibleTally: Equatable, Sendable, Identifiable {
        public var typeID: String
        public var count: Int
        /// perWeek × weeks in the summary.
        public var planned: Int

        public var id: String { typeID }
    }

    /// Days that count (not paused), and the paused ones left out.
    public var days: Int
    public var pausedDays: Int
    public var loggedDays: Int
    public var onPlanDays: Int
    /// Logged days within the kcal band.
    public var kcalDays: Int
    /// Logged days with at least 90 % of the protein target.
    public var proteinDays: Int
    /// Days with at least count − 1 protein meals (only days where protein meals are tracked).
    public var proteinMealDays: Int
    /// Protein meals reached, of the meals planned: "Protein meals 21 of 28".
    public var proteinMeals: Int
    public var proteinMealsTarget: Int
    /// Over the logged days: eaten vs. that day's resolved target.
    public var averageIntake: Double
    public var averageTarget: Double
    public var averageProtein: Double
    public var averageProteinTarget: Double
    public var averageFiber: Double
    public var averageFiberTarget: Double
    public var averageWater: Double
    public var averageWaterTarget: Double
    /// Per day type, in plan order (types without counted days left out).
    public var byType: [TypeAverage]
    /// Per daily check, in plan order.
    public var checks: [CheckTally]
    /// Per flexible day type with a weekly count.
    public var flexible: [FlexibleTally]
    /// The 1–5 feelings from the check-in sheet (optional, filled in by the person).
    public var ratings: CheckInRatings

    public init(days: Int = 0, pausedDays: Int = 0, loggedDays: Int = 0, onPlanDays: Int = 0, kcalDays: Int = 0, proteinDays: Int = 0,
                proteinMealDays: Int = 0, proteinMeals: Int = 0, proteinMealsTarget: Int = 0, averageIntake: Double = 0,
                averageTarget: Double = 0, averageProtein: Double = 0, averageProteinTarget: Double = 0, averageFiber: Double = 0,
                averageFiberTarget: Double = 0, averageWater: Double = 0, averageWaterTarget: Double = 0, byType: [TypeAverage] = [],
                checks: [CheckTally] = [], flexible: [FlexibleTally] = [], ratings: CheckInRatings = CheckInRatings()) {
        self.days = days
        self.pausedDays = pausedDays
        self.loggedDays = loggedDays
        self.onPlanDays = onPlanDays
        self.kcalDays = kcalDays
        self.proteinDays = proteinDays
        self.proteinMealDays = proteinMealDays
        self.proteinMeals = proteinMeals
        self.proteinMealsTarget = proteinMealsTarget
        self.averageIntake = averageIntake
        self.averageTarget = averageTarget
        self.averageProtein = averageProtein
        self.averageProteinTarget = averageProteinTarget
        self.averageFiber = averageFiber
        self.averageFiberTarget = averageFiberTarget
        self.averageWater = averageWater
        self.averageWaterTarget = averageWaterTarget
        self.byType = byType
        self.checks = checks
        self.flexible = flexible
        self.ratings = ratings
    }

    /// Share of the counted days on plan (nil when every day was paused).
    public var onPlanShare: Double? { days > 0 ? Double(onPlanDays) / Double(days) : nil }

    /// Share of the counted days logged (nil when every day was paused).
    public var loggedShare: Double? { days > 0 ? Double(loggedDays) / Double(days) : nil }

    /// Good (85 % or more on plan), watch (70–84 %) or off (below 70 %); nil when every day was paused.
    public var grade: AdherenceGrade? { onPlanShare.map(AdherenceGrade.init(share:)) }

    /// Average eaten minus average target on the logged days (negative = under).
    public var averageBalance: Double { averageIntake - averageTarget }

    /// The tally of one check.
    public func check(_ id: String) -> CheckTally? { checks.first { $0.checkID == id } }

    /// The average of one day type.
    public func type(_ id: String) -> TypeAverage? { byType.first { $0.typeID == id } }
}

extension Adherence {
    /// Sums up days (a week, or a decision window). With a plan, day types and checks follow its
    /// order and carry its settings (optional checks, flexible weekly counts).
    public static func summary(_ days: [DayAdherence], plan: CoachPlan? = nil) -> AdherenceSummary {
        let counted = days.filter { !$0.isPaused }
        let logged = counted.filter(\.isLogged)
        func mean(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }

        var result = AdherenceSummary()
        result.days = counted.count
        result.pausedDays = days.count - counted.count
        result.loggedDays = logged.count
        result.onPlanDays = counted.filter(\.isOnPlan).count
        result.kcalDays = counted.filter(\.isKcalInBand).count
        result.proteinDays = counted.filter(\.isProteinReached).count
        let tracked = counted.filter { $0.proteinMealsTarget > 0 }
        result.proteinMealDays = tracked.filter(\.isProteinMealsReached).count
        result.proteinMeals = tracked.map(\.proteinMeals).reduce(0, +)
        result.proteinMealsTarget = tracked.map(\.proteinMealsTarget).reduce(0, +)
        result.averageIntake = mean(logged.map(\.energy))
        result.averageTarget = mean(logged.map(\.targets.energy))
        result.averageProtein = mean(logged.map(\.protein))
        result.averageProteinTarget = mean(logged.map(\.targets.protein))
        result.averageFiber = mean(logged.map(\.fiber))
        result.averageFiberTarget = mean(logged.map(\.targets.fiber))
        result.averageWater = mean(logged.map(\.water))
        result.averageWaterTarget = mean(logged.map(\.targets.water))

        // Day types: plan order first, then any other id in order of appearance.
        var typeOrder = plan?.dayTypes.map(\.id) ?? []
        for day in counted {
            let id = day.dayTypeID ?? ""
            if !typeOrder.contains(id) { typeOrder.append(id) }
        }
        result.byType = typeOrder.compactMap { id in
            let ofType = counted.filter { ($0.dayTypeID ?? "") == id }
            guard !ofType.isEmpty else { return nil }
            let loggedOfType = ofType.filter(\.isLogged)
            return AdherenceSummary.TypeAverage(typeID: id, days: ofType.count, loggedDays: loggedOfType.count,
                                                averageIntake: mean(loggedOfType.map(\.energy)),
                                                averageTarget: mean(loggedOfType.map(\.targets.energy)))
        }

        // Checks: plan order first, then any other id in order of appearance.
        var checkOrder = plan?.checks.map(\.id) ?? []
        for day in counted {
            for id in day.checksDue + day.checksDone where !checkOrder.contains(id) { checkOrder.append(id) }
        }
        result.checks = checkOrder.compactMap { id in
            let due = counted.filter { $0.checksDue.contains(id) || $0.checksDone.contains(id) }.count
            let done = counted.filter { $0.checksDone.contains(id) }.count
            let optional = plan?.check(id: id)?.isOptional ?? false
            guard due > 0 || plan?.check(id: id) != nil else { return nil }
            return AdherenceSummary.CheckTally(checkID: id, done: done, due: due, isOptional: optional)
        }

        // Flexible types: how often they were picked (every day given, paused or not).
        if let plan {
            let weeks = max(1, Int((Double(days.count) / 7).rounded()))
            result.flexible = plan.dayTypes.filter { $0.schedule == .flexible && $0.perWeek > 0 }.map { type in
                AdherenceSummary.FlexibleTally(typeID: type.id, count: days.filter { $0.dayTypeID == type.id }.count,
                                               planned: type.perWeek * weeks)
            }
        }
        return result
    }
}
