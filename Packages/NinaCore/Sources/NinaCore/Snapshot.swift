import Foundation

/// The small summary widgets and watch complications read from the shared App Group
/// (`<group>/Nina/today.json`). Only today's numbers – never the diary itself.
public struct TodaySnapshot: Codable, Equatable, Sendable {
    public static let fileName = "today.json"

    public var day: String
    public var energy: Double
    public var energyGoal: Double
    public var protein: Double
    public var proteinGoal: Double
    public var carbs: Double
    public var carbsGoal: Double
    public var fat: Double
    public var fatGoal: Double
    public var water: Double
    public var waterGoal: Double
    /// "Lunch · 12:30" – the next planned meal, if any.
    public var nextPlanned: String?
    public var energyUnit: String
    public var updatedAt: Date
    // The coach plan's day type of the day (calorie cycling); nil without day types. Optional, so
    // a file written by an older build still reads.
    public var dayTypeID: String?
    public var dayTypeName: String?
    /// "🏋️" – shown in front of the numbers on the widget and the watch face.
    public var dayTypeEmoji: String?
    /// Picked by hand rather than by the schedule.
    public var dayTypeIsManual: Bool?
    /// The next day's goals and day type, for the widget's entry after the day changes.
    public var tomorrow: Goals?
    /// The hour the diary day starts (Settings → Day starts at); nil in files of older builds,
    /// which means midnight. The widget's day and its change follow it.
    public var dayStartHour: Int?
    /// The planned meals still to come today and tomorrow, so the widget's "next planned" line
    /// moves on by itself (`timeline`); nil in files of older builds.
    public var planned: [PlannedItem]?

    /// A planned meal on the widget: "Lunch · 12:30" at its time on its diary day.
    public struct PlannedItem: Codable, Equatable, Sendable {
        public var day: String
        public var time: Date
        public var text: String

        public init(day: DayKey, time: Date, text: String) {
            self.day = day.rawValue
            self.time = time
            self.text = text
        }
    }

    /// One widget timeline entry: the snapshot to show from `date` on.
    public struct TimelinePoint: Equatable, Sendable {
        public var date: Date
        public var snapshot: TodaySnapshot
    }

    /// A day's goals and day type (the snapshot's next day).
    public struct Goals: Codable, Equatable, Sendable {
        public var day: String
        public var energyGoal: Double
        public var proteinGoal: Double
        public var carbsGoal: Double
        public var fatGoal: Double
        public var waterGoal: Double
        public var dayTypeID: String?
        public var dayTypeName: String?
        public var dayTypeEmoji: String?

        public init(day: DayKey, targets: DailyTargets, dayType: CoachPlan.DayType? = nil) {
            self.day = day.rawValue
            energyGoal = targets.energy
            proteinGoal = targets.protein
            carbsGoal = targets.carbs
            fatGoal = targets.fat
            waterGoal = targets.water
            dayTypeID = dayType?.id
            dayTypeName = dayType?.name
            dayTypeEmoji = dayType.map(TodaySnapshot.emoji(of:))
        }
    }

    public init(day: String, energy: Double, energyGoal: Double, protein: Double, proteinGoal: Double, carbs: Double,
                carbsGoal: Double, fat: Double, fatGoal: Double, water: Double, waterGoal: Double,
                nextPlanned: String? = nil, energyUnit: String = "kcal", updatedAt: Date = Date()) {
        self.day = day
        self.energy = energy
        self.energyGoal = energyGoal
        self.protein = protein
        self.proteinGoal = proteinGoal
        self.carbs = carbs
        self.carbsGoal = carbsGoal
        self.fat = fat
        self.fatGoal = fatGoal
        self.water = water
        self.waterGoal = waterGoal
        self.nextPlanned = nextPlanned
        self.energyUnit = energyUnit
        self.updatedAt = updatedAt
    }

