import SwiftUI
import BinisoftKit
import NinaCore

/// "Protein  82 / 140 g" with a capsule bar. Limits (sugar, salt) turn orange when exceeded.
struct NutrientBar: View {
    let nutrient: Nutrient
    let value: Double
    let target: Double
    var unit: EnergyUnit = .kcal
    var compact = false

    private var fraction: Double { target > 0 ? value / target : 0 }
    private var over: Bool { fraction > 1.0001 }
    private var barColor: Color {
        if nutrient.isLimit && over { return .orange }
        return NutrientStyle.color(nutrient)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(nutrient == .sodium ? "Salt" : nutrient.shortTitle)
                    .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
                Spacer(minLength: 4)
                Text(valueText)
                    .font(compact ? .caption.monospacedDigit() : .subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(NutrientStyle.color(nutrient).opacity(0.16))
                    Capsule()
                        .fill(barColor.gradient)
                        .frame(width: max(compact ? 3 : 5, proxy.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(height: compact ? 5 : 7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(nutrient.title): \(valueText)")
        .animation(.smooth, value: value)
    }

    private var valueText: String {
        if nutrient == .sodium {
            return "\(Fmt.salt(fromSodium: value).replacingOccurrences(of: " g", with: "")) / \(Fmt.salt(fromSodium: target))"
        }
        let current = Fmt.nutrient(value, nutrient, unit: unit, showUnit: false)
        let goal = Fmt.nutrient(target, nutrient, unit: unit)
        return "\(current) / \(goal)"
    }
}

/// The food's emoji (its category's when it has none of its own) on a tile tinted by category –
/// foods are recognisable at a glance.
struct CategoryBadge: View {
    let category: FoodCategory
    var emoji: String?
    var size: CGFloat = 36

    var body: some View {
        Text(emoji ?? category.emoji)
            .font(.system(size: size * 0.55))
            .frame(width: size, height: size)
            .background(
                Color(hue: category.hue, saturation: 0.45, brightness: 0.95).opacity(0.22),
                in: .rect(cornerRadius: size * 0.3, style: .continuous)
            )
            .accessibilityLabel(category.title)
    }
}

/// A small rounded label ("High protein", a tag, an active filter).
struct Chip: View {
    let text: String
    var symbol: String?
    var tint: Color = .secondary
    var isSelected = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .foregroundStyle(isSelected ? Color.white : tint)
        .background(isSelected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.13)), in: .capsule)
    }
}

/// A big number with a label ("1,240 kcal eaten").
struct StatTile: View {
    let title: String
    let value: String
    var detail: String?
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A content card with a title, the house style for Insights and Today.
struct CardSection<Content: View>: View {
    let title: String
    var symbol: String?
    var trailing: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let symbol {
                    Image(systemName: symbol).foregroundStyle(Brand.accent)
                }
                Text(title).font(.headline)
                Spacer()
                if let trailing {
                    Text(trailing).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Small pill-shaped highlight badges for foods.
struct HighlightBadges: View {
    let highlights: [FoodHighlight]

    var body: some View {
        if !highlights.isEmpty {
            HStack(spacing: 4) {
                ForEach(highlights.prefix(3), id: \.self) { highlight in
                    Chip(text: highlight.title, tint: tint(highlight))
                }
            }
        }
    }

    private func tint(_ highlight: FoodHighlight) -> Color {
        switch highlight {
        case .highProtein: NutrientStyle.color(.protein)
        case .highFiber: NutrientStyle.color(.fiber)
        case .light: Brand.accent
        case .lowSugar: NutrientStyle.color(.sugar)
        case .salty: .orange
        }
    }
}

extension View {
    /// Keeps forms and cards at a readable width on the Mac and iPad.
    func readableWidth(_ width: CGFloat = 760) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }
}
