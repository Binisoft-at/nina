import Foundation

// Workouts from Apple Health that suggest a day type (spec F22). The app reads today's finished
// workouts live and never stores them; a day type lists the workout kinds that suggest it
// (`CoachPlan.DayType.workouts`, e.g. "strength", "tennis"). When today follows the default type
// and a workout fits another one, Today offers "Tennis workout found · Make it a tennis day?" –
// only that tap writes the day-type mark. Nina never changes the day type by itself.

/// A finished workout read live from Apple Health.
public struct HealthWorkout: Equatable, Sendable {
    /// The activity as the name of its `HKWorkoutActivityType` case: "tennis",
    /// "traditionalStrengthTraining", "functionalStrengthTraining", "running" …
    public var activity: String
    public var start: Date
    public var end: Date

    public init(activity: String, start: Date, end: Date) {
        self.activity = activity
        self.start = start
        self.end = end
    }

    /// The day it counts for: the day it started on (with the profile's day start).
    public func day(dayStartHour: Int = 0, calendar: Calendar = .current) -> DayKey {
        DayKey(date: start, calendar: calendar, dayStartHour: dayStartHour)
    }
}

/// "Tennis workout found · Make it a tennis day?" on Today's day-type chip.
public struct WorkoutSuggestion: Equatable, Sendable, Identifiable {
    public var day: DayKey
    public var typeID: String
    public var typeName: String
    public var emoji: String
    /// The workout that fits ("tennis").
    public var activity: String
    /// The day's calories as that type.
    public var energy: Double

    public init(day: DayKey, typeID: String, typeName: String, emoji: String, activity: String, energy: Double) {
        self.day = day
        self.typeID = typeID
        self.typeName = typeName
        self.emoji = emoji
        self.activity = activity
        self.energy = energy
    }

    /// The device-only "Not now" key: "workout.2030-01-07.tennis".
    public var key: String { HealthWorkouts.dismissKey(day: day, typeID: typeID) }
    public var id: String { key }

    /// "Tennis workout found".
    public var found: String { "\(HealthWorkouts.title(of: activity)) workout found" }

    /// "Make it a tennis day?" ("Make it a gym day?").
    public var question: String { "Make it a \(HealthWorkouts.dayName(typeName))?" }

    /// "Tennis workout found · Make it a tennis day?"
    public var text: String { "\(found) · \(question)" }
}

public enum HealthWorkouts {
    /// The workout kinds a Health activity counts as, in the words a day type's `workouts` list
    /// uses (normalised like the settings import: lower case, accents folded, "_" between words):
    /// the activity's own name first ("traditional_strength_training"), then the common words
    /// ("strength", "gym" …). Unknown activities count by their own name only.
    public static func kinds(of activity: String) -> [String] {
        var result: [String] = []
        for kind in [snakeCase(activity)] + (table[activity]?.kinds ?? []) {
            let normalized = normalize(kind)
            if !normalized.isEmpty, !result.contains(normalized) { result.append(normalized) }
        }
        return result
    }

    /// "Tennis", "Strength", "HIIT", "Table tennis" (unknown activities: their name in words).
    public static func title(of activity: String) -> String {
        if let title = table[activity]?.title { return title }
        let words = snakeCase(activity).replacingOccurrences(of: "_", with: " ")
        guard let first = words.first else { return "Workout" }
        return first.uppercased() + words.dropFirst()
    }

    /// A day type's workout entry as the settings import stores it: "Strength Training" →
    /// "strength_training", "Fußball" → "fussball".
    public static func normalize(_ text: String) -> String {
        SearchText.normalize(text).replacingOccurrences(of: " ", with: "_")
    }

