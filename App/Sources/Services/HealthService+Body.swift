import Foundation
import Observation
import BinisoftKit
import NinaCore
#if os(iOS)
import HealthKit
#endif

/// Apple Health body data, iPhone and iPad only (spec F22): body fat with lean mass, waist and
/// height, and today's finished workouts. Read live once the person switches them on in
/// Settings → Apple Health → Body (permission is asked right then, never at launch), kept in memory
/// only and never written to SwiftData or CloudKit – not into a measurement, a day mark, the plan,
/// a check-in or the profile (App Store guideline 5.1.3(ii)). The switches and the method each
/// source app is relabelled to are device-only (UserDefaults). `app.health.bodyData`.
@MainActor
@Observable
final class HealthBodyReader {
    enum Option: String, CaseIterable, Identifiable {
        case bodyFat, waist, workouts

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bodyFat: "Body fat and lean mass"
            case .waist: "Waist"
            case .workouts: "Workouts suggest the day type"
            }
        }

        var key: String { "nina.health.body." + rawValue }
    }

    /// Source app id → the method its body fat counts as (missing = smart scale). Device-only.
    static let labelsKey = "nina.health.body.labels"
    /// Today's workouts are read again when older than this (Today asks when it appears).
    static let workoutsMaxAge: TimeInterval = 5 * 60

    let enabled: Bool
    /// `-Demo` (screenshots): made-up values, nothing is read from Health.
    let isDemo: Bool
    private(set) var options: Set<Option> = []
    /// Read live, newest first (not the values Nina wrote). Never stored.
    private(set) var bodyFatSamples: [HealthBodySample] = []
    private(set) var leanSamples: [HealthBodySample] = []
    private(set) var waistSamples: [HealthBodySample] = []
    private(set) var heightSamples: [HealthBodySample] = []
    /// Workouts of the last 36 hours (today's are the ones that count). Never stored.
    private(set) var workouts: [HealthWorkout] = []
    private(set) var labels: [String: BodyMethod] = [:]
    /// Grows whenever the values or the labels change: the body page reloads on it.
    private(set) var version = 0
    @ObservationIgnored private var workoutsReadAt: Date?

    init(enabled: Bool, isDemo: Bool = LaunchOptions.current.isDemo) {
        self.enabled = enabled
        self.isDemo = isDemo
        if isDemo {
            // Only where Health exists (not in the Mac's demo).
            #if os(iOS)
            options = Set(Option.allCases)
            fillDemo()
            #endif
            return
        }
        for option in Option.allCases where UserDefaults.standard.bool(forKey: option.key) {
            options.insert(option)
        }
        let stored = UserDefaults.standard.dictionary(forKey: Self.labelsKey) as? [String: String] ?? [:]
        labels = stored.compactMapValues { BodyMethod(rawValue: $0) }
    }

    var isAvailable: Bool {
        #if os(iOS)
        enabled && HKHealthStore.isHealthDataAvailable()
        #else
        false
        #endif
    }

    /// The switch is on and Health can be read here.
    func isOn(_ option: Option) -> Bool { (isAvailable || isDemo) && options.contains(option) }

    /// Turns a Body switch on or off. Switching on asks for permission (iOS asks only once per kind
    /// of data) and reads at once; switching off forgets the values.
    func set(_ option: Option, _ on: Bool) async {
        if on { options.insert(option) } else { options.remove(option) }
        if !isDemo { UserDefaults.standard.set(on, forKey: option.key) }
        #if os(iOS)
        if on { await requestAuthorization(for: option) }
        #endif
        workoutsReadAt = nil
        await refresh()
        version += 1
    }

    // MARK: Labels

    /// The method a source's body fat counts as.
    func method(for source: String) -> BodyMethod { labels[source] ?? HealthBody.defaultMethod }

    /// Relabels a source app ("this app writes my DEXA results"), on this device only.
    func relabel(_ source: String, as method: BodyMethod) {
        labels[source] = method == HealthBody.defaultMethod ? nil : method
        if !isDemo { UserDefaults.standard.set(labels.mapValues(\.rawValue), forKey: Self.labelsKey) }
        version += 1
    }

    /// The apps that wrote body fat, newest first.
    var sources: [HealthBodySource] { isOn(.bodyFat) ? HealthBody.sources(bodyFatSamples) : [] }

    // MARK: What the screens use

    /// The body page's Health series (memory only).
    func snapshot(dayStartHour: Int, calendar: Calendar = .current) -> HealthBodySnapshot {
        let bodyFat: [HealthBodyFatSeries] = isOn(.bodyFat)
            ? HealthBody.bodyFatSeries(bodyFat: bodyFatSamples, leanMass: leanSamples, labels: labels,
                                       dayStartHour: dayStartHour, calendar: calendar)
            : []
        return HealthBodySnapshot(bodyFat: bodyFat, waist: waist(dayStartHour: dayStartHour, calendar: calendar), heightCm: heightCm)
    }

    /// Health's waist series, one reading per day, oldest first (empty while the switch is off).
    func waist(dayStartHour: Int, calendar: Calendar = .current) -> [GirthReading] {
        isOn(.waist) ? HealthBody.waist(waistSamples, dayStartHour: dayStartHour, calendar: calendar) : []
    }

    /// The newest height in Health: only a hint next to the height field.
    var heightCm: Double? {
        guard isOn(.bodyFat) || isOn(.waist) else { return nil }
        return HealthBody.latestHeight(heightSamples)
    }

    /// "Tennis workout found · Make it a tennis day?" for `day`, or nil (`HealthWorkouts.suggestion`).
    /// `dismissed`: the keys of this device's "Not now" taps.
    func workoutSuggestion(settings: NinaSettings, day: DayKey, dismissed: Set<String>, now: Date = Date()) -> WorkoutSuggestion? {
        guard isOn(.workouts), !workouts.isEmpty else { return nil }
        return HealthWorkouts.suggestion(plan: settings.plan, day: day, today: settings.today(now: now), now: now,
                                         marks: settings.dayTypeMarks, workouts: workouts,
                                         fallback: settings.legacyTargets(for: day), dayStartHour: settings.dayStartHour,
                                         dismissed: dismissed)
    }

    /// Reads today's workouts again when the last read is older than `workoutsMaxAge`.
    func refreshWorkoutsIfStale() async {
        guard isOn(.workouts), !isDemo else { return }
        if let read = workoutsReadAt, Date().timeIntervalSince(read) < Self.workoutsMaxAge { return }
        await refreshWorkouts()
    }

    #if os(iOS)
    @ObservationIgnored private let store = HKHealthStore()

    private func readTypes(for option: Option) -> Set<HKObjectType> {
        var types = Set<HKObjectType>()
        switch option {
        case .bodyFat:
            types.insert(HKQuantityType(.bodyFatPercentage))
            types.insert(HKQuantityType(.leanBodyMass))
            types.insert(HKQuantityType(.height))
        case .waist:
            types.insert(HKQuantityType(.waistCircumference))
            types.insert(HKQuantityType(.height))
        case .workouts:
            types.insert(HKObjectType.workoutType())
        }
        return types
    }

    private func requestAuthorization(for option: Option) async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes(for: option))
            AppLog.info("Health permission asked (body: \(option.rawValue))", category: "health")
        } catch {
            AppLog.warning("Health permission failed: \(error.localizedDescription)", category: "health")
        }
    }

    /// Reads what is switched on (what the person didn't allow simply comes back empty) and
    /// forgets what is off. Called with the other Health readings (`HealthService.refreshReadings`).
    func refresh() async {
        guard !isDemo, isAvailable else { return }
        var changed = false
        var fat: [HealthBodySample] = []
        var lean: [HealthBodySample] = []
        if options.contains(.bodyFat) {
            fat = await samples(.bodyFatPercentage, unit: .percent(), scale: 100)
            lean = await samples(.leanBodyMass, unit: .gramUnit(with: .kilo))
        }
        if fat != bodyFatSamples { bodyFatSamples = fat; changed = true }
        if lean != leanSamples { leanSamples = lean; changed = true }
        var waist: [HealthBodySample] = []
        if options.contains(.waist) {
            waist = await samples(.waistCircumference, unit: .meterUnit(with: .centi))
        }
        if waist != waistSamples { waistSamples = waist; changed = true }
        var height: [HealthBodySample] = []
        if options.contains(.bodyFat) || options.contains(.waist) {
            height = await samples(.height, unit: .meterUnit(with: .centi), days: 3650, limit: 20)
        }
        if height != heightSamples { heightSamples = height; changed = true }
        await refreshWorkouts()
        if changed { version += 1 }
    }

    /// Workouts of the last 36 hours (enough for today with any day start).
    func refreshWorkouts() async {
        guard !isDemo else { return }
        guard isAvailable, options.contains(.workouts) else {
            if !workouts.isEmpty { workouts = [] }
            return
        }
        workoutsReadAt = Date()
        let start = Date().addingTimeInterval(-36 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate, order: .forward)], limit: 50)
        guard let found = try? await descriptor.result(for: store) else { return }
        let list: [HealthWorkout] = found.map { workout in
            HealthWorkout(activity: Self.activityName(workout.workoutActivityType), start: workout.startDate, end: workout.endDate)
        }
        if list != workouts { workouts = list }
    }

    /// Quantity samples of one type from the last `days` days, newest first, without the ones
    /// this app wrote, in `unit` × `scale` (body fat: fraction × 100 = percent).
    private func samples(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, scale: Double = 1, days: Int = 400,
                         limit: Int = 2000) async -> [HealthBodySample] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: predicate)],
                                                 sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: limit)
        guard let found = try? await descriptor.result(for: store) else { return [] }
        let own = HKSource.default()
        return found.compactMap { sample -> HealthBodySample? in
            let source = sample.sourceRevision.source
            guard source != own else { return nil }
            return HealthBodySample(date: sample.endDate, value: sample.quantity.doubleValue(for: unit) * scale,
                                    sourceID: source.bundleIdentifier, sourceName: source.name)
        }
    }

    /// The `HKWorkoutActivityType` case name NinaCore maps (`HealthWorkouts.kinds(of:)`); "other"
    /// for the rest.
    static func activityName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .tennis: "tennis"
        case .traditionalStrengthTraining: "traditionalStrengthTraining"
        case .functionalStrengthTraining: "functionalStrengthTraining"
        case .coreTraining: "coreTraining"
        case .highIntensityIntervalTraining: "highIntensityIntervalTraining"
        case .crossTraining: "crossTraining"
        case .mixedCardio: "mixedCardio"
        case .running: "running"
        case .cycling: "cycling"
        case .swimming: "swimming"
        case .walking: "walking"
        case .hiking: "hiking"
        case .yoga: "yoga"
        case .pilates: "pilates"
        case .rowing: "rowing"
        case .elliptical: "elliptical"
        case .stairClimbing: "stairClimbing"
        case .soccer: "soccer"
        case .basketball: "basketball"
        case .volleyball: "volleyball"
        case .badminton: "badminton"
        case .squash: "squash"
        case .tableTennis: "tableTennis"
        case .pickleball: "pickleball"
        case .racquetball: "racquetball"
        case .golf: "golf"
        case .boxing: "boxing"
        case .kickboxing: "kickboxing"
        case .martialArts: "martialArts"
        case .climbing: "climbing"
        case .downhillSkiing: "downhillSkiing"
        case .crossCountrySkiing: "crossCountrySkiing"
        case .snowboarding: "snowboarding"
        case .cardioDance: "cardioDance"
        case .socialDance: "socialDance"
        case .jumpRope: "jumpRope"
        case .flexibility: "flexibility"
        default: "other"
        }
    }
    #else
    func refresh() async {}
    func refreshWorkouts() async {}
    #endif

    // MARK: Demo

    /// Made-up values for `-Demo` screenshots: a smart scale every week, a waist app and a tennis
    /// workout that ended an hour ago. They fit the demo profile (171 cm, about 67 kg at 21 % body
    /// fat, so about 53 kg lean) and its tape (waist in the low seventies).
    private func fillDemo() {
        let now = Date()
        let day: TimeInterval = 24 * 3600
        let fat: [Double] = [21.4, 21.1, 21.2, 20.8, 20.9, 20.5, 20.6, 20.2]
        let lean: [Double] = [52.6, 52.7, 52.7, 52.9, 53.0, 53.1, 53.2, 53.4]
        let waist: [Double] = [73.8, 73.6, 73.7, 73.2, 73.3, 72.9, 73.0, 72.6]
        for index in fat.indices {
            let date = now.addingTimeInterval(-Double(fat.count - 1 - index) * 7 * day - 3600)
            bodyFatSamples.append(HealthBodySample(date: date, value: fat[index], sourceID: "com.example.scale", sourceName: "Body Scale"))
            leanSamples.append(HealthBodySample(date: date, value: lean[index], sourceID: "com.example.scale", sourceName: "Body Scale"))
            waistSamples.append(HealthBodySample(date: date, value: waist[index], sourceID: "com.example.tape", sourceName: "Tape Measure"))
        }
        heightSamples = [HealthBodySample(date: now.addingTimeInterval(-90 * day), value: 171, sourceID: "com.apple.Health",
                                          sourceName: "Health")]
        workouts = [HealthWorkout(activity: "tennis", start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600))]
    }
}
