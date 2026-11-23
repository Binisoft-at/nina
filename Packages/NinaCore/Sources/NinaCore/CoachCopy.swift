import Foundation

/// "Copy for my AI" (F16): the plan, the last four weeks and the latest body numbers as plain text
/// to paste into another AI, ending with the settings keys it may answer with, so its answer can be
/// imported as it is. Clipboard only: nothing leaves the device unless the person pastes it.
///
/// Weigh-ins read from Apple Health are left out unless `Input.includeHealth` is on (the person
/// switches it on). Numbers use a decimal point and ISO dates, so another AI reads them reliably.
public enum CoachCopy {
    /// Weeks in "Last 4 weeks".
    public static let weeks = 4
    /// The line before the key table that closes the text.
    public static let closingLine = "If you suggest changes, answer only with a setting,value block using these keys"

    /// Everything the text needs, as plain values.
    public struct Input: Sendable {
        public var today: DayKey
        /// Body data, meals, the profile's targets (used before a phase has targets) and the plan.
        /// `weightKg` must not come from Apple Health unless `includeHealth` is on.
        public var state: SettingsState
        /// Weigh-ins typed in Nina and read from Apple Health (`source`).
        public var readings: [WeightSignal.Reading]
        /// Use the Apple Health weigh-ins too.
        public var includeHealth: Bool
        /// Diary totals per day (at least `firstDay(today:)` through yesterday); missing days are empty.
        public var totals: [DayKey: DayTotals]
        /// Live day-type marks: DayKey raw value → day type id.
        public var dayTypeMarks: [String: String]
        /// Daily checks ticked done, per day.
        public var doneChecks: [DayKey: Set<String>]
        /// Days marked "incomplete log".
        public var incompleteDays: Set<DayKey>
        /// Tape records (oldest first or any order).
        public var tape: [BodyTapeRecord]
        /// Body-fat values from assessments and weigh-ins (the tape estimate is added here).
        public var bodyFat: [BodyFatReading]
        /// Saved weekly check-ins.
        public var checkIns: [CheckInSnapshot]
        /// The current settings file (`SettingsCSV.export`), shown so the AI can copy unchanged rows; "" = left out.
        public var currentSettings: String
        public var appName: String
        /// The tape-estimate formula: the profile's sex, else the one picked on the device (the
        /// app's `PhaseBodyFat.formula(sex:)`); nil = `NavyBodyFat.Formula(sex: state.sex)`.
        public var navyFormula: NavyBodyFat.Formula?

        public init(today: DayKey, state: SettingsState, readings: [WeightSignal.Reading] = [], includeHealth: Bool = false,
                    totals: [DayKey: DayTotals] = [:], dayTypeMarks: [String: String] = [:], doneChecks: [DayKey: Set<String>] = [:],
                    incompleteDays: Set<DayKey> = [], tape: [BodyTapeRecord] = [], bodyFat: [BodyFatReading] = [],
                    checkIns: [CheckInSnapshot] = [], currentSettings: String = "", appName: String = "Nina",
                    navyFormula: NavyBodyFat.Formula? = nil) {
            self.today = today
            self.state = state
            self.readings = readings
            self.includeHealth = includeHealth
            self.totals = totals
            self.dayTypeMarks = dayTypeMarks
            self.doneChecks = doneChecks
            self.incompleteDays = incompleteDays
            self.tape = tape
            self.bodyFat = bodyFat
            self.checkIns = checkIns
            self.currentSettings = currentSettings
            self.appName = appName
            self.navyFormula = navyFormula
        }

        /// The plan (empty without one).
        public var plan: CoachPlan { state.plan ?? CoachPlan() }
    }

    /// One week of "Last 4 weeks": seven whole days ending on `end`.
    public struct Week: Equatable, Sendable {
        public var start: DayKey
        public var end: DayKey
    }

    /// The four weeks, oldest first: seven-day blocks ending yesterday (today isn't over yet).
    public static func weekSpans(today: DayKey, calendar: Calendar = .current) -> [Week] {
        let last = today.adding(days: -1, calendar: calendar)
        return (0..<weeks).reversed().map { index in
            let end = last.adding(days: -7 * index, calendar: calendar)
            return Week(start: end.adding(days: -6, calendar: calendar), end: end)
        }
    }

    /// The first day whose diary the text reads.
    public static func firstDay(today: DayKey, calendar: Calendar = .current) -> DayKey {
        weekSpans(today: today, calendar: calendar).first?.start ?? today
    }

