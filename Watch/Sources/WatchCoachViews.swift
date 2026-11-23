import SwiftUI
import NinaCore

// The coach on the home screen (with a set-up plan): the day-type chip under the ring, the checks
// row, the status line and a short Undo; and the screens they open – the day types, the weigh-in
// and the weekly tape with the Digital Crown (0.1 kg or 0.1 cm per detent).

/// Numbers in the person's locale with fixed decimals ("74.6", "74,6").
enum WatchNumber {
    static func fixed(_ value: Double, _ decimals: Int) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)))
    }
}

/// Under the ring: the chip, the checks row and the status line (the Undo of the last write sits
/// under it on the home screen, with or without a plan).
struct WatchCoachSummary: View {
    let coach: WatchCoachData
    let remaining: Double
    @Binding var route: WatchCoachRoute?

    var body: some View {
        VStack(spacing: 4) {
            if let chip = coach.chip {
                WatchCoachChip(chip: chip, remaining: remaining) { route = .dayType }
            }
            if !coach.pills.isEmpty {
                WatchCoachPills(coach: coach, route: $route)
            }
            if coach.status != nil || coach.healthMorning != nil {
                WatchCoachStatusLine(status: coach.status, isFromPhone: coach.statusIsFromPhone,
                                     healthMorning: coach.healthMorning, showsHealthHint: coach.showsHealthHint)
            }
        }
    }
}

/// "🎾 Tennis · 1,240 left": filled when the day type was picked by hand, tinted when it comes
/// from the schedule. A tap opens the day types.
private struct WatchCoachChip: View {
    let chip: CoachBoard.Chip
    let remaining: Double
    let action: () -> Void

    @Environment(WatchModel.self) private var model

    private var text: String {
        let unit = model.settings.energyUnit
        return WatchCoach.chipText(chip, remaining: remaining) { Fmt.energy($0, unit: unit, showUnit: false) }
    }

    var body: some View {
        Button(action: action) {
            face
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Day type: \(chip.name), \(chip.isManual ? "picked by hand" : "from your schedule")")
        .accessibilityHint("Choose the day type")
    }

    @ViewBuilder
    private var face: some View {
        let label = HStack(spacing: 4) {
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .opacity(0.7)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        if chip.isManual {
            label
                .foregroundStyle(Color.white)
                .background(Color.accentColor, in: Capsule())
        } else {
            label
                .foregroundStyle(Color.accentColor)
                .background(Color.accentColor.opacity(0.2), in: Capsule())
        }
    }
}

/// The weigh-in, the weekly tape and the daily checks as small pills in one row (centred when
/// they fit, else it scrolls sideways). Done checks shrink to a check mark; a tap opens them again.
private struct WatchCoachPills: View {
    let coach: WatchCoachData
    @Binding var route: WatchCoachRoute?

    @Environment(WatchModel.self) private var model

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row
            ScrollView(.horizontal, showsIndicators: false) {
                row
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Checks")
    }

    private var row: some View {
        HStack(spacing: 6) {
            ForEach(coach.pills) { item in
                WatchCoachPill(item: item, title: WatchCoach.pillTitle(item, plan: coach.plan)) {
                    tap(item)
                }
            }
        }
    }

    private func tap(_ item: CoachBoard.StripItem) {
        switch WatchCoach.act(for: item) {
        case .weighIn?:
            route = .weighIn
        case .measure(let sites)?:
            route = .measure(sites)
        case .check(let id)?:
            model.toggleCheck(id, on: coach.day)
        case nil:
            break
        }
    }
}

private struct WatchCoachPill: View {
    let item: CoachBoard.StripItem
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            face
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch item.state {
        case .done: return "\(title), done"
        case .skipped: return "\(title), not today"
        case .open: return [title, item.detail].compactMap { $0 }.joined(separator: ", ")
        }
    }

    @ViewBuilder
    private var face: some View {
        switch item.state {
        case .done:
            compact(symbol: "checkmark", tint: Color.accentColor)
        case .skipped:
            compact(symbol: "minus", tint: Color.gray)
        case .open:
            openFace
        }
    }

    private var openFace: some View {
        HStack(spacing: 4) {
            icon
            Text(title)
                .lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.gray.opacity(0.3), in: Capsule())
    }

    @ViewBuilder
    private var icon: some View {
        if !item.emoji.isEmpty {
            Text(item.emoji)
        } else {
            Image(systemName: item.symbol.isEmpty ? "circle" : item.symbol)
                .foregroundStyle(item.detail == nil ? Color.accentColor : Color.orange)
        }
    }

    private func compact(symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.white)
            .frame(width: 26, height: 26)
            .background(tint, in: Circle())
    }
}

