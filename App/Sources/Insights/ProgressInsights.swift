import Foundation
import NinaCore

// The parts of Insights (Progress → Nutrition) that come from the coach plan: protein meals over
// the period (F9), the average by day type (F3) and the compact body goal (F8). Foundation and
// NinaCore only; the cards are in ProgressInsightsCards.swift.

/// Protein meals in the period: "Protein meals 21 of 28", a meal counting from `minimum` g.
struct ProgressProteinMeals {
    let period: ProteinMeals.Period
    /// g of protein from which a meal counts.
    let minimum: Double
}

/// One day type's average over the period: "🏋️ Gym · 12 days · 2,410 / 2,500 kcal".
struct ProgressTypeAverage: Identifiable {
    let id: String
    let name: String
    let emoji: String
    /// Logged days of this type in the period.
    let days: Int
    let averageIntake: Double
    let averageTarget: Double

    /// Eaten ÷ target (0 without a target).
    var share: Double { averageTarget > 0 ? averageIntake / averageTarget : 0 }
    /// Within the day-adherence band of the target (±10 % or ±150 kcal, whichever is larger).
    var isInBand: Bool { Adherence.isInKcalBand(eaten: averageIntake, target: averageTarget) }
    var isOver: Bool { !isInBand && averageIntake > averageTarget }
}

@MainActor
enum ProgressInsights {
    /// Protein meals over the logged, not paused days of `totals`; nil when Today shows no
    /// protein pills (no plan and no per-meal minimum) or nothing is tracked.
    static func proteinMeals(totals: [DayTotals], settings: NinaSettings) -> ProgressProteinMeals? {
        guard let rule = settings.todayCoachProteinRule else { return nil }
        let plan = settings.plan
        let days: [ProteinMeals.Day] = totals.filter { $0.isLogged && !plan.isPaused(on: $0.day) }
            .map { ProteinMeals.day($0, rule: rule) }
        let period = ProteinMeals.period(days)
        guard period.target > 0 else { return nil }
        return ProgressProteinMeals(period: period, minimum: rule.minimum)
    }

    /// Average eaten vs. average target per day type over the logged, not paused days of
    /// `totals`, in plan order. Only with 2 or more day types; types without a logged day are
    /// left out.
    static func typeAverages(totals: [DayTotals], settings: NinaSettings, calendar: Calendar = .current) -> [ProgressTypeAverage] {
        let plan = settings.plan
        guard plan.isSetUp, plan.dayTypes.count >= 2 else { return [] }
        let days: [DayAdherence] = totals.map { total in
            DayAdherence(totals: total, targets: settings.targets(for: total.day, calendar: calendar),
                         dayTypeID: settings.dayType(for: total.day, calendar: calendar)?.id,
                         isPaused: plan.isPaused(on: total.day), calendar: calendar)
        }
        let summary = Adherence.summary(days, plan: plan)
        return summary.byType.compactMap { average -> ProgressTypeAverage? in
            guard average.loggedDays > 0, let type = plan.dayType(id: average.typeID) else { return nil }
            return ProgressTypeAverage(id: type.id, name: type.name.isEmpty ? "Day type" : type.name,
                                       emoji: type.todayCoachEmoji, days: average.loggedDays,
                                       averageIntake: average.averageIntake, averageTarget: average.averageTarget)
        }
    }

    /// The body goal as the Body page shows it (lean mass, fat mass, body fat), for the compact
    /// card; nil without a set-up plan with a long-term goal.
    static func goal(app: AppModel) -> BodyPageGoal? {
        let plan = app.settings.plan
        guard plan.isSetUp, plan.longTerm.isSet else { return nil }
        let context = CoachContext.load(app: app, day: app.today)
        let heightCm = app.store.profile()?.heightCm ?? 0
        let composition = BodyPageData.composition(context, heightCm: heightCm)
        return BodyPageData.goal(context, points: composition.trackingPoints, seriesTitle: composition.page.latestTitle)
    }
}
