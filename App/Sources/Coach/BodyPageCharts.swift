import SwiftUI
import Charts
import BinisoftKit
import NinaCore

// The weight card (F4) and the body composition card (F7) of the body page, with their charts.

// MARK: - Weight

/// 7-day average, weekly change and rate, then the chart: morning weigh-ins, the 7-day average,
/// the phase corridor, the target and review lines, tagged readings and paused spans.
struct BodyPageWeightCard: View {
    let weight: BodyPageWeight
    @Environment(AppModel.self) private var app
    @AppStorage("nina.body.weightRange") private var range: BodyPageRange = .month
    @AppStorage("nina.body.tip.highCarb") private var tipSeen = false

    var body: some View {
        CardSection(title: "Weight", symbol: "scalemass.fill", trailing: trailing) {
            if weight.hasWeighIns {
                BodyPageWeightStats(weight: weight)
                Picker("Range", selection: $range) {
                    ForEach(BodyPageRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if let chart = weight.chart(range) {
                    BodyPageWeightChartView(chart: chart)
                        .frame(height: 220)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Weight chart")
                        .accessibilityValue(weight.summaryText)
                    BodyPageWeightLegend(chart: chart)
                }
                notes
            } else {
                Text("Weigh yourself in the morning, after the bathroom and before breakfast. Nina shows your 7-day average and how fast it moves – single days swing with water.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Log Weight", systemImage: "plus") {
                    app.sheet = .weight(nil)
                }
            }
        }
    }

    private var trailing: String? {
        if let average = weight.average { return Fmt.kilograms(average) }
        return weight.estimate.map { "~" + Fmt.kilograms($0) }
    }

    @ViewBuilder
    private var notes: some View {
        ForEach(noteLines, id: \.self) { line in
            Text(line)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !tipSeen {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb")
                    .foregroundStyle(Brand.accent)
                Text("The morning after a high-carb day often reads 0.3–0.6 kg heavier; the 7-day average evens it out.")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("OK") { tipSeen = true }
                    .font(.footnote.weight(.semibold))
            }
        }
    }

    private var noteLines: [String] {
        var lines: [String] = []
        if let prompt = weight.averagePrompt { lines.append(prompt + ".") }
        if let note = weight.rateNote { lines.append(note) }
        if let noise = weight.noise {
            lines.append("Your normal day-to-day swing: ±\(Fmt.kilograms(noise)).")
        }
        if weight.usesHealth {
            lines.append("Includes weigh-ins from Apple Health, read on this device and never stored by Nina.")
        }
        return lines
    }
}

/// 7-day average · this week · rate.
struct BodyPageWeightStats: View {
    let weight: BodyPageWeight

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            StatTile(title: "7-day average", value: averageText, detail: averageDetail, tint: Brand.accent)
            StatTile(title: "This week", value: weekText, detail: weekDetail)
            StatTile(title: "Rate", value: rateText, detail: weight.rate == nil ? nil : "a week")
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var averageText: String {
        if let average = weight.average { return Fmt.kilograms(average) }
        return weight.estimate.map { Fmt.kilograms($0) } ?? "–"
    }

    private var averageDetail: String? {
        weight.average == nil && weight.estimate != nil ? "estimate" : nil
    }

    private var weekText: String {
        guard let change = weight.weeklyChange else { return "–" }
        return BodyPageText.signed(change.kilograms, decimals: 2) + " kg"
    }

    private var weekDetail: String? {
        guard let change = weight.weeklyChange else { return nil }
        return BodyPageText.signed(change.percent, decimals: 1) + " %"
    }

    private var rateText: String {
        guard let rate = weight.rate else { return "–" }
        return BodyPageText.signed(rate, decimals: 2) + " kg"
    }
}

/// The weight chart of one range.
struct BodyPageWeightChartView: View {
    let chart: BodyPageWeightChart

    var body: some View {
        Chart {
            pauseMarks
            reviewMarks
            corridorMarks
            otherMarks
            morningMarks
            averageMarks
            lineMarks
        }
        .chartXScale(domain: chart.start...chart.end)
        .chartYScale(domain: chart.yDomain)
    }

    @ChartContentBuilder
    private var pauseMarks: some ChartContent {
        ForEach(chart.pauses) { span in
            RectangleMark(xStart: .value("Paused from", span.start), xEnd: .value("Paused until", span.end),
                          yStart: .value("Low", chart.yDomain.lowerBound), yEnd: .value("High", chart.yDomain.upperBound))
                .foregroundStyle(Color.secondary.opacity(0.12))
        }
    }

    @ChartContentBuilder
    private var reviewMarks: some ChartContent {
        if let review = chart.review {
            RectangleMark(xStart: .value("From", chart.start), xEnd: .value("To", chart.end),
                          yStart: .value("Review from", review.lowerBound), yEnd: .value("Review to", review.upperBound))
                .foregroundStyle(Color.purple.opacity(0.08))
            RuleMark(y: .value("Review", review.lowerBound))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.purple.opacity(0.7))
                .annotation(position: .bottom, alignment: .leading) {
                    Text("Review").font(.caption2).foregroundStyle(.secondary)
                }
        }
    }

    @ChartContentBuilder
    private var corridorMarks: some ChartContent {
        ForEach(chart.corridor) { band in
            AreaMark(x: .value("Day", band.date, unit: .day),
                     yStart: .value("Corridor from", band.low), yEnd: .value("Corridor to", band.high))
                .foregroundStyle(Brand.accent.opacity(0.14))
        }
    }

    @ChartContentBuilder
    private var otherMarks: some ChartContent {
        ForEach(chart.others) { dot in
            PointMark(x: .value("Day", dot.date, unit: .day), y: .value("Later weigh-in", dot.kilograms))
                .foregroundStyle(Color.secondary.opacity(0.25))
                .symbolSize(12)
        }
    }

    @ChartContentBuilder
    private var morningMarks: some ChartContent {
        ForEach(chart.plainMornings) { dot in
            PointMark(x: .value("Day", dot.date, unit: .day), y: .value("Morning weight", dot.kilograms))
                .foregroundStyle(Color.secondary.opacity(0.6))
                .symbolSize(18)
        }
        ForEach(chart.taggedMornings) { dot in
            PointMark(x: .value("Day", dot.date, unit: .day), y: .value("Tagged weight", dot.kilograms))
                .foregroundStyle(Color.orange)
                .symbol(.diamond)
                .symbolSize(36)
        }
    }

    @ChartContentBuilder
    private var averageMarks: some ChartContent {
        ForEach(chart.trend) { point in
            LineMark(x: .value("Day", point.date, unit: .day), y: .value("Trend", point.kilograms),
                     series: .value("Line", "Trend"))
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.secondary.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }
        ForEach(chart.averages) { point in
            LineMark(x: .value("Day", point.date, unit: .day), y: .value("7-day average", point.kilograms),
                     series: .value("Line", "7-day average"))
                .interpolationMethod(.monotone)
                .foregroundStyle(Brand.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
        }
    }

    @ChartContentBuilder
    private var lineMarks: some ChartContent {
        if let target = chart.target {
            RuleMark(y: .value("Target", target))
                .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                .foregroundStyle(.secondary)
                .annotation(position: .top, alignment: .leading) {
                    Text("Target \(Fmt.kilograms(target))").font(.caption2).foregroundStyle(.secondary)
                }
        }
        if let end = chart.phaseEnd {
            RuleMark(x: .value("Phase end", end))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.secondary)
                .annotation(position: .top, alignment: .trailing) {
                    Text("Phase end").font(.caption2).foregroundStyle(.secondary)
                }
        }
    }
}

/// What the marks mean.
struct BodyPageWeightLegend: View {
    let chart: BodyPageWeightChart

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                item("Morning", shape: AnyView(Circle().fill(Color.secondary.opacity(0.6)).frame(width: 7, height: 7)))
                item("7-day average", shape: AnyView(Capsule().fill(Brand.accent).frame(width: 14, height: 3)))
                if !chart.trend.isEmpty {
                    item("Trend", shape: AnyView(Capsule().fill(Color.secondary.opacity(0.7)).frame(width: 10, height: 1.5)))
                }
            }
            if hasSecondRow {
                HStack(spacing: 12) {
                    if !chart.corridor.isEmpty {
                        item("Your corridor", shape: AnyView(RoundedRectangle(cornerRadius: 2).fill(Brand.accent.opacity(0.25)).frame(width: 12, height: 9)))
                    }
                    if chart.hasTagged {
                        item("Tagged", shape: AnyView(Image(systemName: "diamond.fill").font(.system(size: 8)).foregroundStyle(Color.orange)))
                    }
                    if !chart.pauses.isEmpty {
                        item("Paused", shape: AnyView(RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.25)).frame(width: 12, height: 9)))
                    }
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityHidden(true)
    }

    private var hasSecondRow: Bool {
        !chart.corridor.isEmpty || chart.hasTagged || !chart.pauses.isEmpty
    }

    private func item(_ title: String, shape: AnyView) -> some View {
        HStack(spacing: 4) {
            shape
            Text(title)
        }
    }
}

