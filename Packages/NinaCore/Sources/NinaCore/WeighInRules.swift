import Foundation

// Whether a weigh-in counts: the weigh-in sheet says so before it is saved ("After 11:00 – shown
// on the chart, not counted in your average"). Built on WeightSignal's public rules only: the
// first reading before the morning cutoff of a diary day is that day's morning weight, every
// other reading is kept for the chart.

extension WeightSignal {
    /// How a weigh-in at a time would be read.
    public enum WeighInStanding: Equatable, Sendable {
        /// It becomes the day's morning weight: it counts in the 7-day average, pace and check-in.
        case counts
        /// After the morning cutoff: on the chart, not in the average.
        case afterCutoff
        /// The day already has an earlier morning weight (`morning`); this one is extra.
        case extra(morning: Reading)
    }

    /// How a weigh-in at `time`, filed under the diary day `day`, would be read next to the
    /// readings this signal has. `excluding`: the weigh-in being edited (it doesn't compete with
    /// itself); `kilograms`: the weight typed, so a Health copy of the same weigh-in (same kg
    /// within 0.05, within 10 minutes) isn't taken for an earlier one.
    public func standing(time: Date, day: DayKey, kilograms: Double? = nil, excluding: Reading? = nil) -> WeighInStanding {
        let probe = Reading(day: day, time: time, kilograms: kilograms ?? 0)
        guard probe.isMorning(cutoffMinutes: cutoffMinutes, dayStartHour: dayStartHour, calendar: calendar) else {
            return .afterCutoff
        }
        var candidates = others.filter { $0.day == day }
        if let morning = morning(on: day) { candidates.append(morning) }
        let earlier = candidates.filter { reading in
            if let excluding, reading == excluding { return false }
            guard reading.isMorning(cutoffMinutes: cutoffMinutes, dayStartHour: dayStartHour, calendar: calendar) else { return false }
            if let kilograms, reading.source == .health,
               abs(reading.kilograms - kilograms) <= WeightSignal.duplicateKilograms + 1e-9,
               abs(reading.time.timeIntervalSince(time)) <= WeightSignal.duplicateSeconds {
                return false
            }
            // A typed weigh-in at the same minute as a Health one goes first (as the signal sorts them).
            return reading.time < time || (reading.time == time && reading.source == .nina)
        }
        guard let first = earlier.min(by: { $0.time < $1.time }) else { return .counts }
        return .extra(morning: first)
    }

    /// A weigh-in at `time` on `day` would be the day's morning weight (`standing` is `.counts`).
    public func countsAsMorning(time: Date, day: DayKey, excluding: Reading? = nil) -> Bool {
        standing(time: time, day: day, excluding: excluding) == .counts
    }
}
