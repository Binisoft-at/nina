import SwiftUI
import BinisoftKit
import NinaCore

// Rows and small parts of the plan editor.

/// A phase: name, status pill, dates and pace.
struct PlanEditorPhaseRow: View {
    let name: String
    let status: String
    let detail: String
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.14), in: .capsule)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
    }

    private var tint: Color { isActive ? Brand.accent : Color.secondary }
}

/// A day type: emoji and name, schedule, and its calories in the running phase.
struct PlanEditorDayTypeRow: View {
    let title: String
    let schedule: String
    let targets: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(schedule)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(targets)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

/// A title with a caption line under it.
struct PlanEditorTitleRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// A note from the plan; swipe (iPhone), the context menu or the trash button (Mac) deletes it.
struct PlanEditorNoteRow: View {
    let text: String
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Text(text)
            #if os(macOS)
            Spacer(minLength: 8)
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            #endif
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}

/// The live "Week avg 2,486 kcal" line with the plan's warnings, under the day types.
struct PlanEditorWeekFooter: View {
    let plan: CoachPlan
    let day: DayKey
    let unit: EnergyUnit
    let note: String

    var body: some View {
        let lines = PlanEditorData.weekLines(plan: plan, day: day, unit: unit)
        VStack(alignment: .leading, spacing: 4) {
            if let line = lines.line {
                Text(line)
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
            }
            ForEach(lines.warnings, id: \.self) { (warning: String) in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if !note.isEmpty {
                Text(note)
            }
        }
    }
}

/// Seven weekday chips (1 = Monday), as in Goals → Training days.
struct PlanEditorWeekdayChips: View {
    @Binding var days: Weekdays

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { (weekday: Int) in
                chip(weekday)
            }
        }
    }

    private func chip(_ weekday: Int) -> some View {
        let isOn = days.days.contains(weekday)
        return Button {
            days.toggle(weekday)
        } label: {
            Text(String(Weekdays.shortNames[weekday - 1].prefix(2)))
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 30)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(isOn ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(Color.secondary.opacity(0.12)),
                            in: .rect(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// A number to type, with its unit and (when `step` > 0) a stepper.
struct PlanEditorAmountRow: View {
    let title: String
    @Binding var value: Double
    let unit: String
    var step: Double = 0
    var range: ClosedRange<Double> = 0...100_000
    var decimals: Int = 0

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
            Spacer(minLength: 8)
            TextField(title, value: $value, format: .number.precision(.fractionLength(0...decimals)))
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 90)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Text(unit)
                .foregroundStyle(.secondary)
            if step > 0 {
                Stepper(title, value: $value, in: range, step: step)
                    .labelsHidden()
            }
        }
    }
}

/// Calories, protein, carbs and fat in grams or % of calories, fiber and water, with the macro
/// check ("macros add up to …") and grams per kg body weight.
struct PlanEditorTargetsFields: View {
    @Binding var targets: DailyTargets
    let weightKg: Double
    @State private var inPercent = false

    var body: some View {
        Picker("Enter", selection: $inPercent) {
            Text("Grams").tag(false)
            Text("% of calories").tag(true)
        }
        .pickerStyle(.segmented)
        PlanEditorAmountRow(title: "Calories", value: energy, unit: "kcal", step: 50, range: 0...10_000)
        if inPercent {
            PlanEditorAmountRow(title: "Protein", value: percent(\.protein, perGram: 4), unit: "%", step: 1, range: 0...100)
            PlanEditorAmountRow(title: "Carbohydrates", value: percent(\.carbs, perGram: 4), unit: "%", step: 1, range: 0...100)
            PlanEditorAmountRow(title: "Fat", value: percent(\.fat, perGram: 9), unit: "%", step: 1, range: 0...100)
        } else {
            PlanEditorAmountRow(title: "Protein", value: $targets.protein, unit: "g", step: 5, range: 0...1000)
            PlanEditorAmountRow(title: "Carbohydrates", value: $targets.carbs, unit: "g", step: 5, range: 0...2000)
            PlanEditorAmountRow(title: "Fat", value: $targets.fat, unit: "g", step: 2, range: 0...1000)
        }
        PlanEditorAmountRow(title: "Fiber", value: $targets.fiber, unit: "g", step: 1, range: 0...200)
        PlanEditorAmountRow(title: "Water", value: $targets.water, unit: "ml", step: 250, range: 0...10_000)
        Button("Carbs from the Rest of the Calories", systemImage: "equal.circle") { fillCarbs() }
        if let warning = CoachPlan.macroWarning(targets) {
            Label(warning, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
        }
        if let perKg = perKgLine {
            Text(perKg)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// In % mode a calorie change keeps the split (the grams follow).
    private var energy: Binding<Double> {
        Binding<Double>(
            get: { targets.energy },
            set: { (value: Double) in
                if inPercent {
                    targets = targets.scaled(toEnergy: value)
                } else {
                    targets.energy = value
                }
            }
        )
    }

    private func percent(_ path: WritableKeyPath<DailyTargets, Double>, perGram: Double) -> Binding<Double> {
        Binding<Double>(
            get: {
                let energy = targets.energy
                return energy > 0 ? (targets[keyPath: path] * perGram / energy * 100).rounded() : 0
            },
            set: { (share: Double) in
                targets[keyPath: path] = (targets.energy * share / 100 / perGram).rounded()
            }
        )
    }

    /// Carbs = (calories − protein × 4 − fat × 9) ÷ 4, in 5 g steps.
    private func fillCarbs() {
        let rest = targets.energy - targets.protein * 4 - targets.fat * 9
        targets.carbs = max(0, (rest / 4 / 5).rounded() * 5)
    }

    private var perKgLine: String? {
        guard weightKg > 0 else { return nil }
        let carbs = Fmt.number(targets.carbs / weightKg, decimals: 1)
        let protein = Fmt.number(targets.protein / weightKg, decimals: 1)
        return "\(protein) g protein and \(carbs) g carbs per kg body weight (\(Fmt.kilograms(weightKg)))"
    }
}

/// Pause coaching (F19): from today until a date or until resumed, with a reason; Resume.
struct PlanEditorPauseSection: View {
    @Environment(AppModel.self) private var app
    @State private var reason: CoachPlan.PauseReason = .holiday
    @State private var hasEnd = true
    @State private var end = Date().addingTimeInterval(7 * 86_400)

    var body: some View {
        Section {
            if let pause = app.settings.plan.pause(on: app.today) {
                LabeledContent("Paused", value: PlanEditorData.pauseText(pause))
                Button("Resume Coaching", systemImage: "play.fill") { PlanEditorData.resume(app: app) }
            } else {
                Picker("Reason", selection: $reason) {
                    ForEach(CoachPlan.PauseReason.allCases) { (reason: CoachPlan.PauseReason) in
                        Text(PlanEditorData.reasonTitle(reason)).tag(reason)
                    }
                }
                Toggle("Until a date", isOn: $hasEnd)
                if hasEnd {
                    DatePicker("Until", selection: $end, in: Date()..., displayedComponents: .date)
                }
                Button("Pause from Today", systemImage: "pause.fill") { pause() }
            }
        } header: {
            Text("Pause Coaching")
        } footer: {
            Text("For a holiday or while you're ill: no check pills, no check-ins and no coach reminders, and paused days stay out of your averages. Meal reminders keep going.")
        }
    }

    private func pause() {
        let until: DayKey? = hasEnd ? DayKey(date: end) : nil
        PlanEditorData.pause(until: until, reason: reason, app: app)
    }
}
