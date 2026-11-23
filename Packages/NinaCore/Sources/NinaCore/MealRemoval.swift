import Foundation

/// Deleting an own meal (Settings → Meals) that entries or routines still use: they can move to
/// Snacks, or stay as they are (the diary then lists them under "Other meal"). The texts of that
/// question; the app counts and moves (MealsSettingsView).
public struct NinaMealRemoval: Equatable, Sendable {
    /// The meal being deleted.
    public var slot: MealSlot
    /// Entries (eaten and planned, not in Recently Deleted) in that meal.
    public var entries: Int
    /// Routines that plan into that meal.
    public var routines: Int
    /// Where they can move: Snacks under its current name.
    public var target: MealSlot

    public init(slot: MealSlot, entries: Int, routines: Int, meals: [MealSlot]) {
        self.slot = slot
        self.entries = entries
        self.routines = routines
        target = meals.first { $0.id == MealSlot.snack.id } ?? .snack
    }

    /// Nothing uses the meal: it goes without a question (its toast has Undo).
    public var isUsed: Bool { entries + routines > 0 }

    /// "12 entries and 1 routine".
    public var usage: String {
        var parts: [String] = []
        if entries > 0 { parts.append(entries == 1 ? "1 entry" : "\(entries) entries") }
        if routines > 0 { parts.append(routines == 1 ? "1 routine" : "\(routines) routines") }
        return parts.joined(separator: " and ")
    }

    /// "12 entries and 1 routine use “Jause”."
    public var question: String {
        let verb = entries + routines == 1 ? "uses" : "use"
        return "\(usage) \(verb) \u{201C}\(Self.name(slot))\u{201D}."
    }

    /// "Move Them to Snacks" (a button).
    public var moveTitle: String {
        let them = entries + routines == 1 ? "It" : "Them"
        return "Move \(them) to \(Self.name(target))"
    }

    /// "Keep Them as They Are" (a button).
    public var keepTitle: String {
        entries + routines == 1 ? "Keep It as It Is" : "Keep Them as They Are"
    }

    /// What happens with each choice, under the question.
    public var detail: String {
        "Kept entries show under \u{201C}Other meal\u{201D}."
    }

    /// The toast after deleting: "Deleted “Jause”", plus where its entries went.
    public func toast(moved: Bool) -> String {
        let deleted = "Deleted \u{201C}\(Self.name(slot))\u{201D}"
        guard isUsed, moved else { return deleted }
        return "\(deleted) · \(usage) moved to \(Self.name(target))"
    }

    /// The meal's name, or "Meal" when it was left empty.
    static func name(_ slot: MealSlot) -> String {
        let trimmed = slot.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Meal" : trimmed
    }
}
