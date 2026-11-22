import SwiftUI
import Charts
import BinisoftKit
import NinaCore

// Apple Health body data on screen (spec F22), all read live and never stored: the workout hint
// under Today's day-type chip, Health's waist on the waist detail, the height hint in Goals & Plan
// and the workout kinds of a day type in My Plan.

// MARK: - Today: workout → day type

extension View {
    /// Today's day-type chip with "🎾 Tennis workout found · Make it a tennis day?" under it, when a
    /// finished Apple Health workout fits another day type than today's default one. Only a tap on
    /// it changes the day (a day-type mark with Undo); "Not now" hides it for the day on this device.
    func todayCoachWorkoutHint(day: DayKey) -> some View {
        modifier(TodayCoachWorkoutHint(day: day))
    }
}

private struct TodayCoachWorkoutHint: ViewModifier {
    let day: DayKey
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            if let suggestion {
                TodayCoachWorkoutPill(suggestion: suggestion) {
                    _ = app.setDayType(suggestion.typeID, on: suggestion.day)
                } dismiss: {
                    app.dismissCard(suggestion.key)
                }
                .transition(.opacity)
            }
        }
        .animation(.snappy, value: suggestion?.key)
        .task(id: day) {
            await watchWorkouts()
        }
    }

    private var suggestion: WorkoutSuggestion? {
        guard day == app.today else { return nil }
        return app.health.bodyData.workoutSuggestion(settings: app.settings, day: day, dismissed: Set(app.coachDismissals.keys))
    }

    /// While today is shown: today's workouts are read again every few minutes (a workout that
    /// just ended shows up without leaving the app).
    private func watchWorkouts() async {
        guard day == app.today else { return }
        let reader = app.health.bodyData
        while !Task.isCancelled {
            await reader.refreshWorkoutsIfStale()
            try? await Task.sleep(for: .seconds(HealthBodyReader.workoutsMaxAge))
        }
    }
}

/// The hint as a glass pill with a small "Not now" button.
private struct TodayCoachWorkoutPill: View {
    let suggestion: WorkoutSuggestion
    let accept: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: accept) {
                Text(label)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(Brand.accent.opacity(0.18)).interactive(), in: .capsule)
            .accessibilityLabel(suggestion.text)
            .accessibilityHint("Makes today a \(suggestion.typeName) day. From an Apple Health workout.")
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Not now")
        }
    }

    /// "🎾 Tennis workout found · Make it a tennis day?"
    private var label: String {
        suggestion.emoji.isEmpty ? suggestion.text : "\(suggestion.emoji) \(suggestion.text)"
    }
}

// MARK: - Waist detail

/// Progress → Body → Waist: Apple Health's waist as a series of its own under the tape readings
/// (never mixed with them; changes only within it). Not editable here: it lives in Health.
struct BodyDetailsHealthWaistSection: View {
    let site: BodySite
    let since: DayKey?
    @Environment(AppModel.self) private var app

    var body: some View {
        if let health {
            Section {
                BodyDetailsHealthWaistChart(points: health.points)
                    .frame(height: 160)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Apple Health waist chart")
                    .accessibilityValue(summary(health))
                if let change = health.change, change.from.day < change.to.day {
                    LabeledContent("Since \(Fmt.shortDay(change.from.day))", value: changeText(change))
                }
                ForEach(health.rows.prefix(12)) { (point: BodyDetailsHealthWaist.Point) in
                    LabeledContent(Fmt.dayTitle(point.day, today: app.today), value: BodyPageText.centimeters(point.value))
                }
            } header: {
                Label("Apple Health", systemImage: "heart.fill")
            } footer: {
                Text("Waist from Apple Health, read live and never stored in Nina. It's a series of its own – never mixed with your tape readings, so changes only compare Health values with each other.")
            }
        }
    }

    private var health: BodyDetailsHealthWaist? {
        let waist = app.health.bodyData.waist(dayStartHour: app.settings.dayStartHour)
        return BodyDetailsHealthWaist(site: site, waist: waist, since: since, calendar: .current)
    }

    private func changeText(_ change: GirthChange) -> String {
        let text = BodyPageText.signed(change.change, decimals: 1) + " cm"
        return change.isClear ? text : text + " · " + GirthTrend.noClearChange
    }

    private func summary(_ health: BodyDetailsHealthWaist) -> String {
        guard let latest = health.latest else { return "" }
        return "Latest \(BodyPageText.centimeters(latest.value)) on \(Fmt.shortDay(latest.day))"
    }
}

private struct BodyDetailsHealthWaistChart: View {
    let points: [BodyDetailsHealthWaist.Point]

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(x: .value("Day", point.date, unit: .day), y: .value("cm", point.value))
                    .foregroundStyle(Color.pink)
                PointMark(x: .value("Day", point.date, unit: .day), y: .value("cm", point.value))
                    .foregroundStyle(Color.pink)
                    .symbolSize(24)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
    }
}

// MARK: - Height hint

/// Goals & Plan → Body & Calculator, under the height: "Health: 176 cm". Only a hint – the person
/// sets the height with the stepper; nothing read from Health is copied into the synced profile.
struct HealthHeightHint: View {
    /// What the height field shows (0 = not set).
    let heightCm: Double
    @Environment(AppModel.self) private var app

    var body: some View {
        if let hint = HealthBody.heightHint(health: app.health.bodyData.heightCm, profileCm: heightCm) {
            HStack {
                Label {
                    Text(HealthBody.heightHintText(hint))
                } icon: {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - My Plan: workouts of a day type

/// My Plan → a day type → Apple Health Workouts: the workout kinds that suggest this type on Today
/// ("tennis", "strength"). With kinds listed and workouts not read yet on this iPhone, a button
/// asks Health for permission right here.
struct PlanEditorHealthWorkoutsSection: View {
    @Binding var workouts: [String]
    @Environment(AppModel.self) private var app
    /// What is being typed (the list is stored normalised: "Strength Training" → strength_training).
    @State private var text: String?

    var body: some View {
        Section {
            TextField("e.g. tennis or strength", text: textBinding)
                .autocorrectionDisabled()
            if offersReading {
                Button("Read Workouts from Apple Health", systemImage: "heart") {
                    let reader = app.health.bodyData
                    Task { await reader.set(.workouts, true) }
                }
            }
        } header: {
            Text("Apple Health workouts")
        } footer: {
            Text("When today is a default day and Apple Health has a finished workout of one of these kinds, Today asks whether to make it this day type – nothing changes until you tap. Separate kinds with commas: strength, tennis, running, cycling, swimming, hiit …")
        }
    }

    private var textBinding: Binding<String> {
        Binding<String>(
            get: { text ?? workouts.joined(separator: ", ") },
            set: { (value: String) in
                text = value
                workouts = HealthWorkouts.parse(value)
            }
        )
    }

    /// Health can be read here, kinds are listed, and the workouts switch is still off.
    private var offersReading: Bool {
        let reader = app.health.bodyData
        return reader.isAvailable && !workouts.isEmpty && !reader.options.contains(.workouts)
    }
}