    /// The whole text.
    public static func text(_ input: Input, calendar: Calendar = .current) -> String {
        let context = Context(input, calendar: calendar)
        var lines: [String] = []
        lines.append("# My nutrition and body data from \(input.appName)")
        lines.append("As of \(input.today.rawValue). Read it, then help me with my plan. Weights in kg, energy in kcal, dates as YYYY-MM-DD.")
        lines.append("")
        lines.append(contentsOf: aboutMe(context))
        lines.append("")
        lines.append(contentsOf: planSummary(context))
        lines.append("")
        lines.append(contentsOf: lastWeeks(context))
        lines.append("")
        lines.append(contentsOf: body(context))
        let notes = context.plan.notes.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !notes.isEmpty {
            lines.append("")
            lines.append("## Notes from my plan")
            lines.append(contentsOf: notes.map { "- \($0)" })
        }
        let current = input.currentSettings.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty {
            lines.append("")
            lines.append("## My current settings in \(input.appName)")
            lines.append(SettingsCSV.currentSettingsNote)
            lines.append("```csv")
            lines.append(current)
            lines.append("```")
        }
        lines.append("")
        lines.append(contentsOf: answerRules())
        return lines.joined(separator: "\n")
    }

    // MARK: Context

    /// The values every part reads: the plan and the weight signal (Health left out unless allowed).
    struct Context {
        let input: Input
        let calendar: Calendar
        let plan: CoachPlan
        let signal: WeightSignal
        let leftOutHealth: Bool

        init(_ input: Input, calendar: Calendar) {
            self.input = input
            self.calendar = calendar
            plan = input.plan
            let readings = input.includeHealth ? input.readings : input.readings.filter { $0.source != .health }
            leftOutHealth = !input.includeHealth && input.readings.contains { $0.source == .health }
            signal = WeightSignal(readings, cutoffMinutes: plan.routine.morningCutoffMinutes, dayStartHour: input.state.dayStartHour,
                                  calendar: calendar)
        }

        var today: DayKey { input.today }
        var state: SettingsState { input.state }

        /// The targets a day had without the plan: training-day targets on training weekdays.
        func legacyTargets(on day: DayKey) -> DailyTargets {
            if let training = state.trainingTargets, state.trainingDays.contains(day, calendar: calendar) { return training }
            return state.targets
        }

        func typeName(_ id: String) -> String {
            guard !id.isEmpty else { return "Days without a day type" }
            return plan.dayType(id: id)?.name ?? id
        }

        func mealName(_ id: String) -> String {
            state.meals.first { $0.id == id }?.name ?? id
        }
    }

    // MARK: Parts

    static func aboutMe(_ context: Context) -> [String] {
        let state = context.state
        var lines = ["## About me"]
        var facts: [String] = []
        if state.sex != .unspecified { facts.append(state.sex.rawValue) }
        facts.append(state.birthYear > 0 ? "born \(state.birthYear)" : "birth year not set")
        facts.append(state.heightCm > 0 ? "height \(fixed(state.heightCm, 0)) cm" : "height not set")
        facts.append("activity: \(state.activity.title.lowercased())")
        lines.append("- " + facts.joined(separator: " · "))
        let signal = context.signal
        let average = signal.average(on: context.today)
        if let mean = average.mean {
            var text = "- Weight: 7-day average \(fixed(mean, 1)) kg (\(average.count) morning weigh-ins in the last 7 days)"
            if let rate = signal.rate(on: context.today, plan: context.plan).value {
                text += ", rate \(signed(rate, 2)) kg/week"
            }
            lines.append(text)
        } else if let last = signal.days.last, let morning = signal.morning(on: last) {
            lines.append("- Weight: last morning weigh-in \(fixed(morning.kilograms, 1)) kg on \(last.rawValue)")
        } else {
            lines.append("- Weight: no morning weigh-ins yet")
        }
        if context.leftOutHealth {
            lines.append("- Weigh-ins from Apple Health are left out.")
        }
        return lines
    }

