import Foundation

/// Numbers in the few display sentences Core builds: the check-in's reasons, the coach
/// notifications, the review card, the body lines, the plan editor's week warning, protein per
/// kg and the goal steps. On Apple platforms they follow the person's locale like the rest of the
/// app ("2.150 kcal", "84,5 cm" in Austria); elsewhere (the Linux tests) they keep "," grouping
/// and "." decimals. Exports and the AI texts never use this (`NumberText`, `SettingsCSV`).
public enum DisplayNumber {
    /// A whole number with grouping: "2,150" (the sign as given: "-150").
    public static func grouped(_ value: Double) -> String {
        // Display numbers are kcal, grams and the like; a broken huge value must not trap in Int().
        guard value.isFinite, abs(value) < 1e15 else { return "0" }
        #if canImport(Darwin)
        return Int(value.rounded()).formatted(.number)
        #else
        return SettingsCSV.grouped(value)
        #endif
    }

    /// Exactly `decimals` decimals: "74.6", "0.15", "2.0".
    public static func fixed(_ value: Double, decimals: Int) -> String {
        guard value.isFinite else { return "0" }
        let places = max(0, decimals)
        #if canImport(Darwin)
        return value.formatted(.number.precision(.fractionLength(places)))
        #else
        let text = String(format: "%.\(places)f", value)
        return text.hasPrefix("-") && Double(text) == 0 ? String(text.dropFirst()) : text
        #endif
    }

    /// Up to `decimals` decimals, trailing zeros left out: "2", "2.5", "84.5".
    public static func plain(_ value: Double, decimals: Int) -> String {
        guard value.isFinite else { return "0" }
        #if canImport(Darwin)
        return value.formatted(.number.precision(.fractionLength(0...max(0, decimals))))
        #else
        return NumberText.plain(value, decimals: max(0, decimals))
        #endif
    }

    /// A change with its sign: "+1.2", "−0.3" (a real minus), and one zero style everywhere:
    /// "0.0" without a sign (anything that rounds to zero at `decimals`).
    public static func signed(_ value: Double, decimals: Int) -> String {
        let places = max(0, decimals)
        let zero = String(format: "%.\(places)f", 0.0)
        guard value.isFinite, String(format: "%.\(places)f", abs(value)) != zero else { return fixed(0, decimals: places) }
        return (value < 0 ? "−" : "+") + fixed(abs(value), decimals: places)
    }

    /// A share of body weight next to a change in kg, left out when it rounds below 0.05 %:
    /// "+0.5 %", nil for 0.04 %.
    public static func signedPercent(_ percent: Double?, decimals: Int = 1) -> String? {
        guard let percent, percent.isFinite, abs(percent) >= 0.05 - 1e-9 else { return nil }
        return signed(percent, decimals: decimals) + " %"
    }

    /// A weight change and its share of body weight: "+0.4 kg (+0.5 %)", "+0.01 kg" (the % left
    /// out under 0.05 %).
    public static func weightChange(kilograms: Double, percent: Double?, decimals: Int = 1) -> String {
        let kg = signed(kilograms, decimals: decimals) + " kg"
        guard let share = signedPercent(percent) else { return kg }
        return "\(kg) (\(share))"
    }
}
