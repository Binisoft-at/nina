import SwiftUI
import BinisoftKit
import NinaCore

// The cards of the body page (BodyPage.swift): set-up, due today, phase header, body goal,
// tape tiles, phases timeline, check-ins, check adherence and the histories. The weight and
// composition cards with their charts are in BodyPageCharts.swift.

// MARK: - Set up

/// Without a plan: one card that opens the plan editor, My Plan (which offers "Import from My AI").
struct BodyPageSetupCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        CardSection(title: "Set up your plan", symbol: "sparkles") {
            Text("Add phases, day types and when to measure, and Nina coaches you: a rate to aim for, a weekly check-in and reminders to measure. Type it in yourself, or use “Import from My AI” in My Plan.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Set Up Your Plan", systemImage: "list.bullet.clipboard") {
                app.present(.plan)
            }
            .primaryActionStyle()
        }
    }
}

// MARK: - Due today

/// The body items due today (and the week's check-in or a phase review); a tap acts.
struct BodyPageDueCard: View {
    let items: [BodyPageDue]
    let today: DayKey
    @Environment(AppModel.self) private var app

    var body: some View {
        CardSection(title: "Due today", symbol: "checklist") {
            ForEach(items) { item in
                Button {
                    app.perform(item.action, on: today)
                } label: {
                    BodyPageLinkRow(title: item.title, detail: item.detail, symbol: item.symbol)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Phase header

/// "Lean gain · week 3 of 16", the status pill, a progress capsule and a few lines; a tap
/// opens the phase.
struct BodyPagePhaseCard: View {
    let header: BodyPagePhaseHeader
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            app.present(.phase(header.phaseID))
        } label: {
            content
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the phase")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(header.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let dates = header.dates {
                        Text(dates)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Chip(text: header.status, tint: BodyPageStyle.color(header.tone), isSelected: header.tone == .alert)
            }
            if let progress = header.progress {
                BodyPageCapsule(progress: progress)
            }
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var lines: [String] {
        var lines: [String] = []
        if let rate = header.rate { lines.append("Goal " + rate) }
        if let end = header.projectedEnd { lines.append("Projected end weight " + Fmt.kilograms(end)) }
        if let checkpoint = header.checkpointLine { lines.append(checkpoint) }
        return lines
    }
}

// MARK: - Body goal

/// The long-term goal: lean mass, fat mass and body fat with bars, the weight row and the
/// honest lines.
struct BodyPageGoalCard: View {
    let goal: BodyPageGoal

    var body: some View {
        CardSection(title: "Body goal", symbol: "target", trailing: goal.goalText) {
            if goal.card.isEmpty {
                Text(BodyGoalCard.emptyText)
                    .font(.subheadline.weight(.medium))
                Text("Add a body-fat value, or measure your waist and neck for the tape estimate, to see the lean and fat mass still to go.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(goal.card.rows) { row in
                    BodyPageGoalRowView(row: row)
                }
            }
            if let weightLine {
                Text(weightLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(notes, id: \.self) { note in
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "7-day average 80.2 kg · phase target 82.0 kg (+1.8) · goal 78.0 kg (−2.2)".
    private var weightLine: String? {
        guard let row = goal.weightRow else { return nil }
        var parts = ["Weight " + Fmt.kilograms(row.now)]
        if let toPhase = row.toPhaseTarget {
            parts.append("phase target \(Fmt.kilograms(row.phaseTarget)) (\(BodyPageText.signed(toPhase, decimals: 1)))")
        }
        if let toGoal = row.toLongTerm {
            parts.append("goal \(Fmt.kilograms(row.longTermTarget)) (\(BodyPageText.signed(toGoal, decimals: 1)))")
        }
        return parts.joined(separator: " · ")
    }

    private var notes: [String] {
        var notes: [String] = []
        if let series = goal.seriesTitle, !goal.card.isEmpty { notes.append("Measured with: \(series)") }
        if let caption = goal.card.caption { notes.append(caption) }
        if let honest = goal.honestLine { notes.append(honest) }
        if let outlook = goal.outlook { notes.append("Lean mass usually grows 0.25–0.5 kg a month: \(outlook).") }
        return notes
    }
}

/// One goal row: "Lean mass  +0.6 of +2.1 kg", a bar, start / now / goal.
struct BodyPageGoalRowView: View {
    let row: BodyGoalRow

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.kind.title)
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 4)
                Text(row.text)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(row.isMovedAway ? Color.orange : Color.secondary)
            }
            BodyPageCapsule(progress: row.progress, tint: tint)
            Text(numbers)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.kind.title)
        .accessibilityValue("\(row.text). \(numbers)")
    }

    private var tint: Color {
        switch row.kind {
        case .lean: .green
        case .fat: .orange
        case .bodyFat: Brand.accent
        }
    }

    /// "Start 64.2 · now 64.8 · goal 67.0 kg" (body fat with the method's band).
    private var numbers: String {
        let unit = row.kind.unit
        func value(_ number: Double) -> String { number.formatted(.number.precision(.fractionLength(1))) }
        var text = "Start \(value(row.start)) · now \(value(row.now)) · goal \(value(row.target)) \(unit)"
        if let band = row.errorBand {
            text += " (±\(band.formatted(.number.precision(.fractionLength(0...1)))) points)"
        }
        return text
    }
}

/// With a plan but no long-term goal: opens My Plan on its Long-Term Goal page.
struct BodyPageGoalHint: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        CardSection(title: "Body goal", symbol: "target") {
            Text("Add a long-term goal – a weight and a body fat – to see how much lean and fat mass is still to go.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add a Goal…", systemImage: "plus") {
                app.present(.planGoal)
            }
        }
    }
}

// MARK: - Tape tiles

/// Waist, Chest, Arm, Thigh, Hip (plus Neck): the latest value and the change since the phase
/// start; a tap pushes the site's chart. In a gain phase the gain line ("arm +0.8, chest +1.4 …"),
/// and a link to the baseline table.
struct BodyPageTilesCard: View {
    let tiles: [BodyPageTile]
    let since: DayKey?
    let baseline: [GirthChange]
    let gainLine: String?
    @Environment(AppModel.self) private var app

    var body: some View {
        CardSection(title: "Measurements", symbol: "ruler", trailing: since.map { "since " + Fmt.shortDay($0) }) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                ForEach(tiles) { tile in
                    NavigationLink {
                        BodyDetailsSiteView(site: tile.site, since: since)
                    } label: {
                        BodyPageTileView(tile: tile)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let gainLine {
                Text("This phase: " + gainLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !baseline.isEmpty {
                NavigationLink {
                    BodyPageBaselineView(rows: baseline, since: since, gainLine: gainLine)
                } label: {
                    BodyPageLinkRow(title: "Baseline table", detail: "Start, latest and change per site", symbol: "tablecells")
                }
                .buttonStyle(.plain)
            }
            Button("Measure Now", systemImage: "plus") {
                app.measureNow()
            }
        }
    }
}

/// One tape tile.
struct BodyPageTileView: View {
    let tile: BodyPageTile

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tile.site.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(valueText)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(changeText)
                .font(.caption2)
                .foregroundStyle(tile.change?.isClear == true ? Brand.accent : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 14, style: .continuous))
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.site.title)
        .accessibilityValue("\(valueText), \(changeText)")
        .accessibilityHint("Shows the chart")
    }

    private var valueText: String {
        tile.value.map { BodyPageText.centimeters($0) } ?? "–"
    }

    private var changeText: String {
        if let text = tile.changeText { return text }
        return tile.value == nil ? "Not measured yet" : "First reading"
    }
}

// MARK: - Phases timeline

/// The phases on a capsule (gain warm, maintain neutral, lose cool) with today, the review
/// window and the goal flag, then the list; a tap opens the phase.
struct BodyPageTimelineCard: View {
    let timeline: BodyPageTimeline
    @Environment(AppModel.self) private var app

    var body: some View {
        CardSection(title: "Phases", symbol: "flag.2.crossed") {
            if !timeline.segments.isEmpty {
                BodyPageTimelineBar(timeline: timeline) { id in
                    app.present(.phase(id))
                }
                HStack {
                    Text(timeline.startText)
                    Spacer()
                    Text(timeline.endText)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                if timeline.review != nil {
                    Text("The shaded window: when you'd reach the review weight at your rate range.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(timeline.rows) { row in
                Button {
                    app.present(.phase(row.id))
                } label: {
                    BodyPagePhaseRowView(row: row)
                }
                .buttonStyle(.plain)
            }
            Button("Add Phase", systemImage: "plus") {
                app.present(.phase(nil))
            }
        }
    }
}

/// The capsule itself.
struct BodyPageTimelineBar: View {
    let timeline: BodyPageTimeline
    let onTap: (String) -> Void

    var body: some View {
        GeometryReader { proxy in
            bar(width: proxy.size.width)
        }
        .frame(height: 30)
    }

    private func bar(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Capsule()
                .fill(Color.secondary.opacity(0.12))
                .frame(width: width, height: 18)
                .offset(y: 6)
            if let review = timeline.review {
                Rectangle()
                    .fill(Color.purple.opacity(0.25))
                    .frame(width: max(3, CGFloat(review.upperBound - review.lowerBound) * width), height: 30)
                    .offset(x: CGFloat(review.lowerBound) * width)
                    .accessibilityHidden(true)
            }
            ForEach(timeline.segments) { segment in
                segmentButton(segment, width: width)
            }
            if let today = timeline.today {
                Capsule()
                    .fill(Color.primary)
                    .frame(width: 2, height: 30)
                    .offset(x: CGFloat(today) * width - 1)
                    .accessibilityHidden(true)
            }
            if let flag = timeline.goalFlag {
                Image(systemName: "flag.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.accent)
                    .offset(x: min(CGFloat(flag) * width, width - 10), y: -2)
                    .accessibilityLabel("Goal date")
            }
        }
    }

    private func segmentButton(_ segment: BodyPageSegment, width: CGFloat) -> some View {
        let segmentWidth = max(6, CGFloat(segment.x1 - segment.x0) * width - 2)
        return Button {
            onTap(segment.id)
        } label: {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(BodyPageStyle.color(segment.goal).opacity(segmentOpacity(segment.state)))
                .frame(width: segmentWidth, height: 18)
        }
        .buttonStyle(.plain)
        .offset(x: CGFloat(segment.x0) * width + 1, y: 6)
        .accessibilityLabel("\(segment.name), \(segment.dates), \(segment.state.title)")
    }

    private func segmentOpacity(_ state: BodyPagePhaseState) -> Double {
        switch state {
        case .active: 1
        case .planned: 0.55
        case .done: 0.35
        }
    }
}

/// A phase in the list: dot, name, dates and rate, state.
struct BodyPagePhaseRowView: View {
    let row: BodyPagePhaseRow

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(BodyPageStyle.color(row.goal))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Chip(text: row.state.title, tint: row.state == .active ? Brand.accent : Color.secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        [row.dates, row.detail].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Check-ins

/// The saved check-ins (week, verdict, Δ kcal, applied); a tap opens that week's check-in.
struct BodyPageCheckInsCard: View {
    let checkIns: [BodyPageCheckIn]
    @Environment(AppModel.self) private var app

    private static let shown = 5

    var body: some View {
        CardSection(title: "Check-ins", symbol: "checkmark.seal") {
            if checkIns.isEmpty {
                Text("Your weekly check-ins show up here: how the week went, your rate and any change to your calories.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(checkIns.prefix(BodyPageCheckInsCard.shown))) { checkIn in
                Button {
                    app.present(.checkIn(checkIn.week))
                } label: {
                    BodyPageCheckInRow(checkIn: checkIn)
                }
                .buttonStyle(.plain)
            }
            if checkIns.count > BodyPageCheckInsCard.shown {
                NavigationLink {
                    BodyDetailsCheckInsView()
                } label: {
                    Label("All check-ins", systemImage: "list.bullet")
                }
            }
            Button("Check In", systemImage: "checkmark.circle") {
                app.present(.checkIn(app.currentCheckInWeek))
            }
        }
    }
}

/// "Week of 7 Jan", "avg 74.6 kg · +0.18 kg/wk · +100 kcal · Applied" and the verdict pill.
struct BodyPageCheckInRow: View {
    let checkIn: BodyPageCheckIn

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(checkIn.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(checkIn.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Chip(text: checkIn.verdict, tint: BodyPageStyle.color(checkIn.tone), isSelected: checkIn.tone == .alert)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// One line of check adherence: "Creatine 26 of 28 days" (the last 28 days, or since the plan
/// was set up).
struct BodyPageChecksCard: View {
    let checks: BodyPageChecks

    var body: some View {
        CardSection(title: "Daily checks", symbol: "pills", trailing: checks.period) {
            Text(checks.line)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Histories

/// "All weigh-ins" and "All measurements".
struct BodyPageHistoryCard: View {
    let measurementCount: Int

    var body: some View {
        CardSection(title: "History", symbol: "clock.arrow.circlepath") {
            NavigationLink {
                WeightView()
            } label: {
                BodyPageLinkRow(title: "All weigh-ins", detail: "Edit or delete, Apple Health included", symbol: "scalemass")
            }
            .buttonStyle(.plain)
            NavigationLink {
                BodyDetailsMeasurementsView()
            } label: {
                BodyPageLinkRow(title: "All measurements", detail: measurementDetail, symbol: "ruler")
            }
            .buttonStyle(.plain)
        }
    }

    private var measurementDetail: String {
        switch measurementCount {
        case 0: "Tape and body fat"
        case 1: "1 record"
        default: "\(measurementCount) records"
        }
    }
}