    static func planSummary(_ context: Context) -> [String] {
        let plan = context.plan
        let today = context.today
        var lines = ["## My plan"]
        guard plan.isSetUp else {
            let state = context.state
            lines.append("- No coach plan yet. Goal: \(state.goal.title.lowercased())"
                         + (state.goal == .maintain ? "" : ", \(fixed(state.ratePerWeek, 2)) kg/week"))
            lines.append("- Daily targets: \(targetsText(state.targets))")
            if let training = state.trainingTargets, !state.trainingDays.isEmpty {
                lines.append("- Training days (\(state.trainingDays.summary)): \(targetsText(training))")
            }
            return lines
        }
        let active = plan.activePhase(on: today)
        let phases = plan.phases.sorted { ($0.start ?? today) < ($1.start ?? today) }
        for phase in phases {
            lines.append(contentsOf: phaseLines(phase, isActive: phase.id == active?.id, context: context))
        }
        if let pause = plan.pause(on: today) {
            let until = pause.end.map { "until \($0.rawValue)" } ?? "until I resume"
            lines.append("- Coaching is paused since \(pause.start.rawValue), \(until) (\(pause.reason.rawValue)).")
        }
        let revision = plan.revision(on: today)
        if !plan.dayTypes.isEmpty {
            lines.append("- Day types" + (active.map { " (targets in \"\($0.name)\")" } ?? "") + ":")
            for type in plan.dayTypes {
                var text = "  - \(type.emoji.isEmpty ? "" : type.emoji + " ")\(type.name) (id \(type.id)): \(scheduleText(type))"
                if let revision {
                    if let own = revision.byType[type.id] {
                        text += " – \(targetsText(own))"
                    } else if revision.baseline != nil {
                        text += " – same as the phase baseline"
                    }
                }
                lines.append(text)
            }
            if let revision, let average = plan.plannedWeekAverage(revision) {
                lines.append("  - Planned week average: \(SettingsCSV.grouped(average)) kcal a day")
            }
        }
        lines.append("- Protein per meal: \(proteinText(context))")
        if !plan.checks.isEmpty {
            lines.append("- Daily checks:")
            for check in plan.checks {
                lines.append("  - \(checkText(check, context: context))")
            }
        }
        lines.append("- Measuring: \(routineText(plan.routine))")
        let adjust = plan.adjust
        lines.append("- Weekly check-in on \(weekdayName(plan.routine.checkInWeekday)); calories are adjusted after "
                     + "\(adjust.windowMinDays)–\(adjust.windowMaxDays) days of weigh-ins, by \(fixed(adjust.stepMin, 0))–"
                     + "\(fixed(adjust.stepMax, 0)) kcal a day, at most once in \(adjust.lockDays) days")
        let goal = plan.longTerm
        if goal.isSet || !goal.note.isEmpty {
            var parts: [String] = []
            if goal.weightKg > 0 { parts.append("\(fixed(goal.weightKg, 1)) kg") }
            if goal.bodyFat > 0 { parts.append("\(fixed(goal.bodyFat, 1)) % body fat") }
            if goal.waistCm > 0 { parts.append("waist \(fixed(goal.waistCm, 1)) cm") }
            if let date = goal.date { parts.append("by \(date.rawValue)") }
            var text = "- Long-term goal: " + (parts.isEmpty ? "not set" : parts.joined(separator: ", "))
            if !goal.note.isEmpty { text += " – \(goal.note)" }
            lines.append(text)
        }
        return lines
    }

    static func phaseLines(_ phase: CoachPlan.Phase, isActive: Bool, context: Context) -> [String] {
        let today = context.today
        var status: String
        if isActive {
            status = "running"
            if let week = phase.week(on: today, calendar: context.calendar) {
                status += ", week \(week)" + (phase.weeks(calendar: context.calendar).map { " of \($0)" } ?? "")
            }
        } else if phase.status == .done {
            status = "done"
        } else if phase.isStarted {
            status = "ended"
        } else {
            status = "planned, not started yet"
        }
        let name = phase.name.isEmpty ? CoachPlan.Phase.defaultName(for: phase.goal) : phase.name
        var text = "- Phase \(phase.id) \"\(name)\" (\(phase.goal.rawValue), \(status)): "
        let start = phase.start.map { (phase.startApprox ? "~" : "") + $0.rawValue } ?? "no start date"
        let end = phase.end.map { (phase.endApprox ? "~" : "") + $0.rawValue } ?? "open end"
        text += "\(start) to \(end)"
        var details: [String] = []
        if phase.rateRange.upperBound > 0 {
            let range = phase.signedRateRange
            details.append("rate \(signed(range.lowerBound, 2)) to \(signed(range.upperBound, 2)) kg/week")
        }
        let review = [phase.reviewMin, phase.reviewMax].filter { $0 > 0 }
        if let low = review.min(), let high = review.max() {
            details.append(low == high ? "review at \(fixed(low, 1)) kg" : "review at \(fixed(low, 1))–\(fixed(high, 1)) kg")
        }
        if phase.targetWeight > 0 { details.append("target \(fixed(phase.targetWeight, 1)) kg") }
        if phase.targetBodyFat > 0 { details.append("target body fat \(fixed(phase.targetBodyFat, 1)) %") }
        if phase.bodyFatCeiling > 0 { details.append("review at body fat \(fixed(phase.bodyFatCeiling, 1)) %") }
        let revision = isActive ? phase.revision(on: today) : phase.revisions.first
        if let baseline = revision?.baseline {
            details.append("baseline \(targetsText(baseline))")
        } else if !isActive, phase.revisions.isEmpty {
            details.append("no targets yet")
        }
        if !details.isEmpty { text += "; " + details.joined(separator: "; ") }
        var lines = [text]
        if !phase.note.isEmpty { lines.append("  - Note: \(phase.note)") }
        return lines
    }

