import Foundation
import NinaCore

/// Display formatting with the person's locale (decimal comma in Austria, grouping separators).
enum Fmt {
    static func number(_ value: Double, decimals: Int = 0) -> String {
        guard value.isFinite else { return "–" }
        return value.formatted(.number.precision(.fractionLength(0...max(0, decimals))))
    }

    /// "1,240 kcal" / "5,188 kJ"
    static func energy(_ kilocalories: Double, unit: EnergyUnit, showUnit: Bool = true) -> String {
        let value = unit.value(fromKilocalories: kilocalories)
        let text = number(value.rounded(), decimals: 0)
        return showUnit ? "\(text) \(unit.symbol)" : text
    }

    /// A nutrient amount the way labels show it: "82 g", "0.4 g", "1.2 g salt", "–" when unknown.
    static func nutrient(_ value: Double?, _ nutrient: Nutrient, unit: EnergyUnit = .kcal, showUnit: Bool = true) -> String {
        guard let value else { return "–" }
        if nutrient == .energy { return energy(value, unit: unit, showUnit: showUnit) }
        let rounded = NumberText.label(value)
        let decimals = abs(rounded) >= 10 ? 0 : (abs(rounded) >= 1 ? 1 : 2)
        let text = number(rounded, decimals: decimals)
        return showUnit ? "\(text) \(nutrient.measure.symbol)" : text
    }

    /// Salt in grams from sodium in mg.
    static func salt(fromSodium sodium: Double?) -> String {
        guard let sodium else { return "–" }
        let salt = sodium * 2.5 / 1000
        return number(NumberText.label(salt), decimals: salt >= 10 ? 0 : (salt >= 1 ? 1 : 2)) + " g"
    }

    static func grams(_ value: Double) -> String {
        number(value.rounded(), decimals: 0) + " g"
    }

    /// "1,250 ml"
    static func milliliters(_ value: Double) -> String {
        number(value.rounded(), decimals: 0) + " ml"
    }

    /// "1.25 l" for big amounts, ml below.
    static func volume(_ milliliters: Double) -> String {
        if milliliters >= 1000 {
            return number(milliliters / 1000, decimals: 2) + " l"
        }
        return self.milliliters(milliliters)
    }

    static func kilograms(_ value: Double, decimals: Int = 1) -> String {
        number(value, decimals: decimals) + " kg"
    }

    static func percent(_ fraction: Double) -> String {
        number((fraction * 100).rounded(), decimals: 0) + " %"
    }

    /// Amount for an entry: "150 g", "2 × slice (60 g)".
    static func amount(_ amount: AmountText) -> String {
        let total = amount.total
        let base = amount.baseUnit
        if amount.isBaseUnit {
            if base == .serving {
                return "\(AmountText.quantity(amount.quantity)) \(amount.quantity == 1 ? "serving" : "servings")"
            }
            return number(amount.quantity, decimals: amount.quantity < 10 ? 1 : 0) + " " + base.symbol
        }
        let weight = base == .serving ? "" : " (" + number(total.rounded(), decimals: 0) + " " + base.symbol + ")"
        if amount.quantity == 1 { return "1 \(amount.unitLabel)\(weight)" }
        return "\(AmountText.quantity(amount.quantity)) × \(amount.unitLabel)\(weight)"
    }

    /// Today / Yesterday / Tomorrow / "Mon, 10 Nov"
    static func dayTitle(_ day: DayKey, today: DayKey, calendar: Calendar = .current) -> String {
        let offset = today.days(to: day, calendar: calendar)
        switch offset {
        case 0: return "Today"
        case -1: return "Yesterday"
        case 1: return "Tomorrow"
        default:
            let date = day.date(calendar: calendar)
            if day.year == today.year {
                return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            }
            return date.formatted(.dateTime.day().month(.abbreviated).year())
        }
    }

    static func shortDay(_ day: DayKey, calendar: Calendar = .current) -> String {
        day.date(calendar: calendar).formatted(.dateTime.day().month(.abbreviated))
    }

    static func weekdayLetter(_ day: DayKey, calendar: Calendar = .current) -> String {
        day.date(calendar: calendar).formatted(.dateTime.weekday(.narrow))
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func clock(_ minutes: Int, calendar: Calendar = .current) -> String {
        let date = DayKey(year: 2026, month: 1, day: 5).date(minutes: minutes, calendar: calendar)
        return date.formatted(date: .omitted, time: .shortened)
    }
}