    public init(progress: DayProgress, nextPlanned: String? = nil, energyUnit: EnergyUnit = .kcal, now: Date = Date()) {
        self.init(day: progress.totals.day.rawValue,
                  energy: progress.energyEaten, energyGoal: progress.energyBudget,
                  protein: progress.totals.eaten.protein, proteinGoal: progress.targets.protein,
                  carbs: progress.totals.eaten.carbs, carbsGoal: progress.targets.carbs,
                  fat: progress.totals.eaten.fat, fatGoal: progress.targets.fat,
                  water: progress.totals.water, waterGoal: progress.targets.water,
                  nextPlanned: nextPlanned, energyUnit: energyUnit.rawValue, updatedAt: now)
    }

    public static let placeholder = TodaySnapshot(day: "2026-01-01", energy: 1240, energyGoal: 2100, protein: 82, proteinGoal: 140,
                                                  carbs: 130, carbsGoal: 230, fat: 41, fatGoal: 70, water: 1250, waterGoal: 2250,
                                                  nextPlanned: "Dinner · 18:30", updatedAt: Date(timeIntervalSince1970: 0))

    /// The day type of the day (nil clears it); a type without its own emoji gets a fitting one.
    public mutating func use(dayType: CoachPlan.DayType?, isManual: Bool = false) {
        dayTypeID = dayType?.id
        dayTypeName = dayType?.name
        dayTypeEmoji = dayType.map(TodaySnapshot.emoji(of:))
        dayTypeIsManual = dayType == nil ? nil : isManual
    }

    /// The day type's emoji, or a fitting one for its name ("" when none fits).
    public static func emoji(of type: CoachPlan.DayType) -> String {
        type.emoji.isEmpty ? CoachPlan.DayType.suggestedEmoji(for: type.name) : type.emoji
    }

    /// "🏋️ " in front of a number; "" without a day type.
    public var dayTypePrefix: String {
        guard let emoji = dayTypeEmoji, !emoji.isEmpty else { return "" }
        return emoji + " "
    }

    /// An empty day (shown after the day changed until the app writes a new snapshot): the next
    /// day's goals and day type when the snapshot has them, else the same goals without a day type.
    /// The day start and the planned meals stay.
    public func emptied(for day: DayKey) -> TodaySnapshot {
        var snapshot: TodaySnapshot
        if let next = tomorrow, next.day == day.rawValue {
            snapshot = TodaySnapshot(day: day.rawValue, energy: 0, energyGoal: next.energyGoal, protein: 0, proteinGoal: next.proteinGoal,
                                     carbs: 0, carbsGoal: next.carbsGoal, fat: 0, fatGoal: next.fatGoal, water: 0,
                                     waterGoal: next.waterGoal, nextPlanned: nil, energyUnit: energyUnit, updatedAt: updatedAt)
            snapshot.dayTypeID = next.dayTypeID
            snapshot.dayTypeName = next.dayTypeName
            snapshot.dayTypeEmoji = next.dayTypeEmoji
        } else {
            snapshot = TodaySnapshot(day: day.rawValue, energy: 0, energyGoal: energyGoal, protein: 0, proteinGoal: proteinGoal,
                                     carbs: 0, carbsGoal: carbsGoal, fat: 0, fatGoal: fatGoal, water: 0, waterGoal: waterGoal,
                                     nextPlanned: nil, energyUnit: energyUnit, updatedAt: updatedAt)
        }
        snapshot.dayStartHour = dayStartHour
        snapshot.planned = planned
        return snapshot
    }

    /// The snapshot for `today` – emptied when it is from an earlier day.
    public func current(today: DayKey) -> TodaySnapshot {
        day == today.rawValue ? self : emptied(for: today)
    }

    /// The diary day `now` counts for, with the snapshot's day start.
    public func today(now: Date, calendar: Calendar = .current) -> DayKey {
        DayKey(date: now, calendar: calendar, dayStartHour: dayStartHour ?? 0)
    }

