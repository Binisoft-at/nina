import Foundation

/// The ⓘ texts of logging: typing a whole meal (`QuickParser`), the Recent list sorted for the
/// meal (`RecentFoods`), the amount and the entry's status. Plain strings (no SwiftUI).
enum LogInfo {
    /// One ⓘ: a few words and one or two short sentences.
    struct Note: Equatable {
        let title: String
        let text: String
    }

    /// "Understood": what quick add reads from a typed line.
    static let quickAdd = Note(
        title: "Typing a whole meal",
        text: "Write each food with its amount, like \u{201C}200 g chicken, 2 eggs and a toast\u{201D} – separate foods "
            + "with commas, \u{201C}and\u{201D} or new lines. German names work too, and \u{201C}350 kcal\u{201D} logs just calories."
    )

    /// "Mostly at breakfast": the foods usually logged at the meal come first.
    static func mostlyAt(_ hint: String) -> Note {
        Note(title: hint,
             text: "Foods you usually have at this meal come first – logged here at least twice, the last time within "
                 + "60 days. Below them is everything else you logged lately, newest first.")
    }

    /// "Recent" while no food leads for the meal yet.
    static let recent = Note(
        title: "Recent",
        text: "The foods you logged lately, newest first. Foods you have at one meal again and again move to the top "
            + "when you log that meal."
    )

    /// The amount of a food (logging and editing an entry).
    static let amount = Note(
        title: "Amount",
        text: "Choose a portion such as \u{201C}1 medium\u{201D} (its weight is in brackets), or switch to g or ml and type "
            + "what you weighed – weighing is the most exact. Everything below follows the amount."
    )

    /// Eaten, planned or skipped.
    static let status = Note(
        title: "Status",
        text: "Eaten counts toward the day. Planned shows dimmed and counts once you mark it eaten; Skipped stays in the "
            + "diary but counts nowhere."
    )
}