/// The status of the active phase in the phone's words, coloured like the phone, with the 7-day
/// average and the rate under it: "Slower than planned" / "avg 74.6 · +0.15/wk" – the iPhone's
/// numbers (Apple Health weigh-ins included) while they are at least as fresh as the watch's own.
/// Under it this morning's weigh-in from Apple Health when the iPhone reported one, and, under the
/// watch's own numbers, a note that weigh-ins from Apple Health count on the iPhone.
private struct WatchCoachStatusLine: View {
    let status: WatchCoach.Status?
    let isFromPhone: Bool
    let healthMorning: WatchSnapshotRelay.Morning?
    let showsHealthHint: Bool

    /// VoiceOver: where the numbers come from.
    private var source: String {
        isFromPhone ? "Worked out on your iPhone" : ""
    }

    var body: some View {
        VStack(spacing: 0) {
            if let status {
                WatchCoachStatusNumbers(status: status)
            }
            if let healthMorning {
                WatchHealthMorningLine(morning: healthMorning)
            }
            if showsHealthHint, status != nil {
                Text("Weigh-ins from Apple Health count on your iPhone")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(source)
    }
}

/// "♥ This morning 74.6 kg": the morning weigh-in the iPhone read from Apple Health (shown only,
/// never saved on the watch).
private struct WatchHealthMorningLine: View {
    let morning: WatchSnapshotRelay.Morning

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "heart.fill")
                .foregroundStyle(Color.pink)
                .imageScale(.small)
            Text(WatchCoach.morningText(morning.kilograms, number: WatchNumber.fixed))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.caption2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This morning's weigh-in from Apple Health, \(WatchNumber.fixed(morning.kilograms, 1)) kilograms")
    }
}

/// "In range" over "avg 74.6 · +0.15/wk".
private struct WatchCoachStatusNumbers: View {
    let status: WatchCoach.Status

    var body: some View {
        if let word = status.word {
            Text(word)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        numbers
    }

    @ViewBuilder
    private var numbers: some View {
        let text = status.numbersText(number: WatchNumber.fixed)
        if !text.isEmpty {
            Text(text)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityLabel(spokenNumbers)
        }
    }

    /// "7-day average 74.6 kilograms, gaining 0.15 kilograms a week" – not "slash w k".
    private var spokenNumbers: String {
        var parts: [String] = []
        if let average = status.average {
            parts.append("7-day average \(WatchNumber.fixed(average, 1)) kilograms")
        }
        if let rate = status.rate {
            let amount = "\(WatchNumber.fixed(abs(rate), 2)) kilograms a week"
            if abs(rate) < 0.005 {
                parts.append("steady")
            } else {
                parts.append(rate > 0 ? "gaining \(amount)" : "losing \(amount)")
            }
        }
        return parts.joined(separator: ", ")
    }

    private var color: Color {
        switch status.tone {
        case .good: .green
        case .watch: .orange
        case .alert: .red
        case .neutral: .secondary
        }
    }
}

/// "Creatine done · Undo" or "Added Skyr · 180 kcal · Undo" for a few seconds after a write.
struct WatchUndoBar: View {
    let undo: WatchUndo

    @Environment(WatchModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: undo.symbol)
                .foregroundStyle(Color.accentColor)
            Text(undo.message)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            Button {
                model.performUndo()
            } label: {
                Text("Undo")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.25), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .font(.caption2)
    }
}

