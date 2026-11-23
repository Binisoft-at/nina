import Foundation

/// The coach on Apple Watch (F20): what the wrist shows and acts on, from the same `CoachBoard`
/// and `WeightSignal` the phone uses. The day-type chip ("🎾 Tennis · 2,600 kcal"), the checks
/// row (weigh-in, the weekly tape sites, daily checks; full sets and body-fat assessments stay on
/// the phone), the Digital Crown values (0.1 kg or 0.1 cm per detent), the order of the weekly
/// sites, and the status line ("avg 74.6 · +0.15/wk · In range") in the phone's words. Pure: the
/// watch hands in plain values and formats numbers with the person's locale.
public enum WatchCoach {
    // MARK: Crown values

    /// kg or cm per Digital Crown detent.
    public static let step = 0.1
    /// Detents per kg or cm.
    static let stepsPerUnit = 10.0
    /// The weigh-in's start without any weigh-in typed yet.
    public static let defaultWeight = 70.0

    /// `value` on the 0.1 grid (the Crown's floating-point drift removed: 74.30000000001 → 74.3),
    /// kept in `range`.
    public static func snapped(_ value: Double, in range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let rounded = (clamped * stepsPerUnit).rounded() / stepsPerUnit
        // Rounding to the grid can step just outside a range whose ends aren't on it.
        return min(max(rounded, range.lowerBound), range.upperBound)
    }

    /// `steps` detents up (positive) or down from `value`, on the grid and kept in `range`
    /// (VoiceOver's adjust action moves like the Crown).
    public static func stepped(_ value: Double, by steps: Int, in range: ClosedRange<Double>) -> Double {
        let start = (snapped(value, in: range) * stepsPerUnit).rounded()
        return snapped((start + Double(steps)) / stepsPerUnit, in: range)
    }

    /// Where the weigh-in Crown starts: the newest weigh-in typed in Nina, else the body weight
    /// (7-day average, trend), else 70 kg; on the grid and within the plausible 25–300 kg. (Never a
    /// weight read from Apple Health: saved with one tap it would copy Health data into iCloud.)
    public static func startWeight(latest: Double?, bodyWeight: Double?) -> Double {
        let value = [latest, bodyWeight].compactMap { $0 }.first { $0.isFinite && $0 > 0 } ?? defaultWeight
        return snapped(value, in: WeightSignal.plausibleRange)
    }

    /// The latest reading of a site on or before `day` (any conditions), as the measure sheet
    /// shows it ("Last 71.5 cm · 7 Jan").
    public static func previousGirth(_ site: BodySite, in records: [BodyTapeRecord], onOrBefore day: DayKey) -> GirthReading? {
        GirthTrend.readings(site, in: records.filter { $0.day <= day }, includeNonStandard: true).last
    }

    /// Where a site's Crown starts: its latest reading, else a typical value for the site; on the
    /// grid and within the site's plausible range.
    public static func startGirth(_ site: BodySite, previous: Double?) -> Double {
        let value = previous.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? typicalGirth(site)
        return snapped(value, in: site.plausibleRange)
    }

    /// A middle-of-the-road start for a site nobody has measured yet (cm).
    public static func typicalGirth(_ site: BodySite) -> Double {
        switch site.base {
        case .waist: 85
        case .waistNarrow: 75
        case .hip: 98
        case .chest: 96
        case .arm: 30
        case .armFlexed: 33
        case .thigh: 55
        case .neck: 36
        case .calf: 37
        default: 50
        }
    }

    /// What to say under a tape value before it is saved.
    public enum GirthNote: Equatable, Sendable {
        /// Nothing to ask (the change since last time is shown).
        case ok
        /// More than 1 cm from last time: measure once more to be sure.
        case recheck
        /// More than 3 cm within 7 days: same spot as last time?
        case jump
    }

    /// The note for `value` against the site's latest reading (`BodyReadings`: a jump beats a recheck).
    public static func girthNote(_ value: Double, previous: GirthReading?, on day: DayKey,
                                 calendar: Calendar = .current) -> GirthNote {
        guard let previous else { return .ok }
        let daysApart = previous.day.days(to: day, calendar: calendar)
        if BodyReadings.isSuspiciousJump(value, previous: previous.value, daysApart: daysApart) { return .jump }
        if BodyReadings.needsAnother([value], twoReadings: false, previous: previous.value) { return .recheck }
        return .ok
    }

    // MARK: Day-type chip

    /// "🛋️ Rest · 2,150 kcal": the day type and its target (the ring above already says what is
    /// left). `energy` formats the kcal with its unit.
    public static func chipText(_ chip: CoachBoard.Chip,
                                energy: (Double) -> String = { WatchCoach.fixed($0.rounded(), 0) + " kcal" }) -> String {
        let name = [chip.emoji, chip.name].filter { !$0.isEmpty }.joined(separator: " ")
        let target = chip.energy.isFinite ? max(0, chip.energy) : 0
        return "\(name) · \(energy(target))"
    }

