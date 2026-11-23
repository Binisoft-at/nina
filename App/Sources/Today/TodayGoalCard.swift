import SwiftUI
import BinisoftKit
import NinaCore

/// "Set your goal" on Today for people who haven't told Nina about themselves yet: no coach plan,
/// and the starting targets or no body data (`GoalSetupPrompt`). One line why, a button to Goals &
/// Plan, "Not Now" (back in 7 days) and "Don't Show Again" – both with Undo in the toast. The choice
/// stays on this device (UserDefaults, never synced): Today owns it (`@AppStorage(storageKey)`)
/// and hands it in, so the card goes the moment it is put away.
struct TodayGoalCard: View {
    let reason: GoalSetupPrompt.Reason
    /// `GoalSetupPrompt.Dismissal.stored`: "", "never" or the day the card comes back.
    @Binding var choice: String

    @Environment(AppModel.self) private var app

    /// The device-only setting that holds "Not now" / "Don't show again".
    static let storageKey = "nina.today.goalCard"

    /// Why the card shows on `day`; nil when it doesn't: only on today, not in the tour's practice
    /// diary, not once a plan is set up or the goal is set, and not while put away.
    static func reason(settings: NinaSettings, choice: String, day: DayKey, today: DayKey, isSandbox: Bool) -> GoalSetupPrompt.Reason? {
        guard day == today, !isSandbox else { return nil }
        let reason = GoalSetupPrompt.reason(planIsSetUp: settings.plan.isSetUp, targets: settings.targets,
                                            trainingTargets: settings.trainingTargets, hasBody: settings.hasBody)
        let dismissal = GoalSetupPrompt.Dismissal(stored: choice)
        return GoalSetupPrompt.isVisible(reason, dismissal: dismissal, today: today) ? reason : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Set your goal")
                    .font(.headline)
            } icon: {
                Image(systemName: "target")
                    .foregroundStyle(Brand.accent)
            }
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            buttons
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, cornerRadius: 22)
        .accessibilityElement(children: .contain)
    }

    /// One line on why it matters.
    private var message: String {
        switch reason {
        case .standardTargets:
            let standard = Fmt.energy(DailyTargets.standard.energy, unit: .kcal)
            return "Nina uses standard targets (\(standard)) for now. Tell Nina about you and your goal to get your own."
        case .missingBody:
            return "Add your height and birth year, so Nina can check your targets and work out your body numbers."
        }
    }

    /// The buttons in one row, or stacked when they don't fit (large text, narrow windows).
    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                openButton
                Spacer(minLength: 0)
                laterButtons
            }
            VStack(alignment: .leading, spacing: 8) {
                openButton
                HStack(spacing: 14) {
                    laterButtons
                }
            }
        }
    }

    private var openButton: some View {
        Button("Set Your Goal") {
            app.sheet = .goals
        }
        .primaryActionStyle()
        .lineLimit(1)
        .accessibilityHint("Opens Goals & Plan")
    }

    @ViewBuilder
    private var laterButtons: some View {
        Button("Not Now") {
            put(away: GoalSetupPrompt.Dismissal.notNow(today: app.today), message: "Hidden for a week", symbol: "clock")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityHint("Hides this card for a week")
        Button("Don't Show Again") {
            put(away: .forever, message: TodayGoalCard.foreverMessage, symbol: "eye.slash")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityHint("Hides this card on this device")
    }

    /// Where Goals & Plan stays once the card is gone for good.
    private static var foreverMessage: String {
        #if os(macOS)
        return "Hidden for good. Goals & Plan stays in the Go menu."
        #else
        return "Hidden for good. Goals & Plan stays in the ⋯ menu."
        #endif
    }

    /// Stores the choice (the card goes) and offers Undo, which puts the previous choice back.
    private func put(away dismissal: GoalSetupPrompt.Dismissal, message: String, symbol: String) {
        let previous = choice
        let stored = $choice
        withAnimation(.snappy) {
            choice = dismissal.stored
        }
        app.toasts.show(message, symbol: symbol) {
            withAnimation(.snappy) {
                stored.wrappedValue = previous
            }
        }
    }
}
