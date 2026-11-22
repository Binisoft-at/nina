import SwiftUI
import SwiftData
import Charts
import BinisoftKit
import NinaCore

// Screens pushed from the body page: one tape site over time, all measurements, all check-ins.
// (All weigh-ins is `WeightView`, App/Sources/Insights/WeightView.swift.)

// MARK: - Site detail

/// One tape site over time: standard readings joined by a line with the ±TEM band, other
/// readings as hollow dots, the change since the phase start and the 4-week change. The readings
/// below open their measurement; swipe deletes that reading (the other sites of the session
/// stay), with Undo.
struct BodyDetailsSiteView: View {
    let site: BodySite
    let since: DayKey?
    @Environment(AppModel.self) private var app
    @State private var includeAll = false
    @State private var detail: BodyDetailsSiteData?

    var body: some View {
        List {
            if let detail {
                if detail.rows.isEmpty {
                    emptySection
                } else {
                    chartSection(detail)
                    readingsSection(detail)
                }
            }
        }
        .navigationTitle(site.title)
        .task(id: "\(app.dataVersion)-\(includeAll)") {
            detail = BodyDetailsSiteData.load(site: site, store: app.store, since: since, includeAll: includeAll)
        }
    }

    private var emptySection: some View {
        Section {
            Text("No \(site.title.lowercased()) readings yet.")
                .foregroundStyle(.secondary)
            measureButton
        } footer: {
            Text(site.landmark)
        }
    }

    private func chartSection(_ detail: BodyDetailsSiteData) -> some View {
        Section {
            BodyDetailsSiteChart(detail: detail, tem: site.tem)
                .frame(height: 200)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(site.title) chart")
                .accessibilityValue(summary(detail))
            if let latest = detail.latest {
                LabeledContent("Latest", value: BodyPageText.centimeters(latest))
            }
            if let change = detail.change, change.from.day < change.to.day {
                LabeledContent("Since \(Fmt.shortDay(change.from.day))", value: changeText(change.change))
            }
            if let fourWeek = detail.fourWeek {
                LabeledContent("4-week change", value: changeText(fourWeek))
            }
            Toggle("Include readings that aren't standard", isOn: $includeAll)
            measureButton
        } footer: {
            Text(footer)
        }
    }

    /// Opens the measure sheet for this site only (and the other side when both are measured).
    private var measureButton: some View {
        Button("Measure \(site.title)", systemImage: "ruler") {
            app.sheet = .measure(.site(site), nil)
        }
    }

    private func readingsSection(_ detail: BodyDetailsSiteData) -> some View {
        Section("Readings") {
            ForEach(detail.rows) { row in
                Button {
                    app.sheet = BodyDetailsEdit.sheet(for: row.measurement, settings: app.settings)
                } label: {
                    BodyDetailsReadingRow(row: row, today: app.today)
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { delete(row) }
                }
                .contextMenu {
                    Button("Edit", systemImage: "pencil") {
                        app.sheet = BodyDetailsEdit.sheet(for: row.measurement, settings: app.settings)
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { delete(row) }
                }
            }
        }
    }

    /// Deletes this site's reading only: the other sites measured in the same session stay. The
    /// whole record goes to the trash only when nothing else is left in it (a value of a site this
    /// build doesn't know yet counts, so it isn't lost). Both toasts have Undo.
    private func delete(_ row: BodyDetailsSiteData.Row) {
        var draft = row.measurement.draft
        draft.values[site] = nil
        if draft.values.isEmpty {
            app.trash(row.measurement)
        } else {
            _ = app.saveMeasurement(draft, editing: row.measurement, message: "\(site.title) reading deleted")
        }
    }

    /// "+1.2 cm", or "+0.4 cm · no clear change" below the site's MDC.
    private func changeText(_ change: Double) -> String {
        let text = BodyPageText.signed(change, decimals: 1) + " cm"
        return GirthTrend.isClear(change, site: site) ? text : text + " · " + GirthTrend.noClearChange
    }

    private var footer: String {
        let mdc = site.mdc.formatted(.number.precision(.fractionLength(1)))
        return "Changes under \(mdc) cm are within measuring error for this site. Hollow dots: readings that weren't taken in the morning before eating (left out of the trend unless included). Where: \(site.landmark)."
    }

    private func summary(_ detail: BodyDetailsSiteData) -> String {
        var parts: [String] = []
        if let latest = detail.latest { parts.append("\(site.title) \(BodyPageText.centimeters(latest))") }
        if let change = detail.change, change.from.day < change.to.day {
            parts.append(change.isClear ? change.label : "\(GirthTrend.noClearChange) since \(Fmt.shortDay(change.from.day))")
        }
        return parts.joined(separator: ", ")
    }
}

/// The readings of one site, computed from the live tape measurements.
struct BodyDetailsSiteData {
    struct Point: Identifiable {
        let id: String
        let date: Date
        let value: Double
        let isStandard: Bool
    }