    /// "🛋️ Rest · 2,150": the day type and its target, for callers that format the number without
    /// its unit. `remaining` isn't shown any more (the ring shows it).
    public static func chipText(_ chip: CoachBoard.Chip, remaining: Double,
                                energy: (Double) -> String = { WatchCoach.fixed($0.rounded(), 0) }) -> String {
        chipText(chip, energy: energy)
    }

    /// The flexible count and the day's kcal of a choice in the day-type list:
    /// "2,400 kcal · 1 of 2 this week". `energy` formats the kcal with its unit.
    public static func optionDetail(_ option: CoachBoard.ChipOption,
                                    energy: (Double) -> String = { WatchCoach.fixed($0.rounded(), 0) + " kcal" }) -> String {
        ([energy(option.energy)] + [option.quotaText].compactMap { $0 }).joined(separator: " · ")
    }

    // MARK: Checks row

    /// What a pill on the watch does.
    public enum Act: Equatable, Sendable {
        /// The weigh-in with the Crown.
        case weighIn
        /// The weekly tape sites, one at a time with the Crown.
        case measure([BodySite])
        /// A daily check: open or skipped → done, done → open again.
        case check(String)
    }

    /// The watch's part of the checks strip, in the strip's order: the weigh-in, the weekly tape
    /// and the daily checks. A full set and a body-fat assessment need the phone, so they are left
    /// out. Empty when nothing the watch can do is open (the row is hidden then, like the strip).
    public static func pills(_ strip: [CoachBoard.StripItem]) -> [CoachBoard.StripItem] {
        let usable = strip.filter { act(for: $0) != nil }
        return usable.contains { $0.state == .open } ? usable : []
    }

    /// What tapping a pill does on the watch; nil for what only the phone does.
    public static func act(for item: CoachBoard.StripItem) -> Act? {
        switch item.action {
        case .weighIn:
            return .weighIn
        case .measure(let due):
            guard due.kind == .weekly, !due.sites.isEmpty else { return nil }
            return .measure(due.sites)
        case .check(let id):
            return .check(id)
        default:
            return nil
        }
    }

    /// A pill's short title: the check's name without its dose ("Creatine"), the site ("Waist")
    /// or "Weigh in".
    public static func pillTitle(_ item: CoachBoard.StripItem, plan: CoachPlan) -> String {
        if case .check(let id) = item.action, let check = plan.check(id: id) {
            let name = check.name.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? item.title : name
        }
        return item.title
    }

    // MARK: Weekly sites, one at a time

    /// The weekly tape sites on the watch: one site per screen, Save or Skip moves on.
    public struct TapeFlow: Equatable, Sendable {
        public let sites: [BodySite]
        /// The site on screen (`sites.count` when finished).
        public private(set) var index = 0
        /// What was saved so far.
        public private(set) var values = BodyValues()

        public init(sites: [BodySite]) {
            var seen = Set<BodySite>()
            self.sites = sites.filter { seen.insert($0).inserted }
        }

        /// The site on screen; nil when every site was saved or skipped.
        public var current: BodySite? { index < sites.count ? sites[index] : nil }
        public var isFinished: Bool { current == nil }
        /// The site after this one.
        public var next: BodySite? { index + 1 < sites.count ? sites[index + 1] : nil }
        /// "1 of 3"; nil with a single site.
        public var progress: String? {
            guard sites.count > 1, !isFinished else { return nil }
            return "\(index + 1) of \(sites.count)"
        }

        /// The sites saved, in order.
        public var savedSites: [BodySite] { sites.filter { values[$0] != nil } }

        /// Saves the current site's value (on the grid, in its plausible range) and moves on.
        public mutating func save(_ centimeters: Double) {
            guard let site = current else { return }
            var storage = values.storage
            storage[site.rawValue] = WatchCoach.snapped(centimeters, in: site.plausibleRange)
            values = BodyValues(storage)
            index += 1
        }

        /// Moves on without a value.
        public mutating func skip() {
            guard !isFinished else { return }
            index += 1
        }

        /// "Waist saved", "Waist and hip saved", "Narrow waist, hip and arm saved"; nil before
        /// anything was saved.
        public var savedText: String? {
            let titles = savedSites.enumerated().map { $0.offset == 0 ? $0.element.title : $0.element.title.lowercased() }
            guard let last = titles.last else { return nil }
            let list = titles.count > 2 ? titles.dropLast().joined(separator: ", ") + " and " + last
                : titles.joined(separator: " and ")
            return list + " saved"
        }
    }

    // MARK: Status line

    /// How the status reads (the phone's colours): in range, slower or faster, off track, or neither.
    public enum Tone: String, Equatable, Sendable {
        case good, watch, alert, neutral
    }

