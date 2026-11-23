import Foundation
import NinaCore

// The ⓘ texts of Nutrition (Progress → Nutrition, the Mac's Nutrition): by day type, protein
// meals, consistency and the measured maintenance. Numbers come from the rules that compute them.
// Foundation and NinaCore only; `BodyPageInfo` and the views are in App/Sources/Coach/BodyPageInfo*.swift.

extension BodyPageInfo {
    /// "By day type": each type against its own target, on target within the day band.
    static let byDayType = BodyPageInfo(
        title: "By day type",
        text: "Each day type has its own calorie target, so a training day and a rest day are judged on their own. A bar "
            + "is on target within \(DisplayNumber.plain(Adherence.kcalBandShare * 100, decimals: 0)) % or "
            + "\(DisplayNumber.plain(Adherence.kcalBandMinimum, decimals: 0)) kcal of it, whichever is more.")

    /// Protein meals: `minimum` is the protein (g, already formatted: "35 g") from which a meal counts.
    static func proteinMeals(minimum: String) -> BodyPageInfo {
        BodyPageInfo(
            title: "Protein meals",
            text: "Meals with at least \(minimum) of protein, out of the protein meals you aim for on these days. A meal "
                + "counts once however big it is, so spreading protein over the day fills it.")
    }

    /// Consistency: the streak and the on-track share (within ±10 % of the day's goal, `DayProgress`).
    static let consistency = BodyPageInfo(
        title: "Consistency",
        text: "Streak: days in a row with something eaten, up to today or yesterday. On track: logged days within 10 % "
            + "of that day's calorie goal.")

    /// The measured maintenance (`Insights.maintenance`, the 28 days through yesterday).
    static let maintenance = BodyPageInfo(
        title: "Measured maintenance",
        text: "The calories that would keep your weight steady, worked out from what you logged and how your morning "
            + "weights moved over the last four weeks. The more days you log, the surer it gets.")
}