    struct Row: Identifiable {
        let id: String
        let measurement: BodyMeasurement
        let day: DayKey
        let time: Date
        let value: Double
        let isStandard: Bool
        let conditions: String
    }

    /// The readings the trend uses (standard ones unless all are included), one per day.
    let trend: [Point]
    /// Readings that aren't standard (hollow dots), one per day.
    let others: [Point]
    /// Every measurement with this site, newest first.
    let rows: [Row]
    let change: GirthChange?
    let fourWeek: Double?
    let latest: Double?

    @MainActor
    static func load(site: BodySite, store: NinaStore, since: DayKey?, includeAll: Bool) -> BodyDetailsSiteData {
        let calendar = store.calendar
        let measurements = store.measurements(kind: .tape)
        let records = measurements.compactMap(\.tapeRecord)
        let trendReadings = GirthTrend.readings(site, in: records, includeNonStandard: includeAll)
        let every = GirthTrend.readings(site, in: records, includeNonStandard: true)
        let trend = trendReadings.map { reading in
            Point(id: "t-" + reading.day.rawValue, date: reading.day.date(calendar: calendar), value: reading.value,
                  isStandard: reading.isStandard)
        }
        let others = every.filter { !$0.isStandard }.map { reading in
            Point(id: "o-" + reading.day.rawValue, date: reading.day.date(calendar: calendar), value: reading.value, isStandard: false)
        }
        let rows: [Row] = measurements.reversed().compactMap { measurement in
            guard let value = measurement.bodyValues[site] else { return nil }
            return Row(id: measurement.uuid.uuidString, measurement: measurement, day: measurement.dayKey, time: measurement.time,
                       value: value, isStandard: measurement.isStandard, conditions: measurement.conditions)
        }
        return BodyDetailsSiteData(
            trend: trend, others: others, rows: rows,
            change: GirthTrend.change(site, readings: trendReadings, since: since, calendar: calendar),
            fourWeek: GirthTrend.fourWeekChange(trendReadings, calendar: calendar),
            latest: every.last?.value)
    }
}

/// The site's chart: the trend line with its ±TEM band, hollow dots for the other readings.
struct BodyDetailsSiteChart: View {
    let detail: BodyDetailsSiteData
    let tem: Double

    var body: some View {
        Chart {
            bandMarks
            lineMarks
            otherMarks
        }
        .chartYScale(domain: .automatic(includesZero: false))
    }

    @ChartContentBuilder
    private var bandMarks: some ChartContent {
        ForEach(detail.trend) { point in
            AreaMark(x: .value("Day", point.date, unit: .day),
                     yStart: .value("Band from", point.value - tem), yEnd: .value("Band to", point.value + tem))
                .foregroundStyle(Brand.accent.opacity(0.12))
        }
    }

    @ChartContentBuilder
    private var lineMarks: some ChartContent {
        ForEach(detail.trend) { point in
            LineMark(x: .value("Day", point.date, unit: .day), y: .value("cm", point.value))
                .foregroundStyle(Brand.accent)
            PointMark(x: .value("Day", point.date, unit: .day), y: .value("cm", point.value))
                .foregroundStyle(Brand.accent)
                .symbolSize(28)
        }
    }

    @ChartContentBuilder
    private var otherMarks: some ChartContent {
        ForEach(detail.others) { point in
            PointMark(x: .value("Day", point.date, unit: .day), y: .value("Not standard", point.value))
                .symbol {
                    Circle()
                        .strokeBorder(Color.secondary, lineWidth: 1.5)
                        .frame(width: 8, height: 8)
                }
        }
    }
}

/// A reading: day, conditions, value.
struct BodyDetailsReadingRow: View {
    let row: BodyDetailsSiteData.Row
    let today: DayKey

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.dayTitle(row.day, today: today))
                Text(BodyDetailsText.conditions(row.conditions, time: row.time))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(BodyPageText.centimeters(row.value))
                .monospacedDigit()
                .foregroundStyle(row.isStandard ? Color.primary : Color.secondary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - All measurements

/// Every tape session and body-fat assessment, newest first: tap edits, swipe deletes (Undo).
struct BodyDetailsMeasurementsView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<BodyMeasurement> { $0.deletedAt == nil }, sort: \BodyMeasurement.time, order: .reverse)
    private var measurements: [BodyMeasurement]

