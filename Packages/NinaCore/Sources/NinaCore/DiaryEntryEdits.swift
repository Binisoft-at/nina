import Foundation

/// Diary edits that need care with days and clock times: moving entries to another day, the day
/// an edited entry keeps, the quick entry's number fields and the diary search.
public enum DiaryEntryEdits {

    // MARK: Moving to another day

    /// The time an entry gets when it moves from `source` to `target`: the same clock time on the
    /// target day. A time before the day start (with the day starting at 3:00, a snack at 00:30)
    /// stays at the end of the target day, on the calendar date after it. Within its own day the
    /// time stays as it is.
    public static func movedTime(_ time: Date, from source: DayKey, to target: DayKey, dayStartHour: Int = 0,
                                 calendar: Calendar = .current) -> Date {
        guard source != target else { return time }
        let parts = calendar.dateComponents([.hour, .minute, .second], from: time)
        var minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if minutes < max(0, min(dayStartHour, 12)) * 60 { minutes += 1440 }
        let moved = target.date(minutes: minutes, calendar: calendar)
        // Seconds keep the order of entries logged a moment apart.
        return moved.addingTimeInterval(Double(parts.second ?? 0))
    }

    // MARK: Editing an entry

    /// The day an edited entry counts for. While the date in the picker is still the one it
    /// started with, the entry keeps its stored day: travelling or a late day start never moves
    /// what was eaten when only the amount, note or clock time changes. A new date counts for the
    /// day that date and time belong to.
    public static func editedDay(stored: DayKey, originalTime: Date, newTime: Date, dayStartHour: Int = 0,
                                 calendar: Calendar = .current) -> DayKey {
        if calendar.isDate(newTime, inSameDayAs: originalTime) { return stored }
        return DayKey(date: newTime, calendar: calendar, dayStartHour: dayStartHour)
    }

    /// One number field of a quick entry as typed. Energy is needed and can't be negative;
    /// protein, carbs and fat may stay empty (0), and a negative one counts as 0. Nil while the
    /// text doesn't read as a number, so Save waits for a fix instead of storing 0.
    public static func quickValue(_ text: String, isEnergy: Bool) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return isEnergy ? nil : 0 }
        guard let value = NumberText.parse(trimmed), value.isFinite else { return nil }
        if isEnergy { return value >= 0 ? value : nil }
        return max(0, value)
    }

    // MARK: Searching the diary

    /// What a diary search looks for: "#" dropped and folded like every search ("Café-Latte" →
    /// "cafe latte", "Straße" → "strasse"); nil below two characters.
    public static func searchNeedle(_ query: String) -> String? {
        let needle = SearchText.normalize(query.replacingOccurrences(of: "#", with: ""))
        return needle.count >= 2 ? needle : nil
    }

    /// Whether an entry's name, note, tags or brand contains the needle (`searchNeedle`).
    public static func matches(_ needle: String, name: String, note: String, tags: String, brand: String) -> Bool {
        SearchText.normalize(name + " " + note + " " + tags + " " + brand).contains(needle)
    }
}
