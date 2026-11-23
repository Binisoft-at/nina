import Foundation

/// Locale-independent number text for storage and for the few places where Core builds display
/// strings (the app formats with the user's locale everywhere else).
public enum NumberText {
    /// Shortest exact text with at most 4 decimals: 52 → "52", 0.26 → "0.26", 13.8100001 → "13.81".
    public static func plain(_ value: Double, decimals: Int = 4) -> String {
        guard value.isFinite else { return "0" }
        let factor = pow(10, Double(decimals))
        var rounded = (value * factor).rounded() / factor
        if rounded == 0 { rounded = 0 } // no "-0"
        var text = "\(rounded)"
        if text.hasSuffix(".0") { text.removeLast(2) }
        return text
    }

    /// The energy field of a food label in the chosen unit, whole numbers: 250 kcal → "250" or
    /// "1046" (kJ). Read back with `unit.kilocalories(from:)`, so saving an untouched field keeps
    /// the calories (within half a kJ).
    public static func energyField(kilocalories: Double, unit: EnergyUnit) -> String {
        plain(unit.value(fromKilocalories: kilocalories), decimals: 0)
    }

    /// Value rounded the way a nutrition label shows it: integers for big values, one decimal
    /// below 10, two below 1 (0.04 g stays visible as 0.04, 152.6 kcal becomes 153).
    public static func label(_ value: Double) -> Double {
        let magnitude = abs(value)
        if magnitude >= 100 { return value.rounded() }
        if magnitude >= 10 { return (value * 10).rounded() / 10 }
        if magnitude >= 1 { return (value * 10).rounded() / 10 }
        return (value * 100).rounded() / 100
    }

    /// Parses "1,5", "1.5", "½", "1 1/2", "3/4" (numbers people type or dictate).
    public static func parse(_ raw: String) -> Double? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let vulgar: [Character: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "⅛": 0.125]
        if let last = text.last, let fraction = vulgar[last] {
            let whole = String(text.dropLast()).trimmingCharacters(in: .whitespaces)
            if whole.isEmpty { return fraction }
            guard let base = Double(whole) else { return nil }
            return base + fraction
        }
        let parts = text.split(separator: " ")
        if parts.count == 2, let whole = Double(parts[0]), let fraction = parseFraction(String(parts[1])) {
            return whole + fraction
        }
        if let fraction = parseFraction(text) { return fraction }
        text = text.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }

    private static func parseFraction(_ text: String) -> Double? {
        let parts = text.split(separator: "/")
        guard parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]), denominator != 0 else { return nil }
        return numerator / denominator
    }
}
