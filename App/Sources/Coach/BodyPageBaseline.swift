import SwiftUI
import BinisoftKit
import NinaCore

// The baseline table (F6), pushed from the Measurements card of the body page: per site the
// value at the phase start (or the first reading), the latest one, the change and whether it is
// a real change (at least the tape's smallest detectable change).

/// Site | Start | Last | Change | Real change?, plus the gain-phase line.
struct BodyPageBaselineView: View {
    let rows: [GirthChange]
    let since: DayKey?
    let gainLine: String?

    var body: some View {
        ScrollView {
            BodyPageInfoSection(title: "Baseline", symbol: "tablecells", trailing: sinceText,
                                about: BodyPageInfo.baseline(sincePhase: since != nil)) {
                BodyPageBaselineGrid(rows: rows)
                if let gainLine {
                    Text("This phase: " + gainLine)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("A real change is at least the tape's smallest detectable change: 1.0 cm, or 0.5 cm for arm, neck and calf. Smaller changes are “no clear change”. Standard readings only (morning, before eating).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .readableWidth(760)
        }
        .background(Color.groupedBackground)
        .navigationTitle("Baseline")
    }

    /// "since 7 Jan" (the phase start), else "from the first reading".
    private var sinceText: String {
        since.map { "since " + Fmt.shortDay($0) } ?? "from the first reading"
    }
}

/// The table itself.
struct BodyPageBaselineGrid: View {
    let rows: [GirthChange]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                Text("Site")
                Text("Start")
                Text("Last")
                Text("Change")
                Text("Real change?")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Divider()
            ForEach(rows, id: \.site) { row in
                GridRow {
                    Text(row.site.title)
                        .font(.footnote.weight(.medium))
                    BodyPageBaselineValue(value: row.from.value, day: row.from.day)
                    BodyPageBaselineValue(value: row.to.value, day: row.to.day)
                    Text(BodyPageText.signed(row.change, decimals: 1) + " cm")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(row.isClear ? Brand.accent : Color.primary)
                    Text(row.isClear ? "Yes" : "No")
                        .font(row.isClear ? Font.footnote.weight(.semibold) : Font.footnote)
                        .foregroundStyle(row.isClear ? Brand.accent : Color.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Baseline table")
        .accessibilityValue(rows.map { BodyPageBaselineGrid.spoken($0) }.joined(separator: ". "))
    }

    /// "Waist: 84.0 cm on 7 Jan to 85.2 cm on 4 Feb, +1.2 cm, a real change".
    static func spoken(_ row: GirthChange) -> String {
        let from = BodyPageText.centimeters(row.from.value) + " on " + Fmt.shortDay(row.from.day)
        let to = BodyPageText.centimeters(row.to.value) + " on " + Fmt.shortDay(row.to.day)
        let change = BodyPageText.signed(row.change, decimals: 1) + " cm"
        return "\(row.site.title): \(from) to \(to), \(change), " + (row.isClear ? "a real change" : GirthTrend.noClearChange)
    }
}

/// "84.0" over "7 Jan".
struct BodyPageBaselineValue: View {
    let value: Double
    let day: DayKey

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value.formatted(.number.precision(.fractionLength(1))))
                .font(.footnote.monospacedDigit())
            Text(Fmt.shortDay(day))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
