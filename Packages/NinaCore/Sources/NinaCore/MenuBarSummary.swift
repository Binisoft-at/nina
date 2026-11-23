import Foundation

/// What Nina's menu bar extra on the Mac shows for the diary day (Settings → "Show in menu bar"):
/// the calories left or over, protein against its target and the water. Built from `DayProgress`,
/// so it says what Today says – eaten food only, planned food doesn't count yet. (The Mac reads
/// nothing from Apple Health, so there is no activity bonus in it.)
public struct NinaMenuBarSummary: Equatable, Sendable {
    /// Whole kcal left; negative when over. Without a calorie target: what was eaten, negative.
    public var energyLeft: Double
    /// The day's calorie target (with the plan's day type).
    public var energyTarget: Double
    public var protein: Double
    public var proteinTarget: Double
    /// ml.
    public var water: Double
    public var waterTarget: Double
    /// The day type's emoji ("🎾"), in front of the calories in the menu; nil without one.
    public var emoji: String?

    public init(progress: DayProgress, emoji: String? = nil) {
        let remaining = progress.energyRemaining
        energyLeft = remaining.isFinite ? remaining.rounded() : 0
        energyTarget = max(0, progress.energyBudget)
        protein = max(0, progress.totals.eaten.protein)
        proteinTarget = max(0, progress.targets.protein)
        water = max(0, progress.totals.water)
        waterTarget = max(0, progress.targets.water)
        let mark = emoji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.emoji = mark.isEmpty ? nil : mark
    }

    /// More eaten than the target allows (a rounded 0 left is not over).
    public var isOver: Bool { hasEnergyTarget && energyLeft < 0 }

    public var hasEnergyTarget: Bool { energyTarget > 0 }

    /// Next to the icon in the menu bar: "1,234 left", "150 over" (no target: "1,234 kcal").
    public var title: String {
        guard hasEnergyTarget else { return "\(DisplayNumber.grouped(-energyLeft)) kcal" }
        return isOver ? "\(DisplayNumber.grouped(-energyLeft)) over" : "\(DisplayNumber.grouped(energyLeft)) left"
    }

    /// The menu's first line: "🎾 1,234 kcal left today", "150 kcal over today" (no target:
    /// "1,234 kcal eaten today").
    public var energyLine: String {
        guard let emoji else { return energyText }
        return "\(emoji) \(energyText)"
    }

    /// The first line without the emoji.
    private var energyText: String {
        if !hasEnergyTarget { return "\(DisplayNumber.grouped(-energyLeft)) kcal eaten today" }
        if isOver { return "\(DisplayNumber.grouped(-energyLeft)) kcal over today" }
        return "\(DisplayNumber.grouped(energyLeft)) kcal left today"
    }

    /// "Protein 85 of 140 g" ("Protein 85 g" without a target).
    public var proteinLine: String {
        let eaten = DisplayNumber.grouped(protein)
        guard proteinTarget > 0 else { return "Protein \(eaten) g" }
        return "Protein \(eaten) of \(DisplayNumber.grouped(proteinTarget)) g"
    }

    /// "Water 750 of 2,000 ml" ("Water 750 ml" without a target).
    public var waterLine: String {
        let drunk = DisplayNumber.grouped(water)
        guard waterTarget > 0 else { return "Water \(drunk) ml" }
        return "Water \(drunk) of \(DisplayNumber.grouped(waterTarget)) ml"
    }

    /// VoiceOver on the menu bar icon: "Nina, 1,234 kcal left today".
    public func accessibilityLabel(appName: String) -> String {
        "\(appName), \(energyText)"
    }
}
