import Foundation

/// How an amount was entered and how it reads: "150 g", "2 × slice (60 g)", "½ serving".
public struct AmountText: Equatable, Sendable {
    /// How many of the unit (2 slices, 150 g).
    public var quantity: Double
    /// "g", "ml", "serving" or a portion label ("slice", "Scheibe").
    public var unitLabel: String
    /// g/ml per unit (1 for g and ml; the portion's weight; 1 for servings).
    public var unitAmount: Double
    public var baseUnit: BaseUnit

    public init(quantity: Double, unitLabel: String, unitAmount: Double, baseUnit: BaseUnit) {
        self.quantity = quantity
        self.unitLabel = unitLabel
        self.unitAmount = unitAmount
        self.baseUnit = baseUnit
    }

    /// Base amount (g, ml or servings).
    public var total: Double { quantity * unitAmount }

    /// True for plain g / ml / serving entries (no household portion).
    public var isBaseUnit: Bool {
        unitLabel.isEmpty || unitLabel == baseUnit.symbol || unitAmount == 1 && [BaseUnit.gram.symbol, BaseUnit.milliliter.symbol, BaseUnit.serving.symbol].contains(unitLabel)
    }

    /// "150 g", "2 × slice (60 g)", "1 medium (182 g)", "1.5 servings".
    public var text: String {
        if isBaseUnit {
            if baseUnit == .serving {
                return "\(Self.quantity(quantity)) \(quantity == 1 ? "serving" : "servings")"
            }
            return "\(Self.quantity(quantity)) \(baseUnit.symbol)"
        }
        let weight = "\(Self.quantity(total)) \(baseUnit == .serving ? "" : baseUnit.symbol)".trimmingCharacters(in: .whitespaces)
        if quantity == 1 { return "1 \(unitLabel) (\(weight))" }
        return "\(Self.quantity(quantity)) × \(unitLabel) (\(weight))"
    }

    /// "½", "1", "1.5", "150" – fractions people recognise, no needless decimals.
    public static func quantity(_ value: Double) -> String {
        let fractions: [(Double, String)] = [(0.25, "¼"), (0.5, "½"), (0.75, "¾")]
        let whole = value.rounded(.down)
        let rest = value - whole
        for (fraction, glyph) in fractions where abs(rest - fraction) < 0.001 && value < 10 {
            return whole == 0 ? glyph : "\(Int(whole))\(glyph)"
        }
        if value >= 100 { return String(Int(value.rounded())) }
        return NumberText.plain(value, decimals: value >= 10 ? 0 : 1)
    }
}
