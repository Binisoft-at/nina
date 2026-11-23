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

    /// "g" or "ml": a measure, not a household portion – also "g" on a drink, whose gram option
    /// has 1/density ml per unit (it gets gram steps and chips, and reads "200 g (194 ml)").
    public static func isBaseLabel(_ label: String) -> Bool {
        label == BaseUnit.gram.symbol || label == BaseUnit.milliliter.symbol
    }

    /// "150 g", "2 × slice (60 g)", "1 medium (182 g)", "1 glass (250 ml)", "200 g (194 ml)",
    /// "½ serving", "1.5 servings".
    public var text: String {
        text(count: Self.quantity, measure: Self.quantity)
    }

    /// The same text with the app's number formatting: `count` formats how many units (portions,
    /// servings), `measure` the grams and millilitres.
    public func text(count: (Double) -> String, measure: (Double) -> String) -> String {
        let symbol = baseUnit.symbol
        // "200 g (194 ml)": grams of a drink (or ml of a food) – a measure, never "200 × g".
        if Self.isBaseLabel(unitLabel), unitLabel != symbol, baseUnit != .serving {
            return "\(measure(quantity)) \(unitLabel) (\(measure(total)) \(symbol))"
        }
        if isBaseUnit {
            if baseUnit == .serving {
                return "\(count(quantity)) \(quantity <= 1 ? "serving" : "servings")"
            }
            return "\(measure(quantity)) \(symbol)"
        }
        let label = PortionLabel.display(unitLabel, baseUnit: baseUnit)
        let weight = baseUnit == .serving ? "" : " (\(measure(total)) \(symbol))"
        if quantity == 1 { return "1 \(label)\(weight)" }
        return "\(count(quantity)) × \(label)\(weight)"
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

    /// The amount as an input field shows it: quarters as "½" / "1¼" below 10, otherwise up to two
    /// decimals with `decimalSeparator` ("12.5", "37,5", "0.33"). Precise enough that showing a
    /// value never changes it: the field writes back only what the person types.
    public static func fieldText(_ value: Double, decimalSeparator: String = ".") -> String {
        guard value.isFinite else { return "" }
        let whole = value.rounded(.down)
        let rest = value - whole
        let fractions: [(Double, String)] = [(0.25, "¼"), (0.5, "½"), (0.75, "¾")]
        for (fraction, glyph) in fractions where abs(rest - fraction) < 0.000_1 && value >= 0 && value < 10 {
            return whole == 0 ? glyph : "\(Int(whole))\(glyph)"
        }
        let text = NumberText.plain(value, decimals: 2)
        return decimalSeparator == "." ? text : text.replacingOccurrences(of: ".", with: decimalSeparator)
    }
}

/// Portion labels that already carry their amount: 646 catalog portions read "glass (250 ml)",
/// "Glas (0,25 l)" or "Stamperl (2 cl)". The total is shown next to every portion anyway, so the
/// bracket goes at display time (stored entries keep their labels).
public enum PortionLabel {
    /// "glass (250 ml)" → "glass", "Glas (0,25 l)" → "Glas"; "can (175 g drained)" and
    /// "from 1 egg (M)" stay as they are. A food counted in servings has no total next to the
    /// label, so its bracket stays too.
    public static func display(_ label: String, baseUnit: BaseUnit) -> String {
        guard baseUnit != .serving, label.hasSuffix(")"), let open = label.lastIndex(of: "(") else { return label }
        let inside = label[label.index(after: open)..<label.index(before: label.endIndex)]
            .trimmingCharacters(in: .whitespaces)
        guard isAmount(inside) else { return label }
        let head = label[..<open].trimmingCharacters(in: .whitespaces)
        return head.isEmpty ? label : head
    }

    /// "250 ml", "0,25 l", "2 cl", "30g", "1.5 kg"
    static func isAmount(_ text: String) -> Bool {
        let units: Set<String> = ["g", "ml", "cl", "l", "kg"]
        var number = ""
        var rest = Substring(text)
        while let character = rest.first, character.isNumber || character == "." || character == "," {
            number.append(character)
            rest = rest.dropFirst()
        }
        guard number.contains(where: \.isNumber) else { return false }
        return units.contains(rest.trimmingCharacters(in: .whitespaces).lowercased())
    }
}