    static func lastWeeks(_ context: Context) -> [String] {
        var lines = ["## Last \(weeks) weeks"]
        for week in weekSpans(today: context.today, calendar: context.calendar) {
            lines.append("")
            lines.append(contentsOf: weekLines(week, context: context))
        }
        return lines
    }

    static func weekLines(_ week: Week, context: Context) -> [String] {
        let calendar = context.calendar
        let plan = context.plan
        let signal = context.signal
        var lines = ["### \(week.start.rawValue) to \(week.end.rawValue)"]

        let average = signal.average(on: week.end)
        if let mean = average.mean {
            var text = "- Morning weight: average \(fixed(mean, 1)) kg (\(average.count) of 7 mornings)"
            if let change = signal.weeklyChange(on: week.end) {
                text += ", \(signed(change.kilograms, 1)) kg vs. the week before"
            }
            lines.append(text)
        } else {
            lines.append("- Morning weight: no weigh-ins")
        }
        let rate = signal.rate(on: week.end, plan: plan)
        if let value = rate.value {
            lines.append("- Rate: \(signed(value, 2)) kg/week (\(rate.weighIns) weigh-ins over \(rate.spanDays) days)")
        } else if average.mean != nil {
            lines.append("- Rate: not enough weigh-ins yet (it needs \(plan.adjust.windowMinDays) days and "
                         + "\(WeightSignal.rateMinimumWeighIns) morning weigh-ins)")
        }

        let weightKg = signal.bodyWeight(on: week.end)?.kilograms ?? context.state.weightKg
        let days = DayKey.range(week.start, through: week.end, calendar: calendar).map { day in
            DayAdherence(plan: plan, totals: context.input.totals[day] ?? DayTotals(day: day, entries: []),
                         marks: context.input.dayTypeMarks, fallback: context.legacyTargets(on: day), weightKg: weightKg,
                         mealSlots: context.state.meals.count, doneChecks: context.input.doneChecks[day] ?? [],
                         incomplete: context.input.incompleteDays.contains(day), calendar: calendar)
        }
        let summary = Adherence.summary(days, plan: plan)
        var logged = "- Logged: \(summary.loggedDays) of \(summary.days) days, on plan \(summary.onPlanDays)"
        if summary.pausedDays > 0 { logged += " (coaching paused \(summary.pausedDays) days, left out)" }
        lines.append(logged)
        if summary.loggedDays > 0 {
            lines.append("- Intake: \(SettingsCSV.grouped(summary.averageIntake)) kcal a day on average vs. a target of "
                         + "\(SettingsCSV.grouped(summary.averageTarget)) (logged days)")
            let types = summary.byType.filter { $0.loggedDays > 0 }
            if !plan.dayTypes.isEmpty, !types.isEmpty {
                let parts = types.map { type in
                    "\(context.typeName(type.typeID)) \(SettingsCSV.grouped(type.averageIntake)) of "
                        + "\(SettingsCSV.grouped(type.averageTarget)) kcal (\(type.loggedDays) \(type.loggedDays == 1 ? "day" : "days"))"
                }
                lines.append("- By day type: " + parts.joined(separator: " · "))
            }
            var protein = "- Protein: target reached on \(summary.proteinDays) of \(summary.loggedDays) logged days, "
                + "average \(fixed(summary.averageProtein, 0)) of \(fixed(summary.averageProteinTarget, 0)) g"
            if summary.proteinMealsTarget > 0 {
                protein += "; protein meals \(summary.proteinMeals) of \(summary.proteinMealsTarget)"
            }
            lines.append(protein)
        }
        let checks = summary.checks.filter { $0.due > 0 || $0.done > 0 }
        let flexible = summary.flexible.filter { $0.planned > 0 }
        if !checks.isEmpty || !flexible.isEmpty {
            var parts = checks.map { tally in
                "\(plan.check(id: tally.checkID)?.name ?? tally.checkID) \(tally.done) of \(tally.due)" + (tally.isOptional ? " (optional)" : "")
            }
            parts += flexible.map { "\(context.typeName($0.typeID)) days \($0.count) of \($0.planned)" }
            lines.append("- Checks: " + parts.joined(separator: " · "))
        }
        if let waist = waistLine(in: week, context: context) { lines.append(waist) }
        for snapshot in context.input.checkIns where snapshot.day >= week.start && snapshot.day <= week.end {
            let verdict = snapshot.verdict?.title ?? "saved"
            let decision = snapshot.decisionText
            lines.append("- Check-in on \(snapshot.day.rawValue): \(verdict)" + (decision.isEmpty || decision == verdict ? "" : ", \(decision)"))
        }
        return lines
    }