// MARK: - Composition

/// Body fat by method with error bands, lean and fat mass, the waist ratios, FFMI and the next
/// full measurement.
struct BodyPageCompositionCard: View {
    let composition: BodyPageComposition
    let today: DayKey

    var body: some View {
        CardSection(title: "Body composition", symbol: "percent", trailing: composition.latestTitle) {
            if composition.hasBodyFat {
                BodyPageFatChart(points: composition.points)
                    .frame(height: 180)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Body fat chart")
                    .accessibilityValue(chartSummary)
                ForEach(composition.series) { series in
                    BodyPageFatSeriesRow(series: series)
                }
            } else {
                Text("No body-fat value yet. Add one from a scale, a DEXA scan or a BIA device, or measure your waist and neck for the free tape estimate.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let latest = composition.latest {
                BodyPageLeanFatBar(composition: latest, day: composition.latestDay)
            }
            ForEach(changeLines, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ratios
            ForEach(footLines, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var ratios: some View {
        if composition.waistToHeight != nil || composition.ffmi != nil || composition.waistToHip != nil {
            HStack(alignment: .top, spacing: 20) {
                if let ratio = composition.waistToHeight {
                    StatTile(title: "Waist-to-height", value: ratio.formatted(.number.precision(.fractionLength(2))),
                             detail: BodyComposition.waistToHeightNote)
                }
                if let ratio = composition.waistToHip {
                    StatTile(title: "Waist-to-hip", value: ratio.formatted(.number.precision(.fractionLength(2))))
                }
                if let ffmi = composition.ffmi {
                    StatTile(title: "FFMI", value: ffmi.formatted(.number.precision(.fractionLength(1))), detail: ffmiDetail)
                }
            }
        }
    }

    private var ffmiDetail: String? {
        composition.normalisedFFMI.map { "normalised " + $0.formatted(.number.precision(.fractionLength(1))) }
    }

    private var chartSummary: String {
        composition.series.map { "\($0.title) \(BodyPageText.percent($0.latest)) on \(Fmt.shortDay($0.latestDay))" }
            .joined(separator: ", ")
    }

    /// The change since the tracking series' previous value, in lean and fat mass.
    private var changeLines: [String] {
        guard let change = composition.change else { return [] }
        var lean = "lean " + BodyPageText.signed(change.lean, decimals: 1) + " kg"
        if change.isLeanWithinError { lean += " (" + CompositionChange.withinErrorText + ")" }
        var fat = "fat " + BodyPageText.signed(change.fat, decimals: 1) + " kg"
        if change.isFatWithinError { fat += " (" + CompositionChange.withinErrorText + ")" }
        var lines = ["Since the value before: \(lean), \(fat)."]
        if let share = change.leanShare {
            lines.append("Lean share of the gain: \(Fmt.percent(share)).")
        }
        return lines
    }

    private var footLines: [String] {
        var lines: [String] = []
        if let note = composition.tapeNote { lines.append(note) }
        if let next = composition.nextFull {
            let overdue = next.overdueDays(on: today)
            if next.day == today {
                lines.append("Full measurement due today")
            } else if overdue > 0 {
                lines.append("Full measurement due since \(Fmt.shortDay(next.day))")
            } else {
                lines.append("Next full measurement \(Fmt.shortDay(next.day))")
            }
        }
        return lines
    }
}

/// The body-fat values per method and device, with each method's error band.
struct BodyPageFatChart: View {
    let points: [BodyPageFatPoint]

    var body: some View {
        Chart {
            bandMarks
            valueMarks
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartLegend(position: .bottom)
    }

    @ChartContentBuilder
    private var bandMarks: some ChartContent {
        ForEach(points) { point in
            if let low = point.low, let high = point.high {
                RuleMark(x: .value("Day", point.date, unit: .day),
                         yStart: .value("Band from", low), yEnd: .value("Band to", high))
                    .lineStyle(StrokeStyle(lineWidth: 8, lineCap: .round))
                    .foregroundStyle(by: .value("Method", point.series))
                    .opacity(0.2)
            }
        }
    }

    @ChartContentBuilder
    private var valueMarks: some ChartContent {
        ForEach(points) { point in
            LineMark(x: .value("Day", point.date, unit: .day), y: .value("Body fat", point.bodyFat),
                     series: .value("Method", point.series))
                .foregroundStyle(by: .value("Method", point.series))
            PointMark(x: .value("Day", point.date, unit: .day), y: .value("Body fat", point.bodyFat))
                .foregroundStyle(by: .value("Method", point.series))
                .symbolSize(24)
        }
    }
}

/// "DEXA scan  18.4 % · ±1.5 · 12 Jan", the tracking series marked.
struct BodyPageFatSeriesRow: View {
    let series: BodyPageFatSeries

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(series.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(BodyPageText.percent(series.latest))
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = ["±" + series.band, Fmt.shortDay(series.latestDay), "\(series.count) \(series.count == 1 ? "value" : "values")"]
        if series.band == "unknown" { parts[0] = "error unknown" }
        if series.isTracking { parts.append("tracks your goal") }
        return parts.joined(separator: " · ")
    }
}

/// Lean and fat mass as one split bar.
struct BodyPageLeanFatBar: View {
    let composition: BodyComposition
    let day: DayKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Lean \(Fmt.kilograms(composition.leanKg))")
                    .foregroundStyle(Color.green)
                Spacer()
                Text("Fat \(Fmt.kilograms(composition.fatKg))")
                    .foregroundStyle(Color.orange)
            }
            .font(.subheadline.weight(.medium).monospacedDigit())
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    Capsule()
                        .fill(Color.green.gradient)
                        .frame(width: max(4, proxy.size.width * CGFloat(leanShare) - 1))
                    Capsule()
                        .fill(Color.orange.gradient)
                }
            }
            .frame(height: 10)
            if let source {
                Text(source)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lean and fat mass")
        .accessibilityValue("Lean \(Fmt.kilograms(composition.leanKg)), fat \(Fmt.kilograms(composition.fatKg))")
    }

    /// "From the value on 12 Jan, as measured by the device".
    private var source: String? {
        guard let day else { return nil }
        let text = "From the value on " + Fmt.shortDay(day)
        return composition.isMeasured ? text + ", as measured by the device" : text
    }

    private var leanShare: Double {
        let total = composition.leanKg + composition.fatKg
        guard total > 0 else { return 0.5 }
        return min(0.98, max(0.02, composition.leanKg / total))
    }
}
