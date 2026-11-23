import Foundation

/// Which planned meals ask "Lunch planned – eaten?" and when "Lunch logged?" still comes
/// (the iPhone's meal notifications; the app builds the requests).
public enum MealPromptRules {
    /// The routine of a planned entry's key ("rule:<uuid>:<day>", `PlanSchedule.key`); nil for a
    /// plan made by hand.
    public static func ruleID(planKey: String) -> String? {
        let parts = planKey.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts[0] == "rule", !parts[1].isEmpty else { return nil }
        return String(parts[1])
    }

    /// A planned entry asks "eaten?": planned by hand, or by a routine that is on and asks
    /// (`asking`: the ids of active routines with "Remind me" on). A paused, deleted or silent
    /// routine's planned meals don't ask.
    public static func asks(planKey: String, asking: Set<String>) -> Bool {
        guard planKey.hasPrefix("rule:") else { return true }
        guard let rule = ruleID(planKey: planKey) else { return false }
        return asking.contains(rule)
    }

    /// "Lunch logged?" still stands for a meal: nothing eaten in it, and no planned prompt of its
    /// own asks about it.
    public static func remindsAbout(meal: String, eaten: Set<String>, prompted: Set<String>) -> Bool {
        !eaten.contains(meal) && !prompted.contains(meal)
    }
}