    /// The last waist value of the week (the narrow waist first for women), standard readings first.
    static func waistLine(in week: Week, context: Context) -> String? {
        let records = context.input.tape.filter { $0.day >= week.start && $0.day <= week.end }
            .sorted { ($0.day, $0.time ?? .distantPast) < ($1.day, $1.time ?? .distantPast) }
        let withWaist = records.filter { BodyComposition.waist(in: $0.values, sex: context.state.sex) != nil }
        guard let record = withWaist.last(where: \.isStandard) ?? withWaist.last,
              let waist = BodyComposition.waist(in: record.values, sex: context.state.sex) else { return nil }
        return "- Waist: \(fixed(waist, 1)) cm on \(record.day.rawValue)" + (record.isStandard ? "" : " (not a standard morning reading)")
    }

    static func body(_ context: Context) -> [String] {
        var lines = ["## Body"]
        let routine = context.plan.routine
        let records = context.input.tape.sorted { ($0.day, $0.time ?? .distantPast) < ($1.day, $1.time ?? .distantPast) }
        let full = records.last { BodySchedule.isFullSet(Set($0.values.sites.keys), routine: routine) }
        if let record = full ?? records.last {
            let title = full != nil ? "Latest full measurement" : "Latest tape measurement"
            let sites = BodySite.allCases.compactMap { site in
                record.values[site].map { "\(site.title) \(fixed($0, 1)) cm" }
            }
            lines.append("- \(title) (\(record.day.rawValue)\(record.isStandard ? ", morning, before eating" : "")): "
                         + sites.joined(separator: " · "))
        } else {
            lines.append("- No tape measurements yet")
        }
        var readings = context.input.bodyFat
        let formula = context.input.navyFormula ?? NavyBodyFat.Formula(sex: context.state.sex)
        if context.state.heightCm > 0, formula != nil,
           let estimate = NavyBodyFat.estimate(formula: formula, heightCm: context.state.heightCm, records: context.input.tape,
                                               calendar: context.calendar).estimate {
            readings.append(BodyFatReading(navy: estimate))
        }
        let series = BodyFatSeries.group(readings)
        if series.isEmpty {
            lines.append("- No body-fat values yet")
        } else {
            lines.append("- Body fat by method:")
            for item in series {
                guard let latest = item.latest else { continue }
                let error = item.method.errorBand != nil ? "typical error \(item.method.errorText) points" : "error unknown"
                var text = "  - \(item.title): \(fixed(latest.bodyFat, 1)) % on \(latest.day.rawValue) (\(error))"
                if item.count > 1, let first = item.first {
                    text += "; first \(fixed(first.bodyFat, 1)) % on \(first.day.rawValue), \(item.count) values"
                }
                if let lean = latest.leanKg, let fat = latest.fatKg {
                    text += "; lean \(fixed(lean, 1)) kg, fat \(fixed(fat, 1)) kg"
                }
                lines.append(text)
            }
        }
        return lines
    }

