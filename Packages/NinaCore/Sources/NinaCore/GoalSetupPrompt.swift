import Foundation

/// The "Set your goal" card on Today for people who haven't told Nina about themselves yet: it
/// shows while no coach plan is set up and either the targets are still Nina's starting values
/// (`DailyTargets.standard`, no training-day targets) or the profile has no body data (birth year
/// and height). It opens Goals & Plan. "Not now" hides it for 7 days, "Don't show again" for good;
/// both are kept on the device only (never synced).
public enum GoalSetupPrompt {
    /// Why the card shows (its message follows it).
    public enum Reason: String, Equatable, Sendable {
        /// The calorie and macro targets are still the starting values.
        case standardTargets
        /// Own targets, but no birth year or height: body numbers and the calculator can't work.
        case missingBody
    }

    /// "Not now" hides the card for this many days.
    public static let snoozeDays = 7

    /// Why the card shows; nil when it doesn't (a set-up plan, or own targets and body data).
    public static func reason(planIsSetUp: Bool, targets: DailyTargets, trainingTargets: DailyTargets?, hasBody: Bool) -> Reason? {
        guard !planIsSetUp else { return nil }
        if trainingTargets == nil, isStandard(targets) { return .standardTargets }
        return hasBody ? nil : .missingBody
    }

    /// Calories and macros are the starting values (water, fibre and the limits don't count: changing
    /// only the water goal is no goal yet).
    public static func isStandard(_ targets: DailyTargets) -> Bool {
        let standard = DailyTargets.standard
        let pairs: [(Double, Double)] = [(targets.energy, standard.energy), (targets.protein, standard.protein),
                                         (targets.carbs, standard.carbs), (targets.fat, standard.fat)]
        return pairs.allSatisfy { abs($0.0 - $0.1) < 0.5 }
    }

    /// What the person chose on the card, stored as text in the device's settings.
    public enum Dismissal: Equatable, Sendable {
        /// Nothing chosen: the card shows when it applies.
        case none
        /// "Not now": hidden before this day.
        case until(DayKey)
        /// "Don't show again".
        case forever

        static let foreverText = "never"

        /// From the stored text ("" or unreadable = none).
        public init(stored: String) {
            let text = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            if text == Dismissal.foreverText {
                self = .forever
            } else if let day = DayKey(text) {
                self = .until(day)
            } else {
                self = .none
            }
        }

        /// The text to store.
        public var stored: String {
            switch self {
            case .none: return ""
            case .until(let day): return day.rawValue
            case .forever: return Dismissal.foreverText
            }
        }

        /// "Not now" tapped on `today`: back on the 7th day after.
        public static func notNow(today: DayKey, calendar: Calendar = .current) -> Dismissal {
            .until(today.adding(days: GoalSetupPrompt.snoozeDays, calendar: calendar))
        }

        /// The card stays hidden on `today`.
        public func hides(on today: DayKey) -> Bool {
            switch self {
            case .none: return false
            case .until(let day): return today < day
            case .forever: return true
            }
        }
    }

    /// The card shows on `today`: it applies and wasn't put away.
    public static func isVisible(_ reason: Reason?, dismissal: Dismissal, today: DayKey) -> Bool {
        reason != nil && !dismissal.hides(on: today)
    }
}
