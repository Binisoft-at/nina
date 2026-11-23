import SwiftUI
import BinisoftKit
import NinaCore

// The coach cards of Insights (Progress → Nutrition): protein meals in the Macros card, the
// average by day type and the compact body goal. Data in ProgressInsights.swift.

/// "Protein meals  21 of 28" with what counts as one, and an ⓘ (outside the row's one VoiceOver
/// element, so it stays reachable).
struct ProgressProteinMealsRow: View {
    let protein: ProgressProteinMeals

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            row
            InfoButton(BodyPageInfo.proteinMeals(minimum: Fmt.grams(protein.minimum)))
        }
    }

    private var row: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Protein meals")
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 4)
                Text(protein.period.text)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            BodyPageCapsule(progress: protein.period.share, tint: NutrientStyle.color(.protein))
            Text("A meal counts from \(Fmt.grams(protein.minimum)) of protein. Logged days up to yesterday.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Protein meals")
        .accessibilityValue("\(protein.period.text), counted from \(Fmt.grams(protein.minimum)) per meal")
    }
}

/// Average eaten vs. target per day type ("By day type").
struct ProgressTypeAveragesCard: View {
    let rows: [ProgressTypeAverage]
    let unit: EnergyUnit

    var body: some View {
        BodyPageInfoSection(title: "By day type", symbol: "calendar", trailing: "eaten / target", about: BodyPageInfo.byDayType) {
            ForEach(rows) { row in
                ProgressTypeAverageRow(row: row, unit: unit)
            }
            Text("Average per logged day of each type up to yesterday, against that type's calorie target. Paused days and days marked incomplete are left out.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "🏋️ Gym · 12 days   2,410 / 2,500 kcal" and a bar.
struct ProgressTypeAverageRow: View {
    let row: ProgressTypeAverage
    let unit: EnergyUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(valueText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            BodyPageCapsule(progress: row.share, tint: tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(Fmt.energy(row.averageIntake, unit: unit)) eaten on average, target \(Fmt.energy(row.averageTarget, unit: unit))")
    }

    /// "🏋️ Gym · 12 days".
    private var title: String {
        let name = row.emoji.isEmpty ? row.name : row.emoji + " " + row.name
        return "\(name) · \(row.days) \(row.days == 1 ? "day" : "days")"
    }

    private var valueText: String {
        Fmt.energy(row.averageIntake, unit: unit, showUnit: false) + " / " + Fmt.energy(row.averageTarget, unit: unit)
    }

    /// On target (the day-adherence band), over, or under – the colours of the calories chart.
    private var tint: Color {
        if row.isInBand { return Brand.accent }
        return row.isOver ? Color.orange : NutrientStyle.color(.protein).opacity(0.7)
    }
}

/// The long-term body goal, compact: one bar per row (lean mass, fat mass, body fat) and the
/// series it is measured with. A tap opens the Body page.
struct ProgressGoalCard: View {
    let goal: BodyPageGoal
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            app.showProgress(.body)
        } label: {
            CardSection(title: "Body goal", symbol: "target", trailing: goal.goalText) {
                content
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the Body page")
    }

    @ViewBuilder
    private var content: some View {
        if goal.card.isEmpty {
            Text(BodyGoalCard.emptyText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            ForEach(goal.card.rows) { row in
                ProgressGoalRow(row: row)
            }
        }
        if let measured {
            Text(measured)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// "Measured with: DEXA scan".
    private var measured: String? {
        guard let series = goal.seriesTitle, !goal.card.isEmpty else { return nil }
        return "Measured with: \(series)"
    }
}

/// "Lean mass   +0.6 of +2.1 kg" over a thin bar.
struct ProgressGoalRow: View {
    let row: BodyGoalRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.kind.title)
                    .font(.subheadline)
                Spacer(minLength: 4)
                Text(row.text)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(row.isMovedAway ? Color.orange : Color.secondary)
            }
            BodyPageCapsule(progress: row.progress, tint: tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.kind.title)
        .accessibilityValue(row.text)
    }

    private var tint: Color {
        switch row.kind {
        case .lean: Color.green
        case .fat: Color.orange
        case .bodyFat: Brand.accent
        }
    }
}