    /// The closing part: the answer rules and the key table (the text ends with the table).
    static func answerRules() -> [String] {
        var lines = ["## How to answer"]
        lines.append("\(closingLine). The first line is exactly setting,value. Leave out every setting that stays the same. "
                     + "A group you write (all day_type.*, phase.N.* or check.* rows) replaces that whole group, so write all its rows again. "
                     + "A phase that has started stays even when you leave it out; phase.N.remove,yes deletes one.")
        lines.append("")
        lines.append("| setting | value |")
        lines.append("|---|---|")
        for key in SettingsCSV.keys + SettingsCSV.planKeys {
            lines.append("| \(key.name) | \(key.meaning)\(key.example.isEmpty ? "" : " – e.g. \(key.example)") |")
        }
        return lines
    }

    // MARK: Text pieces

    static func targetsText(_ targets: DailyTargets) -> String {
        "\(SettingsCSV.grouped(targets.energy)) kcal, protein \(fixed(targets.protein, 0)) g, carbs \(fixed(targets.carbs, 0)) g, "
            + "fat \(fixed(targets.fat, 0)) g"
    }

    static func scheduleText(_ type: CoachPlan.DayType) -> String {
        switch type.schedule {
        case .fixed: type.weekdays.isEmpty ? "fixed, no weekdays yet" : type.weekdays.summary
        case .flexible: type.perWeek > 0 ? "flexible, \(type.perWeek) per week" : "flexible"
        case .default: "all other days"
        }
    }

    static func proteinText(_ context: Context) -> String {
        let protein = context.plan.protein
        let count = protein.effectiveCount(mealSlots: context.state.meals.count)
        var text: String
        if protein.mealMin > 0 {
            text = protein.mealMax > protein.mealMin
                ? "\(fixed(protein.mealMin, 0))–\(fixed(protein.mealMax, 0)) g per protein meal"
                : "at least \(fixed(protein.mealMin, 0)) g per protein meal"
        } else {
            text = "not set (Nina uses 0.4 g per kg body weight per meal)"
        }
        text += ", \(count) protein meals a day"
        if !protein.meals.isEmpty { text += " (" + protein.meals.map(context.mealName).joined(separator: ", ") + ")" }
        return text
    }

    static func checkText(_ check: CoachPlan.Check, context: Context) -> String {
        var text = check.name + (check.dose.isEmpty ? "" : " (\(check.dose))")
        switch check.timing {
        case .anytime: text += ", anytime"
        case .meal(let id): text += ", with \(context.mealName(id).lowercased())"
        case .time(let minutes): text += ", at \(ClockTime.text(minutes))"
        }
        switch check.days {
        case .daily: text += ", every day"
        case .weekdays(let days): text += ", on \(days.summary)"
        case .dayTypes(let ids): text += ", on " + ids.map(context.typeName).joined(separator: " and ") + " days"
        }
        if check.isOptional { text += ", optional" }
        if check.affectsWeight { text += ", can move the scale" }
        return text
    }

    static func routineText(_ routine: CoachPlan.Routine) -> String {
        func sites(_ list: [BodySite]) -> String { list.isEmpty ? "none" : list.map { $0.title.lowercased() }.joined(separator: ", ") }
        let method = routine.bodyFatMethod?.title ?? "the most accurate method with 2 values"
        return "weigh in daily at \(ClockTime.text(routine.weighInMinutes)) (morning weights until "
            + "\(ClockTime.text(routine.morningCutoffMinutes))); every week: \(sites(routine.weeklySites)); full set every "
            + "\(routine.fullEveryWeeks) weeks: \(sites(routine.fullSites)); body fat every \(routine.bodyFatEveryWeeks) weeks "
            + "(\(method)); side: \(routine.side.rawValue)"
            + (routine.thighMark.isEmpty ? "" : "; thigh: \(routine.thighMark)")
    }

    static func weekdayName(_ weekday: Int) -> String {
        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        return names[max(1, min(7, weekday)) - 1]
    }

    /// A number with a decimal point and fixed decimals ("80.0").
    static func fixed(_ value: Double, _ decimals: Int) -> String {
        guard value.isFinite else { return "0" }
        let text = String(format: "%.\(max(0, decimals))f", value)
        return text.hasPrefix("-") && Double(text) == 0 ? String(text.dropFirst()) : text
    }

    /// A signed number ("+0.15", "-0.20", "+0.00").
    static func signed(_ value: Double, _ decimals: Int) -> String {
        let text = fixed(abs(value), decimals)
        let isZero = Double(text) == 0
        return (value < 0 && !isZero ? "-" : "+") + text
    }
}