    /// "avg 74.6 · +0.15/wk · In range": the 7-day average, the decision rate and the status
    /// words of the active phase.
    public struct Status: Equatable, Sendable {
        /// The valid 7-day average (kg).
        public var average: Double?
        /// The valid decision rate (kg/week).
        public var rate: Double?
        /// "In range", "Slower than planned", "Faster than planned", "Gathering data" or
        /// "Off track"; nil without an active phase with a rate range.
        public var word: String?
        public var tone: Tone

        public init(average: Double?, rate: Double?, word: String?, tone: Tone) {
            self.average = average
            self.rate = rate
            self.word = word
            self.tone = tone
        }

        /// The numbers part: "avg 74.6 · +0.15/wk" ("" without either). `number` formats an
        /// absolute value with fixed decimals.
        public func numbersText(number: (Double, Int) -> String = WatchCoach.fixed) -> String {
            var parts: [String] = []
            if let average { parts.append("avg " + number(average, 1)) }
            if let rate { parts.append(WatchCoach.signed(rate, 2, number: number) + "/wk") }
            return parts.joined(separator: " · ")
        }

        /// The whole line: "avg 74.6 · +0.15/wk · In range".
        public func text(number: (Double, Int) -> String = WatchCoach.fixed) -> String {
            [numbersText(number: number), word ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    /// The status line of the active phase on the summary's day, in the phone's words
    /// (`WeightSignal.statusLine`): the weight signal's status, "Off track" only after the
    /// check-ins since the last calorie change were outside on the live side as often as the
    /// check-in asks, "New targets since Tue · first look Mon 21 Jan" while the rate restarts
    /// after a calorie change, "Paused · until 12 Feb" while paused. nil when there is nothing to
    /// show (no average and no phase with a range).
    public static func status(summary: WeightSignal.Summary, plan: CoachPlan, checkIns: [CheckInSnapshot],
                              calendar: Calendar = .current) -> Status? {
        let line = WeightSignal.statusLine(on: summary.day, plan: plan, rate: summary.rate, checkIns: checkIns, calendar: calendar)
        let word = line?.text(calendar: calendar)
        let average = summary.average.value
        guard average != nil || word != nil else { return nil }
        // While paused or before a new rate there is no rate to show.
        let rate = line?.isPaused == true ? nil : summary.rate.value
        return Status(average: average, rate: rate, word: word, tone: line.map { Tone(rawValue: $0.tone.rawValue) ?? .neutral } ?? .neutral)
    }

    /// The same from plain values (`checkIns` in any order): "Off track" once the phase's latest
    /// check-ins were outside on the live rate's side as often as the check-in asks
    /// (`plan.adjust.confirmChecks`, at least 1).
    public static func status(average: Double?, rate: Double?, status: WeightSignal.Status?, phaseID: String?,
                              plan: CoachPlan, checkIns: [CheckInSnapshot]) -> Status? {
        var word = status?.title
        var tone = status.map(self.tone(of:)) ?? .neutral
        if let status, status.isOutside, let phaseID, let phase = plan.phase(id: phaseID), let rate,
           let side = CheckInEngine.deviation(rate: rate, phase: phase, tolerance: plan.adjust.tolerance) {
            var inARow = 0
            for snapshot in checkIns.filter({ $0.phaseID == phaseID }).sorted(by: { $0.day > $1.day }) {
                guard snapshot.deviation == side else { break }
                inARow += 1
            }
            if inARow >= max(1, plan.adjust.confirmChecks) {
                word = CheckInVerdict.offTarget.title
                tone = .alert
            }
        }
        // A rate is only shown next to a phase's status, or with the average.
        guard average != nil || word != nil else { return nil }
        return Status(average: average, rate: rate, word: word, tone: tone)
    }

    public static func tone(of status: WeightSignal.Status) -> Tone {
        switch status {
        case .inRange: .good
        case .slower, .faster: .watch
        case .gathering: .neutral
        }
    }

    // MARK: Numbers

    /// A number with a decimal point and fixed decimals ("74.6"), without a minus for zero.
    public static func fixed(_ value: Double, _ decimals: Int) -> String {
        guard value.isFinite else { return "0" }
        let text = String(format: "%.\(max(0, decimals))f", value)
        return text.hasPrefix("-") && Double(text) == 0 ? String(text.dropFirst()) : text
    }

    /// "+0.15", "−0.20" (a real minus), "0.00" for zero, as the phone writes changes. `number`
    /// formats the absolute value.
    public static func signed(_ value: Double, _ decimals: Int, number: (Double, Int) -> String = WatchCoach.fixed) -> String {
        let text = number(abs(value), decimals)
        guard value.isFinite, fixed(abs(value), decimals) != fixed(0, decimals) else { return text }
        return (value < 0 ? "−" : "+") + text
    }
}