// MARK: - Day types

/// Every day type with the day's kcal and the flexible count; "Back to Schedule" for a day set by
/// hand. Picking writes the day-type mark like the phone's chip menu.
struct WatchDayTypeList: View {
    let day: DayKey
    let chip: CoachBoard.Chip

    @Environment(WatchModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(chip.options) { option in
                    Button {
                        pick(option)
                    } label: {
                        WatchDayTypeRow(option: option, detail: detail(option))
                    }
                }
            } footer: {
                Text(chip.isManual ? "Picked by hand for this day." : "From your schedule.")
            }
            if chip.isManual {
                Section {
                    Button {
                        model.setDayType(nil, on: day)
                        dismiss()
                    } label: {
                        Label("Back to Schedule", systemImage: "calendar.badge.clock")
                    }
                }
            }
        }
        .navigationTitle("Day Type")
    }

    private func detail(_ option: CoachBoard.ChipOption) -> String {
        let unit = model.settings.energyUnit
        return WatchCoach.optionDetail(option) { Fmt.energy($0, unit: unit) }
    }

    private func pick(_ option: CoachBoard.ChipOption) {
        if !option.isSelected { model.setDayType(option.id, on: day) }
        dismiss()
    }
}

private struct WatchDayTypeRow: View {
    let option: CoachBoard.ChipOption
    let detail: String

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text([option.emoji, option.name].filter { !$0.isEmpty }.joined(separator: " "))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if option.isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .accessibilityAddTraits(option.isSelected ? .isSelected : [])
    }
}

// MARK: - Weigh-in

/// The weight with the Digital Crown, 0.1 kg per detent from the last weight typed in Nina; Save
/// logs it now (Undo on the home screen). A weight far from the 7-day average says so first.
struct WatchWeighInView: View {
    let latest: Double?
    let reference: Double?

    @Environment(WatchModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var kilograms: Double

    init(start: Double, latest: Double?, reference: Double?) {
        self.latest = latest
        self.reference = reference
        _kilograms = State(initialValue: start)
    }

    private var range: ClosedRange<Double> { WeightSignal.plausibleRange }
    private var value: Double { WatchCoach.snapped(kilograms, in: range) }

    var body: some View {
        VStack(spacing: 4) {
            number
            hint
            Button(action: save) {
                Label("Save", systemImage: "checkmark")
            }
            .tint(Color.accentColor)
        }
        .padding(.horizontal, 4)
        .navigationTitle("Weigh In")
    }

    private var number: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(WatchNumber.fixed(value, 1))
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.7)
            Text("kg")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .focusable()
        .digitalCrownRotation($kilograms, from: range.lowerBound, through: range.upperBound, by: WatchCoach.step,
                              sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weight")
        .accessibilityValue(Fmt.kilograms(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: kilograms = WatchCoach.stepped(kilograms, by: 1, in: range)
            case .decrement: kilograms = WatchCoach.stepped(kilograms, by: -1, in: range)
            default: break
            }
        }
    }

    /// "Last 74.2 kg", or how far it is from the 7-day average when that looks like a typo.
    private var hint: some View {
        let sanity = WeightSignal.sanity(value, reference: reference)
        var text = latest.map { "Last \(Fmt.kilograms($0))" } ?? "Turn the Crown"
        var isWarning = false
        if case .typo(let average) = sanity {
            text = "\(Fmt.kilograms(abs(value - average))) from your 7-day average – sure?"
            isWarning = true
        }
        return Text(text)
            .font(.caption2)
            .foregroundStyle(isWarning ? Color.orange : Color.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
    }

    private func save() {
        model.logWeight(value)
        dismiss()
    }
}

// MARK: - Weekly tape

/// The weekly tape sites one at a time with the Digital Crown, 0.1 cm per detent from the site's
/// last reading. Save keeps the value (one record for the session, conditions set automatically)
/// and moves to the next site; Skip moves on without one.
struct WatchMeasureView: View {
    let records: [BodyTapeRecord]
    let day: DayKey