    /// When the diary day after the one `now` counts for starts (the widget's day change).
    public func nextDayStart(after now: Date, calendar: Calendar = .current) -> Date {
        today(now: now, calendar: calendar).adding(days: 1, calendar: calendar)
            .start(dayStartHour: dayStartHour ?? 0, calendar: calendar)
    }

    /// The snapshot as the widget shows it at `now`: its diary day (emptied once that day is over)
    /// and the next planned meal still to come on it.
    public func current(now: Date, calendar: Calendar = .current) -> TodaySnapshot {
        shown(on: today(now: now, calendar: calendar), at: now, including: true)
    }

    /// The widget's timeline from `now`: now, each planned meal's time (the line moves on to the
    /// next one), the next diary day's start (an empty day with its own goals and planned meals),
    /// and that day's planned times. The widget asks again after the last entry.
    public func timeline(now: Date, calendar: Calendar = .current) -> [TimelinePoint] {
        let today = today(now: now, calendar: calendar)
        let change = nextDayStart(after: now, calendar: calendar)
        let nextDay = today.adding(days: 1, calendar: calendar)
        let afterChange = nextDay.adding(days: 1, calendar: calendar).start(dayStartHour: dayStartHour ?? 0, calendar: calendar)
        var points = [TimelinePoint(date: now, snapshot: current(now: now, calendar: calendar))]
        for time in plannedTimes(on: today, after: now, before: change) {
            points.append(TimelinePoint(date: time, snapshot: shown(on: today, at: time)))
        }
        points.append(TimelinePoint(date: change, snapshot: shown(on: nextDay, at: change, including: true)))
        for time in plannedTimes(on: nextDay, after: change, before: afterChange) {
            points.append(TimelinePoint(date: time, snapshot: shown(on: nextDay, at: time)))
        }
        return points
    }

    /// The snapshot for `day` from `date` on, with the next planned meal after that moment (a file
    /// of an older build keeps its one line).
    private func shown(on day: DayKey, at date: Date, including: Bool = false) -> TodaySnapshot {
        var snapshot = current(today: day)
        if planned != nil {
            snapshot.nextPlanned = nextPlannedText(on: day.rawValue, from: date, including: including)
        }
        return snapshot
    }

    /// The first planned meal on `day` at or after (`including`) or after `date`.
    private func nextPlannedText(on day: String, from date: Date, including: Bool) -> String? {
        guard let planned else { return nil }
        return planned.filter { $0.day == day && (including ? $0.time >= date : $0.time > date) }
            .min { $0.time < $1.time }?.text
    }

    /// The distinct planned times on `day` inside (`start`, `end`), at most 8.
    private func plannedTimes(on day: DayKey, after start: Date, before end: Date) -> [Date] {
        let times = (planned ?? []).filter { $0.day == day.rawValue && $0.time > start && $0.time < end }.map(\.time)
        return Array(Set(times).sorted().prefix(8))
    }

    public var remaining: Double { energyGoal - energy }
    public var fraction: Double { energyGoal > 0 ? energy / energyGoal : 0 }

    public func hasSameContent(as other: TodaySnapshot?) -> Bool {
        guard let other else { return false }
        var a = self, b = other
        a.updatedAt = .distantPast
        b.updatedAt = .distantPast
        return a == b
    }

    /// Always kcal: Nina shows and edits energy in kcal only. `energyUnit` stays in the file so
    /// snapshots written by older builds (which could say "kJ") still read.
    public var unit: EnergyUnit { .kcal }
}

/// Which HealthKit quantity type each nutrient is written to (raw HKQuantityTypeIdentifier values),
/// and its unit. Trans fat and alcohol grams have no HealthKit type.
public enum HealthMapping {
    public struct Item: Sendable, Equatable {
        public let nutrient: Nutrient
        public let identifier: String
        /// "kcal", "g", "mg", "mcg"
        public let unit: String
    }

