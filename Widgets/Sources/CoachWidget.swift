#if os(iOS)
import WidgetKit
import SwiftUI
import NinaCore

/// The coach on the Home Screen and the Lock Screen: the day type with its kcal, the 7-day
/// average and the weekly rate with the status words, the weigh-in while it is open, the next
/// body measurement and the open daily checks. It reads only the small snapshot the app writes
/// to the App Group (`WidgetBridge.readCoach`, `CoachSnapshot`) – never the diary – and moves
/// past the morning cutoff and into the next day on its own. Taps open Nina where it helps:
/// nina://weigh, nina://measure, nina://check/<id>, nina://progress (iPhone only).
struct CoachWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetBridge.coachKind, provider: CoachProvider()) { entry in
            CoachWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Coach")
        .description("Today's day type, your 7-day average and weekly rate, the next measurement and the checks still open.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct CoachEntry: TimelineEntry {
    let date: Date
    let shown: CoachSnapshot.Shown
    /// The app hasn't written a coach snapshot yet (installed, not opened since).
    let isEmpty: Bool
}

struct CoachProvider: TimelineProvider {
    func placeholder(in context: Context) -> CoachEntry {
        CoachEntry(date: Date(), shown: CoachSnapshot.placeholderShown, isEmpty: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (CoachEntry) -> Void) {
        let now = Date()
        guard !context.isPreview, let snapshot = WidgetBridge.readCoach() else {
            completion(CoachEntry(date: now, shown: CoachSnapshot.placeholderShown, isEmpty: !context.isPreview))
            return
        }
        completion(CoachEntry(date: now, shown: snapshot.shown(at: now), isEmpty: false))
    }

    /// The app reloads the timeline whenever the coach data changes. In between, the weigh-in
    /// leaves at the morning cutoff and the next diary day starts with its own day type and
    /// checks (`CoachSnapshot.timeline`).
    func getTimeline(in context: Context, completion: @escaping (Timeline<CoachEntry>) -> Void) {
        let now = Date()
        guard let snapshot = WidgetBridge.readCoach() else {
            let entry = CoachEntry(date: now, shown: CoachSnapshot.placeholderShown, isEmpty: true)
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(3600))))
            return
        }
        let entries = snapshot.timeline(now: now).map { CoachEntry(date: $0.date, shown: $0.shown, isEmpty: false) }
        completion(Timeline(entries: entries, policy: .after(snapshot.nextReload(after: now))))
    }
}

/// Numbers with the person's decimal separator and fixed decimals ("74,6").
private enum CoachWidgetFormat {
    static func number(_ value: Double, _ decimals: Int) -> String {
        guard value.isFinite else { return "–" }
        return value.formatted(.number.precision(.fractionLength(max(0, decimals))))
    }

    /// "2,500 kcal".
    static func kcal(_ value: Double) -> String {
        Fmt.number(value.rounded(), decimals: 0) + " kcal"
    }

    static func url(_ link: CoachSnapshot.Link) -> URL {
        URL(string: link.url(scheme: AppInfo.urlScheme)) ?? URL(string: "\(AppInfo.urlScheme)://today")!
    }

    static func color(_ tone: CoachSnapshot.Tone) -> Color {
        switch tone {
        case .good: .green
        case .watch: .orange
        case .alert: .red
        case .neutral: .secondary
        }
    }
}

/// One tappable line in the medium widget: the weigh-in, the next measurement or an open check.
private struct CoachWidgetRow: Identifiable {
    let id: String
    let symbol: String
    let emoji: String
    let title: String
    let detail: String?
    let link: CoachSnapshot.Link
}