    @Environment(WatchModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var flow: WatchCoach.TapeFlow
    @State private var centimeters: Double
    /// The session's record once the first site is saved.
    @State private var record: BodyMeasurement?
    @State private var started: Date?

    init(sites: [BodySite], records: [BodyTapeRecord], day: DayKey) {
        let flow = WatchCoach.TapeFlow(sites: sites)
        self.records = records
        self.day = day
        _flow = State(initialValue: flow)
        _centimeters = State(initialValue: WatchMeasureView.start(flow.current, records: records, day: day))
    }

    static func start(_ site: BodySite?, records: [BodyTapeRecord], day: DayKey) -> Double {
        guard let site else { return 0 }
        return WatchCoach.startGirth(site, previous: WatchCoach.previousGirth(site, in: records, onOrBefore: day)?.value)
    }

    var body: some View {
        Group {
            if let site = flow.current {
                WatchMeasurePage(site: site, centimeters: $centimeters, previous: previous(site), day: day,
                                 hasNext: flow.next != nil, save: save, skip: skip)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .navigationTitle(flow.progress ?? "Measure")
    }

    private func previous(_ site: BodySite) -> GirthReading? {
        WatchCoach.previousGirth(site, in: records, onOrBefore: day)
    }

    private func save() {
        guard flow.current != nil else { return }
        flow.save(centimeters)
        let time = started ?? Date()
        started = time
        record = model.saveTape(flow.values, into: record, message: flow.savedText ?? "Measurements saved", time: time)
        moveOn()
    }

    private func skip() {
        flow.skip()
        moveOn()
    }

    private func moveOn() {
        if let next = flow.current {
            centimeters = WatchMeasureView.start(next, records: records, day: day)
        } else {
            dismiss()
        }
    }
}

/// One site: its name, the value with the Crown, the change since last time (or a nudge), Save
/// and Skip.
private struct WatchMeasurePage: View {
    let site: BodySite
    @Binding var centimeters: Double
    let previous: GirthReading?
    let day: DayKey
    let hasNext: Bool
    let save: () -> Void
    let skip: () -> Void

    private var range: ClosedRange<Double> { site.plausibleRange }
    private var value: Double { WatchCoach.snapped(centimeters, in: range) }

    var body: some View {
        VStack(spacing: 3) {
            Text(site.hasSides && !site.isLeft ? "\(site.title) (right)" : site.title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            number
            note
            buttons
        }
        .padding(.horizontal, 4)
    }

    private var number: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(WatchNumber.fixed(value, 1))
                .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.7)
            Text("cm")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .focusable()
        .digitalCrownRotation($centimeters, from: range.lowerBound, through: range.upperBound, by: WatchCoach.step,
                              sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(site.title)
        .accessibilityValue("\(WatchNumber.fixed(value, 1)) cm")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: centimeters = WatchCoach.stepped(centimeters, by: 1, in: range)
            case .decrement: centimeters = WatchCoach.stepped(centimeters, by: -1, in: range)
            default: break
            }
        }
    }

    /// "−0.3 cm since 7 Jan", or a nudge when it moved a lot.
    private var note: some View {
        var text = "First reading"
        var isWarning = false
        if let previous {
            let date = Fmt.shortDay(previous.day)
            switch WatchCoach.girthNote(value, previous: previous, on: day) {
            case .jump:
                text = "Over 3 cm from \(date) – same spot?"
                isWarning = true
            case .recheck:
                text = "Over 1 cm from last time – measure again to be sure"
                isWarning = true
            case .ok:
                text = "\(WatchCoach.signed(value - previous.value, 1, number: WatchNumber.fixed)) cm since \(date)"
            }
        }
        return Text(text)
            .font(.caption2)
            .foregroundStyle(isWarning ? Color.orange : Color.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            if hasNext {
                Button("Skip", action: skip)
            }
            Button(action: save) {
                Text("Save")
            }
            .tint(Color.accentColor)
        }
    }
}
