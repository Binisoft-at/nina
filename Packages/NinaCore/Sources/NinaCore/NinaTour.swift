import Foundation
import BinisoftKitCore

/// What the tour's practice day looks like right now (built from the demo store after every change).
public struct NinaTourSnapshot: Equatable, Sendable {
    public var eatenCount = 0
    public var plannedCount = 0
    public var trashedCount = 0
    /// Entries per meal, e.g. "breakfast:2|lunch:1" – changes when something moves to another meal.
    public var mealLayout = ""
    public var water = 0.0
    public var favoriteCount = 0
    public var isCreateOpen = false
    public var isAddOpen = false
    public var isQuickAddOpen = false
    /// Today's day type id ("" without a plan): changes when a type is picked on the chip.
    public var dayType = ""
    /// Days other than today with a day type picked by hand (the week strip's menu).
    public var plannedDayTypes = 0
    /// Daily checks ticked done.
    public var checksDone = 0
    /// Body measurements saved (tape and body fat).
    public var measureCount = 0
    /// Weigh-ins saved in Nina.
    public var weighIns = 0

    public init() {}
}

/// Nina's interactive tour. To teach a new feature: add a step with `since: version + 1` and bump
/// `version`; people who already took the tour then get just the new steps as "What's new".
/// `swift test` checks the catalog.
public enum NinaTour {
    public static let version = 6