struct CoachWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CoachEntry

    private var shown: CoachSnapshot.Shown { entry.shown }

    var body: some View {
        familyView
            .widgetURL(CoachWidgetFormat.url(primaryLink))
    }

    @ViewBuilder
    private var familyView: some View {
        if entry.isEmpty {
            emptyView
        } else {
            switch family {
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            case .systemMedium: medium
            default: small
            }
        }
    }

    /// What a tap on the widget opens (the rows of the medium widget have their own links).
    private var primaryLink: CoachSnapshot.Link {
        entry.isEmpty ? .today : shown.primary
    }

    // MARK: Texts

    /// "🏋️ Gym" or "Coach" without a day type.
    private var dayLabel: String {
        if shown.isPaused { return "Paused" }
        return shown.dayType?.label ?? "Coach"
    }

    /// "74.6"; nil without an average.
    private var averageNumber: String? {
        shown.weight?.average.map { CoachWidgetFormat.number($0, 1) }
    }

    /// "+0.15 kg/wk · In range".
    private var statusText: String? {
        shown.weight?.statusText(number: CoachWidgetFormat.number)
    }

    private var statusColor: Color {
        CoachWidgetFormat.color(shown.weight?.tone ?? .neutral)
    }

    /// The one thing to do next: "Weigh in", "Waist · today", "2 of 4 checks done", "Set up your plan".
    private var nextLine: String? {
        if !shown.isSetUp { return "Set up your plan in Nina" }
        if shown.needsWeighIn { return "Weigh in this morning" }
        if let measurement = shown.measurement, measurement.isDue(on: shown.day) { return shown.measurementLine() }
        if shown.isOutdated { return "Open Nina for today" }
        if let checks = shown.checksText { return "Checks: " + checks.lowercased() }
        return shown.measurementLine()
    }

    private var nextSymbol: String {
        if !shown.isSetUp { return "list.bullet.clipboard" }
        if shown.needsWeighIn { return "scalemass" }
        if let measurement = shown.measurement, measurement.isDue(on: shown.day) { return measurement.symbol }
        if shown.isOutdated { return "arrow.clockwise" }
        if !shown.checks.isEmpty { return shown.openChecks.isEmpty ? "checkmark.circle.fill" : "checklist" }
        return shown.measurement?.symbol ?? "figure"
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(dayLabel)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            if let energy = shown.dayType?.energy, !shown.isPaused {
                Text(CoachWidgetFormat.kcal(energy))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            averageBlock
            Spacer(minLength: 2)
            if let nextLine {
                Label(nextLine, systemImage: nextSymbol)
                    .font(.caption2.weight(.medium))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// The 7-day average, big, with the rate and the status words under it.
    @ViewBuilder
    private var averageBlock: some View {
        if let averageNumber {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(averageNumber)
                    .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .privacySensitive()
                Text("kg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("7-day average")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        if let statusText {
            Text(statusText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(statusColor)
                .lineLimit(2)
                .privacySensitive()
        } else if averageNumber == nil {
            Text(shown.isSetUp ? "Weigh in a few mornings to see your average." : "Your coach plan lives in Nina.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }

    /// Home Screen, medium: the summary on the left, what is open on the right (each line opens it).
    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(dayLabel)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if let energy = shown.dayType?.energy, !shown.isPaused {
                    Text(CoachWidgetFormat.kcal(energy))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 2)
                averageBlock
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(rows) { row in
                    Link(destination: CoachWidgetFormat.url(row.link)) {
                        rowView(row)
                    }
                }
                if let summary = rowsSummary {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func rowView(_ row: CoachWidgetRow) -> some View {
        HStack(spacing: 6) {
            rowIcon(row)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(row.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if let detail = row.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func rowIcon(_ row: CoachWidgetRow) -> some View {
        if row.emoji.isEmpty {
            Image(systemName: row.symbol)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
        } else {
            Text(row.emoji)
                .font(.caption)
        }
    }

    /// The weigh-in, the next measurement, then the open checks – at most four lines.
    private var rows: [CoachWidgetRow] {
        guard shown.isSetUp, !shown.isPaused else { return [] }
        var rows: [CoachWidgetRow] = []
        if shown.needsWeighIn {
            rows.append(CoachWidgetRow(id: "weighIn", symbol: "scalemass", emoji: "", title: "Weigh in",
                                       detail: "this morning", link: .weighIn))
        }
        if let measurement = shown.measurement {
            rows.append(CoachWidgetRow(id: "measure", symbol: measurement.symbol, emoji: "", title: measurement.title,
                                       detail: shown.measurementWhen(), link: .measure(measurement.kind)))
        }
        for check in shown.openChecks {
            rows.append(CoachWidgetRow(id: "check." + check.id, symbol: "circle", emoji: check.emoji, title: check.name,
                                       detail: check.dose.isEmpty ? nil : check.dose, link: .check(check.id)))
        }
        return Array(rows.prefix(4))
    }

    /// Under the lines: "All 4 checks done", "Open Nina for today", "Set up your plan in Nina".
    private var rowsSummary: String? {
        if !shown.isSetUp { return "Set up your plan in Nina to see your day type, checks and measurements here." }
        if shown.isPaused { return "Coaching is paused – nothing to tick off." }
        if shown.isOutdated { return "Open Nina for today's checks." }
        guard !shown.checks.isEmpty else { return rows.isEmpty ? "Nothing open today." : nil }
        let hidden = shown.openChecks.count - rows.filter { $0.id.hasPrefix("check.") }.count
        if hidden > 0 { return "+\(hidden) more \(hidden == 1 ? "check" : "checks") · \(shown.checksText ?? "")" }
        return shown.openChecks.isEmpty ? "Checks: " + (shown.checksText ?? "").lowercased() : nil
    }

    // MARK: Lock Screen

    /// "🏋️ Gym · 74.6 kg" / "+0.15 kg/wk · In range" / "Weigh in this morning".
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(rectangularHeader)
                .font(.headline)
                .widgetAccentable()
                .lineLimit(1)
                .privacySensitive()
            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .lineLimit(1)
                    .privacySensitive()
            }
            if let nextLine {
                Text(nextLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rectangularHeader: String {
        guard let averageNumber else { return dayLabel }
        return "\(dayLabel) · \(averageNumber) kg"
    }

    /// "🏋️ Gym · 74.6 kg · In range".
    private var inline: some View {
        Text(inlineText)
            .privacySensitive()
    }

    private var inlineText: String {
        var parts = [dayLabel]
        if let averageNumber { parts.append("\(averageNumber) kg") }
        if let word = shown.weight?.word, !shown.isPaused { parts.append(word) }
        return parts.joined(separator: " · ")
    }

    // MARK: Before the app wrote anything

    @ViewBuilder
    private var emptyView: some View {
        switch family {
        case .accessoryInline:
            Text("Open Nina")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Coach").font(.headline).widgetAccentable()
                Text("Open Nina once to fill this in.").font(.caption).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Label("Coach", systemImage: "figure")
                    .font(.caption.weight(.semibold))
                Text("Open Nina once to fill this in.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
#endif
