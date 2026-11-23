import SwiftUI
import NinaCore

/// The ⓘ texts of Settings (`InfoButton`: a title and one or two short sentences). English, except
/// the Thalia section, which is German like the rest of it.
enum SettingsInfo {
    typealias Item = CheckInSheetInfo.Item

    static let foodNames: Item = (
        title: "Food names",
        text: "The language of the built-in foods' names. Search finds them in English and German either way, and Austrian names like Paradeiser or Topfen work too."
    )

    static let dayStart: Item = (
        title: "Day starts at",
        text: "For late nights: until this hour, what you log still counts for the day before, so a midnight snack stays with its evening. Today moves on to the new day at this time."
    )

    static var waterGlass: Item {
        #if os(macOS)
        let text = "How much the +Water button on Today adds with one click – the same in the menu bar and with Add a Glass of Water (⌃⌘W)."
        #else
        let text = "How much the +Water button adds with one tap – on Today, on your Apple Watch and when you ask Siri to log water."
        #endif
        return (title: "Water glass", text: text)
    }

    static let macroSplit: Item = (
        title: "Macro split",
        text: "How your calories are shared between protein, carbs and fat: 25/45/30 means 25 % from protein, 45 % from carbs and 30 % from fat. It's a starting point – you can change every target by hand."
    )

    static let activeEnergy: Item = (
        title: "Active energy",
        text: "What you burn by moving, as Apple Health counts it from your iPhone or Apple Watch. Nina adds this share of it to today's calorie budget."
    )

    static let bodyData: Item = (
        title: "Body data from Health",
        text: "Body fat, lean mass and waist from your scale or another app show next to what you measure in Nina, each as its own series. They're read live from Apple Health and never saved in Nina or its iCloud."
    )

    static let workouts: Item = (
        title: "Workouts",
        text: "When today is your default day type and Apple Health has a finished workout that one of your day types lists – tennis, for example – Today asks whether to switch. Only your tap changes the day."
    )

    /// The footer lists the quiet hours; this says what the reminders are and which device sends them.
    static var coachReminders: Item {
        let morning = Fmt.clock(CoachReminders.morningUntilMinutes)
        return (title: "Coach reminders",
                text: "Nudges from your plan: the morning weigh-in, daily checks, the evening before a full measurement, the check-in and phase days. Early checks share the morning reminder, so there's only one before \(morning). Your iPhone sends them (your Apple Watch shows them too); iPad and Mac only when switched on there.")
    }

    /// Settings → Menu Bar (Mac only).
    static let menuBar: Item = (
        title: "Menu bar",
        text: "The number next to Nina's icon is what's left of today's calories – the same as Today's ring. You can also ⌘-drag the icon out of the menu bar; that turns Show in menu bar off."
    )

    /// German, like the Thalia section (the owner's choice).
    static let thalia: Item = (
        title: "Thalia",
        text: "Nina gibt Thalia, dem Planer von Binisoft, die Tageswerte: Kalorien, Protein, Kohlenhydrate, Fett, Wasser und das Morgengewicht – nie etwas aus Apple Health. Der Schalter gilt für alle Geräte."
    )
}

/// A settings row whose title carries an ⓘ, with the control (its label hidden, so VoiceOver
/// still reads it) on the trailing side. Used for pickers, whose own label row may open the menu.
struct SettingsInfoRow<Control: View>: View {
    let title: String
    let info: SettingsInfo.Item
    let control: Control

    init(_ title: String, info: SettingsInfo.Item, @ViewBuilder control: () -> Control) {
        self.title = title
        self.info = info
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .info(info.title, info.text)
            Spacer(minLength: 8)
            control
                .labelsHidden()
                .fixedSize()
        }
    }
}
