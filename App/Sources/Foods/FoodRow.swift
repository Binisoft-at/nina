import SwiftUI
import BinisoftKit
import NinaCore

/// A food in lists: category, name (and the other language's), brand, energy per portion or 100 g.
struct FoodRow: View {
    let record: FoodRecord
    let language: FoodLanguage
    let unit: EnergyUnit
    var usage: FoodUsage?
    var showsHighlights = false
    var onQuickAdd: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if record.ref.kind == .recipe {
                Text(record.source == .recipe && record.unit == .serving && record.servings.isEmpty ? "🍱" : "🍲")
                    .font(.system(size: 20))
                    .frame(width: 36, height: 36)
                    .background(Color.teal.opacity(0.16), in: .rect(cornerRadius: 11, style: .continuous))
            } else {
                CategoryBadge(category: record.category, size: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(record.displayName(language))
                        .lineLimit(1)
                    if record.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if showsHighlights {
                    HighlightBadges(highlights: record.highlights)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.energy(portionEnergy, unit: unit, showUnit: false))
                    .font(.subheadline.monospacedDigit())
                Text(portionLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let onQuickAdd {
                Button(action: onQuickAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Brand.accent)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add \(record.displayName(language))")
            }
        }
        .contentShape(.rect)
    }

    private var subtitle: String {
        var parts: [String] = []
        if !record.brand.isEmpty { parts.append(record.brand) }
        if let other = record.secondaryName(language) { parts.append(other) }
        if let usage, usage.count > 0 { parts.append("\(usage.count)×") }
        if parts.isEmpty { parts.append(record.category.title) }
        return parts.joined(separator: " · ")
    }

    private var defaultAmount: AmountText { record.initialAmount(language: language) }

    private var portionEnergy: Double {
        record.nutrients(forAmount: defaultAmount.total).energy
    }

    private var portionLabel: String {
        if record.ref.kind == .recipe, record.unit == .serving { return "per serving" }
        return Fmt.amount(defaultAmount)
    }
}

extension FoodRecord {
    /// What the portion screen starts with: the usual amount, the first portion, or 100 g/ml.
    func initialAmount(language: FoodLanguage) -> AmountText {
        if usualAmount > 0 {
            for serving in servings where serving.amount > 0 {
                let count = usualAmount / serving.amount
                if abs(count - count.rounded()) < 0.02, count.rounded() >= 1, count.rounded() <= 6 {
                    return AmountText(quantity: count.rounded(), unitLabel: serving.label(language), unitAmount: serving.amount, baseUnit: unit)
                }
            }
            if unit == .serving {
                return AmountText(quantity: usualAmount, unitLabel: BaseUnit.serving.symbol, unitAmount: 1, baseUnit: .serving)
            }
            return AmountText(quantity: usualAmount.rounded(), unitLabel: unit.symbol, unitAmount: 1, baseUnit: unit)
        }
        if let serving = servings.first {
            return AmountText(quantity: 1, unitLabel: serving.label(language), unitAmount: serving.amount, baseUnit: unit)
        }
        if unit == .serving {
            return AmountText(quantity: 1, unitLabel: BaseUnit.serving.symbol, unitAmount: 1, baseUnit: .serving)
        }
        return AmountText(quantity: 100, unitLabel: unit.symbol, unitAmount: 1, baseUnit: unit)
    }
}