    public static let items: [Item] = [
        Item(nutrient: .energy, identifier: "HKQuantityTypeIdentifierDietaryEnergyConsumed", unit: "kcal"),
        Item(nutrient: .protein, identifier: "HKQuantityTypeIdentifierDietaryProtein", unit: "g"),
        Item(nutrient: .carbs, identifier: "HKQuantityTypeIdentifierDietaryCarbohydrates", unit: "g"),
        Item(nutrient: .fat, identifier: "HKQuantityTypeIdentifierDietaryFatTotal", unit: "g"),
        Item(nutrient: .fiber, identifier: "HKQuantityTypeIdentifierDietaryFiber", unit: "g"),
        Item(nutrient: .sugar, identifier: "HKQuantityTypeIdentifierDietarySugar", unit: "g"),
        Item(nutrient: .saturatedFat, identifier: "HKQuantityTypeIdentifierDietaryFatSaturated", unit: "g"),
        Item(nutrient: .monoFat, identifier: "HKQuantityTypeIdentifierDietaryFatMonounsaturated", unit: "g"),
        Item(nutrient: .polyFat, identifier: "HKQuantityTypeIdentifierDietaryFatPolyunsaturated", unit: "g"),
        Item(nutrient: .cholesterol, identifier: "HKQuantityTypeIdentifierDietaryCholesterol", unit: "mg"),
        Item(nutrient: .sodium, identifier: "HKQuantityTypeIdentifierDietarySodium", unit: "mg"),
        Item(nutrient: .potassium, identifier: "HKQuantityTypeIdentifierDietaryPotassium", unit: "mg"),
        Item(nutrient: .calcium, identifier: "HKQuantityTypeIdentifierDietaryCalcium", unit: "mg"),
        Item(nutrient: .iron, identifier: "HKQuantityTypeIdentifierDietaryIron", unit: "mg"),
        Item(nutrient: .magnesium, identifier: "HKQuantityTypeIdentifierDietaryMagnesium", unit: "mg"),
        Item(nutrient: .zinc, identifier: "HKQuantityTypeIdentifierDietaryZinc", unit: "mg"),
        Item(nutrient: .vitaminA, identifier: "HKQuantityTypeIdentifierDietaryVitaminA", unit: "mcg"),
        Item(nutrient: .vitaminC, identifier: "HKQuantityTypeIdentifierDietaryVitaminC", unit: "mg"),
        Item(nutrient: .vitaminD, identifier: "HKQuantityTypeIdentifierDietaryVitaminD", unit: "mcg"),
        Item(nutrient: .vitaminE, identifier: "HKQuantityTypeIdentifierDietaryVitaminE", unit: "mg"),
        Item(nutrient: .vitaminB12, identifier: "HKQuantityTypeIdentifierDietaryVitaminB12", unit: "mcg"),
        Item(nutrient: .folate, identifier: "HKQuantityTypeIdentifierDietaryFolate", unit: "mcg"),
        Item(nutrient: .caffeine, identifier: "HKQuantityTypeIdentifierDietaryCaffeine", unit: "mg"),
    ]

    public static let waterIdentifier = "HKQuantityTypeIdentifierDietaryWater"

    /// Sync identifier for an entry's food correlation: HealthKit replaces the sample when the
    /// same identifier comes with a higher version, so edits never duplicate.
    public static func syncIdentifier(entry: UUID) -> String { "nina.entry.\(entry.uuidString)" }
    public static func syncIdentifier(water: UUID) -> String { "nina.water.\(water.uuidString)" }
    /// A weigh-in's body-mass sample: the same on every device, so iPhone and iPad never write it twice.
    public static func syncIdentifier(weight: UUID) -> String { syncIdentifier(weightID: weight.uuidString) }
    /// The same from the weigh-in's uuid text (`HealthWeightSync.Item.id`).
    public static func syncIdentifier(weightID: String) -> String { "nina.weight.\(weightID)" }

    /// A version that grows with every edit (seconds since 2001 of the last change).
    public static func syncVersion(modifiedAt: Date) -> Int {
        max(1, Int(modifiedAt.timeIntervalSinceReferenceDate))
    }
}