    public static let catalog = TourCatalog<NinaTourSnapshot>.standard(
        appName: "Nina",
        version: version,
        practiceNoun: "diary",
        replayHint: "Settings or Help → Nina Tour",
        steps: [
            TourStep(
                id: "create", symbol: "plus.circle", title: "Everything starts at Create",
                body: "Tap ⋯ at the top, then Create…: foods, quick entries, meals, recipes, water, weight – and importing the data you already have.",
                macBody: "Click Create in the toolbar or press ⇧⌘N: foods, quick entries, meals, recipes, water, weight – and importing the data you already have.",
                goal: .isTrue(\.isCreateOpen)
            ),
            TourStep(
                id: "setup-ai", since: 2, symbol: "sparkles", title: "Let your AI set Nina up",
                body: "In ⋯ → Create… → Import My Data, tap Copy the Setup Prompt. Paste it into ChatGPT or Claude with a few lines about you and the foods you eat, then paste its answer back: your goal, daily targets, meal times, foods and usual meals are set in one go – with a preview first.",
                macBody: "In Create → Import My Data, click Copy the Setup Prompt. Paste it into ChatGPT or Claude with a few lines about you and the foods you eat, then paste its answer back: goal, targets, meal times, foods and meals are set in one go – with a preview first.",
                goal: .none
            ),
            TourStep(
                id: "log", symbol: "magnifyingglass", title: "Log a food",
                body: "Tap + next to Breakfast, search for \u{201C}banana\u{201D} (or \u{201C}Banane\u{201D}) and tap the + next to it. Nina knows about 1,000 everyday foods in English and German.",
                macBody: "Click + next to Breakfast (or press ⌘N), search for \u{201C}banana\u{201D} and press Return. Nina knows about 1,000 everyday foods in English and German.",
                goal: .increased(\.eatenCount)
            ),
            TourStep(
                id: "quick", symbol: "text.bubble", title: "Type it like a message",
                body: "In the same search field, write \u{201C}2 eggs, 1 toast and 200 ml milk\u{201D}. Nina understands amounts and units (also \u{201C}10 dag Extrawurst\u{201D} or \u{201C}ein Achtel Rotwein\u{201D}) and logs everything at once.",
                macBody: "In the search field, write \u{201C}2 eggs, 1 toast and 200 ml milk\u{201D} and press Return. Nina understands amounts and units and logs everything at once.",
                goal: .increased(\.eatenCount)
            ),
            TourStep(
                id: "recentsPerMeal", since: 6, symbol: "clock.arrow.circlepath", title: "Recents for this meal",
                body: "When you log, the foods you usually have at that meal come first – under \u{201C}Mostly at breakfast\u{201D}. Everything else you logged lately follows, newest first. Change the meal at the top and the list follows – on your Apple Watch too.",
                macBody: "When you log (⌘N), the foods you usually have at that meal come first – under \u{201C}Mostly at breakfast\u{201D}. Everything else you logged lately follows, newest first. Change the meal at the top and the list follows.",
                goal: .none
            ),
            TourStep(
                id: "undo", symbol: "arrow.uturn.backward", title: "Mistakes are fine",
                body: "Swipe left on an entry and tap Delete, then tap Undo in the message. Shaking your iPhone undoes the last change too.",
                macBody: "Right-click an entry and choose Delete, then click Undo in the message – or press ⌘Z.",
                goal: .undone(\.trashedCount)
            ),
            TourStep(
                id: "move", symbol: "arrow.left.arrow.right", title: "Wrong meal? Move it",
                body: "Touch and hold an entry → Move to → Lunch. You can also drag entries between meals, or swipe right to log it again.",
                macBody: "Right-click an entry → Move to → Lunch, or drag it onto another meal.",
                goal: .changed(\.mealLayout)
            ),
            TourStep(
                id: "plan", symbol: "checklist", title: "Plan, then just confirm",
                body: "Dimmed entries are planned. Tap the circle next to the planned dinner when you've eaten it – that's all the logging it needs.",
                macBody: "Dimmed entries are planned. Click the circle next to the planned dinner when you've eaten it – that's all the logging it needs.",
                goal: .decreased(\.plannedCount)
            ),
            TourStep(
                id: "water", symbol: "drop.fill", title: "Water in one tap",
                body: "Tap the glass in the water card to add 250 ml. Touch and hold it for other amounts.",
                macBody: "Click the glass in the water card to add 250 ml. Right-click it for other amounts.",
                goal: .increased(\.water)
            ),
            TourStep(
                id: "daytype", since: 3, symbol: "figure.strengthtraining.traditional", title: "Your day type",
                body: "With a plan, the chip on the summary card says what kind of day today is – Gym, Tennis or Rest – and today's targets follow it. Tap the chip and pick Tennis.",
                macBody: "With a plan, the chip on the summary card says what kind of day today is – Gym, Tennis or Rest – and today's targets follow it. Click the chip and choose Tennis, or use Day → Day Type (⌃⌘1 to ⌃⌘4).",
                goal: .changed(\.dayType)
            ),
            TourStep(
                id: "plan-ahead", since: 3, symbol: "calendar", title: "Plan ahead",
                body: "Tennis on Thursday? Touch and hold that day in the week strip and pick its type. Its targets are ready when the day comes.",
                macBody: "Tennis on Thursday? Right-click that day in the week strip and choose its type. Its targets are ready when the day comes.",
                goal: .increased(\.plannedDayTypes)
            ),
            TourStep(
                id: "planDayTypes", since: 6, symbol: "calendar.day.timeline.left", title: "Day types in Plan",
                body: "In the Plan tab, each of the next 7 days shows its day type's emoji on the right. Tap it to make that day a Gym, Tennis or Rest day – Back to Schedule undoes it, and every change has Undo.",
                macBody: "In Plan (⌘4), each of the next 7 days shows its day type's emoji on the right. Click it (or right-click the day → Day Type) to change that day's type – Back to Schedule undoes it, and every change has Undo.",
                goal: .none
            ),
            TourStep(
                id: "checks", since: 3, symbol: "pills", title: "Daily checks",
                body: "What your plan asks for every day – creatine, say – sits in the strip under the summary. Tap Creatine to tick it off. Touch and hold it for Not Today.",
                macBody: "What your plan asks for every day – creatine, say – sits in the strip under the summary. Click Creatine to tick it off. Right-click it for Not Today.",
                goal: .increased(\.checksDone)
            ),
            TourStep(
                id: "protein", since: 3, symbol: "fork.knife", title: "Protein per meal",
                body: "With a protein minimum in your plan, each meal header shows a pill like 17 / 25 g. It fills once the meal has enough. When you add food, search says what's missing: +8 g protein to reach 25.",
                macBody: "With a protein minimum in your plan, each meal header shows a pill like 17 / 25 g. It fills once the meal has enough. When you add food (⌘N), search says what's missing: +8 g protein to reach 25.",
                goal: .none
            ),
            TourStep(
                id: "weigh-in", since: 3, symbol: "scalemass", title: "Weigh in",
                body: "Each morning, tap Weigh in in the strip – or ⋯ → Create… → Weight. Your last weight is already there: adjust it and tap Save. A salty dinner or a late meal? Pick it under More, and that morning won't count for your pace.",
                macBody: "Each morning, click Weigh in in the strip, or choose Log Weight… in the File menu. Your last weight is already there: adjust it and click Save. A salty dinner or a late meal? Pick it under More, and that morning won't count for your pace.",
                goal: .increased(\.weighIns)
            ),
            TourStep(
                id: "measure", since: 3, symbol: "ruler", title: "Measure in seconds",
                body: "Tap ⋯ → Create… → Measurements. One site per page, with last time's value already there: type your waist – or nudge it with − and + – and tap Done. The strip tells you when the next measurement is due.",
                macBody: "Choose File → Log Measurements… (⇧⌘M). One site per page, with last time's value already there: type your waist and click Done. The strip tells you when the next measurement is due.",
                goal: .increased(\.measureCount)
            ),
            TourStep(
                id: "progress", since: 3, symbol: "chart.line.uptrend.xyaxis", title: "Progress",
                body: "The Progress tab → Body shows your 7-day average weight and its pace against your plan, your tape and body-fat values, your phases and your check-ins. Tap a tile to see its chart.",
                macBody: "Body in the sidebar (⌘6) shows your 7-day average weight and its pace against your plan, your tape and body-fat values, your phases and your check-ins. Click a tile to see its chart.",
                goal: .none
            ),
            TourStep(
                id: "checkin", since: 3, symbol: "calendar.badge.checkmark", title: "Weekly check-in",
                body: "Once a week a card asks for a two-minute check-in in four steps: your week, your waist, how it went and next week – with a small calorie change when the numbers call for it. Nothing changes until you tap Apply, and Undo takes it back.",
                macBody: "Once a week a card asks for a two-minute check-in in four steps: your week, your waist, how it went and next week – with a small calorie change when the numbers call for it. Nothing changes until you click Apply, and Undo (⌘Z) takes it back.",
                goal: .none
            ),
            TourStep(
                id: "photos", since: 4, symbol: "camera", title: "Progress photos",
                body: "Progress → Body → Photos → Take Photos. Front, side and back – your last photo shows faintly over the camera, so you stand the same way. Compare puts two days side by side with your weight and waist. Photos sync only to your iCloud; lock them with Face ID in the card's ⋯ menu.",
                macBody: "Body → Photos → Add Photos: pick front, side and back from Photos or a file. Compare shows two days side by side, or one over the other with a slider, with your weight and waist. Photos sync only to your iCloud; lock them with Touch ID in the card's ⋯ menu.",
                goal: .none
            ),
            TourStep(
                id: "watchCoach", since: 4, symbol: "applewatch", title: "Coach on your watch",
                body: "With a plan, your Apple Watch shows today's day type under the ring – tap it to switch. Weigh in or measure your waist with the Digital Crown, tap Creatine when you've had it, and see how your weight is going.",
                macBody: "With a plan, Nina on your Apple Watch shows today's day type, your checks and how your weight is going. Weigh in and measure your waist with the Digital Crown.",
                goal: .none
            ),
            TourStep(
                id: "watchHealth", since: 6, symbol: "applewatch", title: "Your iPhone's numbers on your watch",
                body: "Your Apple Watch now shows the same weight numbers as your iPhone, including weigh-ins from your scale in Apple Health. Weighed on the scale this morning? The watch shows it and skips Weigh in. Open Nina on your iPhone once after weighing so it can pass it on.",
                macBody: "Your Apple Watch now shows the same weight numbers as your iPhone, including weigh-ins from your scale in Apple Health. Your iPhone passes them on directly, never through iCloud. This Mac can't read Apple Health, so its numbers only count weigh-ins typed in Nina.",
                goal: .none
            ),
            TourStep(
                id: "healthBody", since: 4, symbol: "heart.text.square", title: "Body data from Apple Health",
                body: "Turn on Body in Settings → Apple Health: body fat, lean mass and waist from your scale show in Progress → Body as their own series, marked Health. After a workout, Today asks \u{201C}Make it a tennis day?\u{201D} – only your tap changes the day.",
                macBody: "List workouts in My Plan → a day type → Apple Health workouts (tennis, strength …). After a matching workout, your iPhone asks whether to make it that kind of day – only your tap changes it.",
                goal: .none
            ),
            TourStep(
                id: "history", since: 4, symbol: "clock.arrow.circlepath", title: "Bring your history",
                body: "Old weigh-ins, tape logs or a DEXA, InBody or 3D-scan report? ⋯ → Create… → Import My Data → Body: copy the prompt, give it to your AI with your data and paste its answer back. Nina adds only what's new, and Undo takes it all back.",
                macBody: "Old weigh-ins, tape logs or a DEXA, InBody or 3D-scan report? File → Import & Export… (⇧⌘I) → Body: copy the prompt, give it to your AI with your data and paste its answer back. Nina adds only what's new, and Undo takes it all back.",
                goal: .none
            ),
            TourStep(
                id: "thalia", since: 6, symbol: "arrow.up.forward.app", title: "Your numbers in Thalia",
                body: "Nina hands Thalia your daily calories, protein, carbs, fat, water and morning weight on this device – Thalia takes them as soon as you open it. One switch for all your devices: Settings → Thalia → An Thalia liefern.",
                macBody: "Nina hands Thalia your daily calories, protein, carbs, fat, water and morning weight on this Mac – Thalia takes them as soon as you open it here. One switch for all your devices: Settings (⌘,) → General → Thalia → An Thalia liefern.",
                goal: .none
            ),
            TourStep(
                id: "backup", since: 6, symbol: "externaldrive", title: "Back up, move, find",
                body: "Settings → Import & Export → Back Up Everything saves all your Nina data in one folder – photos and check-ins too, nothing from Apple Health. Logged something on the wrong day? Touch and hold the entry → Move to Day…",
                macBody: "File → Back Up Nina… (⇧⌘B) saves all your Nina data in one folder – photos and check-ins too. Search in the sidebar (⇧⌘F) finds any food or day. On Today, ⌫ deletes the selected entries, ⌘C and then ⌘V on another day copies them, and right-click → Move to Day… moves them.",
                goal: .none
            ),
            TourStep(
                id: "autobackup", since: 6, symbol: "clock.badge.checkmark", title: "A backup every week",
                body: "Nina now saves a full backup once a week by itself and keeps the last 4 – in the Files app under On My iPhone → Nina. Settings → Import & Export → Choose Folder… keeps them in iCloud Drive instead. (On iPad, switch on Back Up Automatically Every Week there.)",
                macBody: "Settings → Import & Export → Back Up Automatically Every Week saves a full backup once a week and keeps the last 4 – in Nina's own folder (Show in Finder) or a folder you choose. It's off on the Mac until you switch it on. File → Back Up Nina… (⇧⌘B) still saves one whenever you like.",
                goal: .none
            ),
            TourStep(
                id: "siri", since: 6, symbol: "waveform", title: "Siri, Shortcuts and controls",
                body: "Say \u{201C}Log weight in Nina\u{201D}, \u{201C}Today is a Tennis day in Nina\u{201D} or \u{201C}Mark Creatine done in Nina\u{201D} – German works too (\u{201C}Heute ist ein Tennistag in Nina\u{201D}). In Control Center, tap + and then Add a Control → Nina for Log Food, Weigh In and Add Water; they also fit the Lock Screen and the Action button.",
                macBody: "Ask Siri or use the Shortcuts app: \u{201C}Log weight in Nina\u{201D}, \u{201C}Today is a Gym day in Nina\u{201D}, \u{201C}Mark Creatine done in Nina\u{201D} – in English or German (\u{201C}Gewicht in Nina eintragen\u{201D}).",
                goal: .none
            ),
            TourStep(
                id: "coachWidget", since: 6, symbol: "rectangle.stack", title: "The coach on your Home Screen",
                body: "Add the Coach widget (touch and hold the Home Screen → Edit → Add Widget → Nina): today's day type, your 7-day average and weekly rate, the next measurement and the checks still open. Tap a check to tick it off, or Weigh in before your morning cutoff.",
                macBody: "On your iPhone, add the Coach widget (touch and hold the Home Screen → Edit → Add Widget → Nina): today's day type, your 7-day average and weekly rate, the next measurement and the checks still open – one tap away.",
                goal: .none
            ),
            TourStep(
                id: "menubar", since: 6, symbol: "menubar.rectangle", title: "Today and Nutrition, everywhere",
                body: "The Today tab is your diary and Progress → Nutrition shows how you eat – the Mac now uses the same names. On a Mac, Nina also sits in the menu bar with what's left today.",
                macBody: "The sidebar now uses the iPhone's names: Today (⌘1) is your diary, Nutrition (⌘5) shows how you eat. And Nina sits in the menu bar: calories left, protein and water today, a glass of water, Log Food… and Weigh In… without switching apps. Settings (⌘,) → General → Menu Bar turns it off.",
                goal: .none
            ),
            TourStep(
                id: "everywhere", symbol: "applewatch", title: "Everywhere you are",
                body: "Nina syncs through your iCloud with your Mac and Apple Watch. Log from the watch, see what's left in widgets, and send everything to Apple Health in Settings.",
                macBody: "Nina syncs through your iCloud with your iPhone and Apple Watch. Settings (⌘,) has Goals, My Plan, meals, reminders and Import & Export.",
                goal: .none
            ),
        ]
    )
}