    /// "tennis; Strength" → ["tennis", "strength"] (comma, semicolon or | between entries).
    public static func parse(_ text: String) -> [String] {
        var result: [String] = []
        for part in text.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "|" }) {
            let kind = normalize(String(part))
            if !kind.isEmpty, !result.contains(kind) { result.append(kind) }
        }
        return result
    }

    /// The activity is one of the kinds in a day type's `workouts` list.
    public static func matches(_ activity: String, workouts: [String]) -> Bool {
        let listed = Set(workouts.map(normalize).filter { !$0.isEmpty })
        guard !listed.isEmpty else { return false }
        return kinds(of: activity).contains { listed.contains($0) }
    }

    /// The day types (in plan order) whose `workouts` list the activity.
    public static func types(matching activity: String, in plan: CoachPlan) -> [CoachPlan.DayType] {
        plan.dayTypes.filter { matches(activity, workouts: $0.workouts) }
    }

    /// The day types that list workouts, as "Tennis: tennis" lines for Settings.
    public static func mappedTypes(in plan: CoachPlan) -> [CoachPlan.DayType] {
        plan.dayTypes.filter { !$0.workouts.isEmpty }
    }

    /// "workout.2030-01-07.tennis".
    public static func dismissKey(day: DayKey, typeID: String) -> String { "workout.\(day.rawValue).\(typeID)" }

    /// What Today offers on `day`, or nil. Only on today, with a set-up plan that isn't paused,
    /// when the day follows its default type (from the schedule or picked by hand), and a
    /// workout that started that day and has finished by `now` is listed by another day type.
    /// When workouts fit several types, the one with the most calories that day wins (day-type
    /// combos are out of scope: "pick the higher one"); ties go to the plan's order. A
    /// suggestion whose key is in `dismissed` ("Not now" on this device) is not offered again.
    /// `fallback`: the targets without a plan revision (`NinaSettings.legacyTargets(for:)`).
    public static func suggestion(plan: CoachPlan, day: DayKey, today: DayKey, now: Date = Date(),
                                  marks: [String: String], workouts: [HealthWorkout], fallback: DailyTargets,
                                  dayStartHour: Int = 0, dismissed: Set<String> = [],
                                  calendar: Calendar = .current) -> WorkoutSuggestion? {
        guard day == today, plan.isSetUp, !plan.isPaused(on: day),
              let current = plan.dayType(on: day, marks: marks, calendar: calendar), current.schedule == .default else { return nil }
        let finished = workouts.filter { $0.end <= now && $0.day(dayStartHour: dayStartHour, calendar: calendar) == day }
            .sorted { $0.start < $1.start }
        var best: WorkoutSuggestion?
        for type in plan.dayTypes where type.id != current.id {
            guard let workout = finished.first(where: { matches($0.activity, workouts: type.workouts) }) else { continue }
            var picked = marks
            picked[day.rawValue] = type.id
            let energy = plan.targets(on: day, marks: picked, fallback: fallback, calendar: calendar).energy
            let candidate = WorkoutSuggestion(day: day, typeID: type.id, typeName: type.name,
                                              emoji: type.emoji.isEmpty ? CoachPlan.DayType.suggestedEmoji(for: type.name) : type.emoji,
                                              activity: workout.activity, energy: energy)
            guard !dismissed.contains(candidate.key) else { continue }
            if best == nil || energy > (best?.energy ?? 0) { best = candidate }
        }
        return best
    }

    /// "tennis day", "gym day"; a name that already ends in "day" stays ("rest day").
    static func dayName(_ typeName: String) -> String {
        let name = typeName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.isEmpty { return "workout day" }
        return name.hasSuffix(" day") || name == "day" ? name : name + " day"
    }

    /// "traditionalStrengthTraining" → "traditional_strength_training".
    static func snakeCase(_ name: String) -> String {
        var result = ""
        for character in name {
            if character.isUppercase {
                if !result.isEmpty, result.last != "_" { result.append("_") }
                result += character.lowercased()
            } else if character == " " || character == "-" {
                if !result.isEmpty, result.last != "_" { result.append("_") }
            } else {
                result.append(character)
            }
        }
        return result
    }

    /// Activities by their `HKWorkoutActivityType` case name: the title Today shows and the
    /// words a day type may list for them (English, plus a few German ones).
    static let table: [String: (title: String, kinds: [String])] = [
        "tennis": ("Tennis", ["tennis"]),
        "traditionalStrengthTraining": ("Strength", ["strength", "strength_training", "gym", "weights", "lifting", "kraft", "krafttraining"]),
        "functionalStrengthTraining": ("Strength", ["strength", "strength_training", "functional", "gym", "kraft", "krafttraining"]),
        "coreTraining": ("Core", ["core"]),
        "highIntensityIntervalTraining": ("HIIT", ["hiit", "intervals"]),
        "crossTraining": ("Cross training", ["crossfit"]),
        "mixedCardio": ("Cardio", ["cardio"]),
        "running": ("Running", ["run", "jogging", "laufen"]),
        "cycling": ("Cycling", ["bike", "biking", "cycle", "radfahren", "rad"]),
        "swimming": ("Swimming", ["swim", "schwimmen"]),
        "walking": ("Walking", ["walk", "gehen"]),
        "hiking": ("Hiking", ["hike", "wandern"]),
        "yoga": ("Yoga", []),
        "pilates": ("Pilates", []),
        "rowing": ("Rowing", ["row", "rudern"]),
        "elliptical": ("Elliptical", ["crosstrainer"]),
        "stairClimbing": ("Stairs", ["stairs"]),
        "soccer": ("Football", ["football", "fussball"]),
        "basketball": ("Basketball", []),
        "volleyball": ("Volleyball", []),
        "badminton": ("Badminton", []),
        "squash": ("Squash", []),
        "tableTennis": ("Table tennis", ["ping_pong", "tischtennis"]),
        "pickleball": ("Pickleball", []),
        "racquetball": ("Racquetball", []),
        "golf": ("Golf", []),
        "boxing": ("Boxing", []),
        "kickboxing": ("Kickboxing", []),
        "martialArts": ("Martial arts", []),
        "climbing": ("Climbing", ["bouldering", "klettern"]),
        "downhillSkiing": ("Skiing", ["skiing", "ski"]),
        "crossCountrySkiing": ("Cross-country skiing", ["skiing", "ski", "langlauf"]),
        "snowboarding": ("Snowboarding", []),
        "cardioDance": ("Dance", ["dance", "dancing", "tanzen"]),
        "socialDance": ("Dance", ["dance", "dancing", "tanzen"]),
        "jumpRope": ("Jump rope", []),
        "flexibility": ("Stretching", ["stretching"]),
    ]
}