    var body: some View {
        List {
            ForEach(measurements) { measurement in
                Button {
                    app.sheet = BodyDetailsEdit.sheet(for: measurement, settings: app.settings)
                } label: {
                    BodyDetailsMeasurementRow(measurement: measurement, today: app.today)
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { app.trash(measurement) }
                }
                .contextMenu {
                    Button("Edit", systemImage: "pencil") {
                        app.sheet = BodyDetailsEdit.sheet(for: measurement, settings: app.settings)
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { app.trash(measurement) }
                }
            }
        }
        .overlay {
            if measurements.isEmpty {
                ContentUnavailableView {
                    Label("No measurements yet", systemImage: "ruler")
                } description: {
                    Text("Tape measurements and body-fat values show up here. Measure in the morning, before eating, at the same spots each time.")
                } actions: {
                    Button("Measure Now") { app.measureNow() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Measurements")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Tape Measurements…", systemImage: "ruler") { app.measureNow() }
                    Button("Body Fat…", systemImage: "percent") { app.sheet = .assessment(nil) }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .bodyHistoryExportMenu()
    }
}

/// A measurement in a list: "Tape · 6 sites", the values, the day.
struct BodyDetailsMeasurementRow: View {
    let measurement: BodyMeasurement
    let today: DayKey

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(BodyDetailsText.title(measurement))
                Text(BodyDetailsText.values(measurement))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(Fmt.dayTitle(measurement.dayKey, today: today))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Which sheet edits a measurement: an assessment, the weekly sites, or the full set.
enum BodyDetailsEdit {
    @MainActor
    static func sheet(for measurement: BodyMeasurement, settings: NinaSettings) -> AppSheet {
        if measurement.recordKind == .assessment { return .assessment(measurement) }
        let routine = settings.plan.isSetUp ? settings.plan.routine : CoachPlan.Routine.defaults(for: settings.body.sex)
        let weekly = Set(routine.weeklySites.map(\.base))
        let sites = measurement.bodyValues.sites.keys
        let isWeekly = !sites.isEmpty && sites.allSatisfy { weekly.contains($0.base) }
        return .measure(isWeekly ? .weekly : .full, measurement)
    }
}

/// Text for measurement rows (the body page lists and Recently Deleted).
enum BodyDetailsText {
    /// The sites in the measure sheet's order, then the left-side ones.
    static let siteOrder: [BodySite] = BodySite.mainSites + [.armLeft, .thighLeft, .calfLeft]

    /// "Body fat 20.1 %", "Waist", "Tape · 6 sites".
    static func title(_ measurement: BodyMeasurement) -> String {
        let values = measurement.bodyValues
        switch measurement.recordKind {
        case .assessment:
            return "Body fat" + (values.bodyFat.map { " " + BodyPageText.percent($0) } ?? "")
        case .tape:
            let sites = siteOrder.filter { values[$0] != nil }
            if sites.count == 1 { return sites[0].title }
            return "Tape · \(sites.count) sites"
        }
    }

    /// "Waist 84.0 · Chest 101.5 cm" or "DEXA scan · lean 64.0 kg · fat 16.0 kg".
    static func values(_ measurement: BodyMeasurement) -> String {
        let values = measurement.bodyValues
        switch measurement.recordKind {
        case .assessment:
            var parts: [String] = [(measurement.bodyMethod ?? .estimate).title]
            if !measurement.device.isEmpty { parts.append(measurement.device) }
            if let lean = values.leanKg { parts.append("lean " + Fmt.kilograms(lean)) }
            if let fat = values.fatKg { parts.append("fat " + Fmt.kilograms(fat)) }
            return parts.joined(separator: " · ")
        case .tape:
            let parts = siteOrder.compactMap { site in
                values[site].map { "\(site.title) \($0.formatted(.number.precision(.fractionLength(1))))" }
            }
            let text = parts.isEmpty ? "No values" : parts.joined(separator: " · ") + " cm"
            return measurement.isStandard ? text : text + " · not standard"
        }
    }

    /// "07:10 · morning, before eating" or "18:30 · after training · not standard".
    static func conditions(_ conditions: String, time: Date) -> String {
        let titles = BodyProtocol.tags(conditions).compactMap { BodyCondition(rawValue: $0)?.title.lowercased() }
        var parts = [Fmt.time(time)]
        if !titles.isEmpty { parts.append(titles.joined(separator: ", ")) }
        if !BodyProtocol.isStandard(conditions) { parts.append("not standard") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - All check-ins

/// Every saved check-in, newest first, with its 7-day average, rate and decision; a tap opens
/// that week's check-in.
struct BodyDetailsCheckInsView: View {
    @Environment(AppModel.self) private var app
    @State private var rows: [BodyPageCheckIn] = []

    var body: some View {
        List {
            ForEach(rows) { row in
                Button {
                    app.present(.checkIn(row.week))
                } label: {
                    BodyPageCheckInRow(checkIn: row)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView("No check-ins yet", systemImage: "checkmark.seal",
                                       description: Text("Your weekly check-ins show up here."))
            }
        }
        .navigationTitle("Check-ins")
        .task(id: loadKey) {
            rows = BodyPageData.checkIns(CoachContext.load(app: app, day: app.today))
        }
    }

    /// Reload on data changes and when Apple Health weigh-ins arrive (the average and rate of a
    /// check-in that used them are recomputed live, never stored).
    private var loadKey: String {
        "\(app.dataVersion)-\(app.health.weightSamples.count)"
    }
}
