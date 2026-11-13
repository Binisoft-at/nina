import Foundation

/// Averages, streaks, patterns and trends over a period. Everything is computed on the device
/// from the diary; nothing is stored.
public enum Insights {
    /// Current streak (days in a row with something eaten, ending today or yesterday) and the best one.
    public static func streaks(logged: Set<DayKey>, today: DayKey, calendar: Calendar = .current) -> (current: Int, best: Int) {
        guard !logged.isEmpty else { return (0, 0) }
        var current = 0
        var day = logged.contains(today) ? today : today.adding(days: -1, calendar: calendar)
        while logged.contains(day) {
            current += 1
            day = day.adding(days: -1, calendar: calendar)
        }
        var best = 0
        var run = 0
        var previous: DayKey?
        for day in logged.sorted() {
            if let previous, previous.adding(days: 1, calendar: calendar) == day {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return (current, max(best, current))
    }

    public struct PeriodStats: Equatable, Sendable {
        public var days: Int
        public var loggedDays: Int
        /// Average per logged day.
        public var average: NutrientValues
        public var averageWater: Double
        /// Average energy target over the logged days.
        public var averageTarget: Double
        /// Share of logged days within ±10 % of the energy target.
        public var onTrackShare: Double
        public var overDays: Int
        public var underDays: Int
        public var macroShares: MacroShares
        /// ISO weekday (1 = Monday) → average kcal on logged days.
        public var byWeekday: [Int: Double]
        /// Average minutes after midnight of the first and last eaten entry.
        public var firstMealMinutes: Int?
        public var lastMealMinutes: Int?

        /// Average daily difference to the target (negative = below).
        public var averageBalance: Double { average.energy - averageTarget }
    }

    /// - Parameters:
    ///   - totals: one value per day of the period (unlogged days included, they are skipped).
    ///   - targets: the targets that applied on a day.
    ///   - mealTimes: first and last eaten time per day (minutes after midnight).
    public static func stats(totals: [DayTotals], targets: (DayKey) -> DailyTargets,
                             mealTimes: [DayKey: (first: Int, last: Int)] = [:], calendar: Calendar = .current) -> PeriodStats {
        let logged = totals.filter(\.isLogged)
        let count = Double(max(logged.count, 1))
        let sum = NutrientValues.sum(logged.map(\.eaten))
        let average = sum.scaled(by: 1 / count)
        var onTrack = 0, over = 0, under = 0
        var targetSum = 0.0
        var weekdaySums: [Int: (Double, Int)] = [:]
        for day in logged {
            let target = targets(day.day)
            targetSum += target.energy
            let progress = DayProgress(totals: day, targets: target)
            switch progress.verdict {
            case .onTrack: onTrack += 1
            case .over: over += 1
            case .under: under += 1
            }
            let weekday = day.day.weekday(calendar: calendar)
            let current = weekdaySums[weekday] ?? (0, 0)
            weekdaySums[weekday] = (current.0 + day.eaten.energy, current.1 + 1)
        }
        let times = logged.compactMap { mealTimes[$0.day] }
        let first = times.isEmpty ? nil : times.map(\.first).reduce(0, +) / times.count
        let last = times.isEmpty ? nil : times.map(\.last).reduce(0, +) / times.count
        return PeriodStats(
            days: totals.count,
            loggedDays: logged.count,
            average: average,
            averageWater: logged.isEmpty ? 0 : logged.map(\.water).reduce(0, +) / count,
            averageTarget: logged.isEmpty ? 0 : targetSum / count,
            onTrackShare: logged.isEmpty ? 0 : Double(onTrack) / count,
            overDays: over,
            underDays: under,
            macroShares: sum.macroShares,
            byWeekday: weekdaySums.mapValues { $0.1 > 0 ? $0.0 / Double($0.1) : 0 },
            firstMealMinutes: first,
            lastMealMinutes: last
        )
    }

    public struct FoodRank: Equatable, Sendable, Identifiable {
        public var id: String { key }
        /// Food reference, or the lower-cased name for entries without one.
        public var key: String
        public var name: String
        public var category: FoodCategory
        public var count: Int
        public var total: NutrientValues
    }

    /// The foods eaten most often (or contributing most of a nutrient).
    public static func topFoods(_ entries: [EntryFacts], by nutrient: Nutrient? = nil, limit: Int = 10) -> [FoodRank] {
        var ranks: [String: FoodRank] = [:]
        for entry in entries where entry.status == .eaten {
            let key = entry.foodRef.isEmpty ? "name:" + SearchText.normalize(entry.name) : entry.foodRef.rawValue
            var rank = ranks[key] ?? FoodRank(key: key, name: entry.name, category: entry.category, count: 0, total: NutrientValues())
            rank.count += 1
            rank.total += entry.nutrients
            ranks[key] = rank
        }
        let sorted = ranks.values.sorted { lhs, rhs in
            if let nutrient {
                let l = lhs.total.value(nutrient), r = rhs.total.value(nutrient)
                if l != r { return l > r }
            }
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.name < rhs.name
        }
        return Array(sorted.prefix(limit))
    }

    /// Exponentially smoothed weight (the "trend weight"), one value per day from the first
    /// weigh-in to `through`; days without a weigh-in carry the trend forward.
    public static func weightTrend(_ weights: [DayKey: Double], through end: DayKey, smoothing alpha: Double = 0.1,
                                   calendar: Calendar = .current) -> [(day: DayKey, weight: Double, trend: Double?)] {
        guard let first = weights.keys.min() else { return [] }
        var trend: Double?
        var result: [(day: DayKey, weight: Double, trend: Double?)] = []
        for day in DayKey.range(first, through: max(end, first), calendar: calendar) {
            if let weight = weights[day] {
                trend = trend.map { $0 + alpha * (weight - $0) } ?? weight
                result.append((day, weight, trend))
            } else if let current = trend {
                result.append((day, .nan, current))
            }
        }
        return result
    }

    public struct Maintenance: Equatable, Sendable {
        /// Estimated kcal per day at which the weight would stay the same.
        public var kilocalories: Double
        public var averageIntake: Double
        /// Trend change over the window (negative = lost).
        public var weightChange: Double
        public var days: Int
        public var loggedDays: Int
        public var confidence: Confidence

        public enum Confidence: String, Sendable { case low, medium, high }
    }

    /// Your measured maintenance calories: average intake minus the energy the weight trend
    /// says was stored or burned (7,700 kcal per kg). Needs ≥ 14 days with weigh-ins at both
    /// ends of the window and ≥ 10 logged days.
    public static func maintenance(totals: [DayTotals], weights: [DayKey: Double], window: Int = 28,
                                   today: DayKey, calendar: Calendar = .current) -> Maintenance? {
        let start = today.adding(days: -(window - 1), calendar: calendar)
        let inWindow = totals.filter { $0.day >= start && $0.day <= today }
        let logged = inWindow.filter { $0.isLogged }
        guard logged.count >= 10 else { return nil }
        let windowWeights = weights.filter { $0.key >= start.adding(days: -14, calendar: calendar) && $0.key <= today }
        let trend = weightTrend(windowWeights, through: today, smoothing: 0.15, calendar: calendar)
        let points = trend.filter { $0.day >= start }
        guard let firstPoint = points.first, let lastPoint = points.last, let startTrend = firstPoint.trend, let endTrend = lastPoint.trend else { return nil }
        let span = firstPoint.day.days(to: lastPoint.day, calendar: calendar)
        let weighIns = windowWeights.filter { $0.key >= start }.count
        guard span >= 14, weighIns >= 3 else { return nil }
        let averageIntake = logged.map(\.eaten.energy).reduce(0, +) / Double(logged.count)
        let change = endTrend - startTrend
        let estimate = averageIntake - change * GoalCalculator.kilocaloriesPerKilogram / Double(span)
        let confidence: Maintenance.Confidence
        if logged.count >= 21, weighIns >= 10 { confidence = .high }
        else if logged.count >= 14, weighIns >= 5 { confidence = .medium }
        else { confidence = .low }
        return Maintenance(kilocalories: (estimate / 10).rounded() * 10, averageIntake: averageIntake, weightChange: change,
                           days: span, loggedDays: logged.count, confidence: confidence)
    }
}
