import Foundation
import SwiftData
import NinaCore

// What the body page (Progress → Body, the Body sidebar item on the Mac) shows, computed once per
// data change from a `CoachContext`: the due items, the phase header, the weight card and chart,
// the body goal, the tape tiles, body composition, the phases timeline, the check-ins and the
// check adherence. Foundation and NinaCore only, so it type-checks without SwiftUI. Apple Health
// weigh-ins come in live through the context and are never stored.

/// How a status reads: in range (good), slower or faster (watch), off track (alert), or neither.
enum BodyPageTone: Equatable {
    case good, watch, alert, neutral
}

/// The weight chart's ranges: the last 4 weeks, the active phase, everything.
enum BodyPageRange: String, CaseIterable, Identifiable {
    case month, phase, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .month: "4W"
        case .phase: "Phase"
        case .all: "All"
        }
    }
}

/// A body item due today (weigh-in, tape, full set, body fat) or the week's check-in / review.
struct BodyPageDue: Identifiable {
    let id: String
    let title: String
    let detail: String?
    let symbol: String
    let action: CoachBoard.Action
}

/// "Lean gain · week 3 of 16", its dates, rate range and status.
struct BodyPagePhaseHeader {
    let phaseID: String
    let title: String
    let dates: String?
    let rate: String?
    let status: String
    let tone: BodyPageTone
    /// Share of the phase gone (0…1); nil without an end.
    let progress: Double?
    let projectedEnd: Double?
    let checkpointLine: String?
    let isActive: Bool
}

/// One weigh-in on the chart.
struct BodyPageWeightDot: Identifiable {
    let id: String
    let day: DayKey
    let date: Date
    let kilograms: Double
    let isTagged: Bool
    let isHealth: Bool
}

/// A value on a day (the 7-day average line).
struct BodyPageWeightValue: Identifiable {
    let id: String
    let date: Date
    let kilograms: Double
}

/// The phase corridor on a day.
struct BodyPageBand: Identifiable {
    let id: String
    let date: Date
    let low: Double
    let high: Double
}

/// A paused span (shaded).
struct BodyPageSpan: Identifiable {
    let id: String
    let start: Date
    let end: Date
}

/// Everything one range of the weight chart draws.
struct BodyPageWeightChart {
    let range: BodyPageRange
    let start: Date
    let end: Date
    /// Morning weights (tagged ones marked).
    let mornings: [BodyPageWeightDot]
    /// Later weigh-ins of a day: faint, left out of every calculation.
    let others: [BodyPageWeightDot]
    let averages: [BodyPageWeightValue]
    /// The EMA trend on the days with a morning weight (thin, the "estimate" line).
    let trend: [BodyPageWeightValue]
    let corridor: [BodyPageBand]
    let pauses: [BodyPageSpan]
    let target: Double?
    let review: ClosedRange<Double>?
    let phaseEnd: Date?
    let yDomain: ClosedRange<Double>

    var isEmpty: Bool { mornings.isEmpty && others.isEmpty }
    var hasTagged: Bool { mornings.contains { $0.isTagged } }
    /// Untagged and tagged morning weights (drawn differently).
    var plainMornings: [BodyPageWeightDot] { mornings.filter { !$0.isTagged } }
    var taggedMornings: [BodyPageWeightDot] { mornings.filter(\.isTagged) }
}

/// The weight card's numbers.
struct BodyPageWeight {
    /// The valid 7-day average.
    let average: Double?
    /// "Weigh in 2 more mornings to see your average" (only while there are weigh-ins).
    let averagePrompt: String?
    /// The weight body math uses while the average isn't valid (trend or latest): "estimate".
    let estimate: Double?
    let weeklyChange: WeightSignal.Change?
    /// The decision rate (kg/week) when valid.
    let rate: Double?
    /// Why there is no rate yet.
    let rateNote: String?
    /// "±0.6 kg" personal day-to-day swing.
    let noise: Double?
    let usesHealth: Bool
    /// The active phase's goal: "+0.15 to +0.25 kg a week".
    let goalText: String?
    let charts: [BodyPageRange: BodyPageWeightChart]
    /// The chart's accessibility summary.
    let summaryText: String
    let hasWeighIns: Bool

    func chart(_ range: BodyPageRange) -> BodyPageWeightChart? { charts[range] }
}

/// The long-term body goal card.
struct BodyPageGoal {
    let card: BodyGoalCard
    let goal: CoachPlan.LongTerm
    /// The tracking series ("DEXA scan").
    let seriesTitle: String?
    let weightRow: BodyGoalWeightRow?
    /// "Reaching 78 kg at 14 % depends on gaining about 3 kg of lean mass."
    let honestLine: String?
    /// "goal date likely later (~Sep 2031)".
    let outlook: String?
}

/// A tape site tile: the latest value and the change since the phase start.
struct BodyPageTile: Identifiable {
    let site: BodySite
    let value: Double?
    let day: DayKey?
    let change: GirthChange?
    var id: String { site.rawValue }

    /// "+1.2 cm" when clear, else "no clear change"; nil without two readings.
    var changeText: String? {
        guard let change, change.from.day < change.to.day else { return nil }
        guard change.isClear else { return GirthTrend.noClearChange }
        return BodyPageText.signed(change.change, decimals: 1) + " cm"
    }
}

/// A body-fat value on the composition chart.
struct BodyPageFatPoint: Identifiable {
    let id: String
    let series: String
    let date: Date
    let bodyFat: Double
    let low: Double?
    let high: Double?
}

/// One body-fat series (method and device).
struct BodyPageFatSeries: Identifiable {
    let id: String
    let title: String
    let latest: Double
    let latestDay: DayKey
    /// "±1.5", "unknown".
    let band: String
    let count: Int
    let isTracking: Bool
}

/// Body composition: body fat by method, lean and fat mass, ratios, FFMI and the next full set.
struct BodyPageComposition {
    let points: [BodyPageFatPoint]
    let series: [BodyPageFatSeries]
    /// The latest composition of the tracking series.
    let latest: BodyComposition?
    let latestDay: DayKey?
    let latestTitle: String?
    /// The change from the tracking series' previous value.
    let change: CompositionChange?
    let waistToHeight: Double?
    let waistToHip: Double?
    let ffmi: Double?
    let normalisedFFMI: Double?
    let nextFull: BodySchedule.Due?
    /// Why the tape estimate is missing ("Height needed for the tape estimate").
    let tapeNote: String?

    var hasBodyFat: Bool { !series.isEmpty }
    var isEmpty: Bool { series.isEmpty && waistToHeight == nil && nextFull == nil && tapeNote == nil }
}

/// Planned, active or done.
enum BodyPagePhaseState: Equatable {
    case planned, active, done
    var title: String {
        switch self {
        case .planned: "Planned"
        case .active: "Active"
        case .done: "Done"
        }
    }
}

/// A phase on the timeline capsule (fractions 0…1 of the timeline).
struct BodyPageSegment: Identifiable {
    let id: String
    let name: String
    let goal: WeightGoal
    let state: BodyPagePhaseState
    let x0: Double
    let x1: Double
    let dates: String
}

/// A phase in the list under the timeline.
struct BodyPagePhaseRow: Identifiable {
    let id: String
    let name: String
    let goal: WeightGoal
    let state: BodyPagePhaseState
    let dates: String
    let detail: String?
}

/// The phases timeline: a capsule from the first phase's start to the last one's end.
struct BodyPageTimeline {
    let segments: [BodyPageSegment]
    let rows: [BodyPagePhaseRow]
    /// Today's position (0…1), nil outside the timeline.
    let today: Double?
    /// When the review checkpoint comes at the ends of the rate range (fractions).
    let review: ClosedRange<Double>?
    /// The long-term goal's date (fraction).
    let goalFlag: Double?
    let startText: String
    let endText: String
}

/// A saved check-in in the list.
struct BodyPageCheckIn: Identifiable {
    let id: String
    let week: DayKey
    let title: String
    let verdict: String
    let tone: BodyPageTone
    let delta: String?
    let decision: String
}

/// Everything the body page shows.
@MainActor
struct BodyPageData {
    let today: DayKey
    let isSetUp: Bool
    let due: [BodyPageDue]
    let header: BodyPagePhaseHeader?
    let weight: BodyPageWeight
    let goal: BodyPageGoal?
    let tiles: [BodyPageTile]
    let composition: BodyPageComposition
    let timeline: BodyPageTimeline?
    let checkIns: [BodyPageCheckIn]
    /// "Creatine 6 of 7 days · Vitamin D 7 of 7 days" (the last 7 days).
    let checkLine: String?
    /// The active phase's start: tile changes and site details count from it.
    let phaseStart: DayKey?
    let measurementCount: Int

    /// The page for today with the app's data (typed and live Health weigh-ins).
    static func load(app: AppModel, now: Date = Date()) -> BodyPageData {
        let context = CoachContext.load(app: app, day: app.today, now: now)
        return BodyPageData(context: context, store: app.store)
    }

    init(context: CoachContext, store: NinaStore) {
        let today = context.today
        let plan = context.plan
        let sex = context.settings.body.sex
        let heightCm = store.profile()?.heightCm ?? 0
        let phase = context.activePhase
        self.today = today
        isSetUp = context.isSetUp
        phaseStart = phase?.start
        measurementCount = context.measurements.count
        due = BodyPageData.dueItems(context)
        header = BodyPageData.header(context)
        weight = BodyPageData.weight(context)
        let routine = plan.isSetUp ? plan.routine : CoachPlan.Routine.defaults(for: sex)
        tiles = BodyPageData.tileSites(routine: routine).map { site in
            BodyPageData.tile(site, records: context.tapeRecords, since: phase?.start)
        }
        let composition = BodyPageData.composition(context, heightCm: heightCm)
        self.composition = composition.page
        goal = BodyPageData.goal(context, points: composition.trackingPoints, seriesTitle: composition.page.latestTitle)
        timeline = BodyPageData.timeline(context)
        checkIns = BodyPageData.checkIns(context.checkIns, calendar: context.calendar)
        checkLine = BodyPageData.checkLine(context, store: store)
    }
}

// MARK: - Parts

extension BodyPageData {
    static func dueItems(_ context: CoachContext) -> [BodyPageDue] {
        var items: [BodyPageDue] = context.dueItems.map { item in
            var detail = item.overdueText
            if detail == nil {
                switch item.reason {
                case .baseline: detail = "Baseline"
                case .phaseStart: detail = "Phase start"
                case .phaseEnd: detail = "Phase end"
                case .checkpoint: detail = "Review checkpoint"
                case .schedule: detail = nil
                }
            }
            if item.kind == .full, item.includesAssessment {
                detail = [detail, "with body fat"].compactMap { $0 }.joined(separator: " · ")
            }
            let symbol: String
            let action: CoachBoard.Action
            switch item.kind {
            case .weighIn:
                symbol = "scalemass"
                action = .weighIn
            case .weekly:
                symbol = "ruler"
                action = .measure(item)
            case .full:
                symbol = "figure.arms.open"
                action = .measure(item)
            case .assessment:
                symbol = "percent"
                action = .assessment(item)
            }
            return BodyPageDue(id: item.id, title: item.title, detail: detail, symbol: symbol, action: action)
        }
        if let card = context.board.card, card.kind == .checkIn || card.kind == .review {
            items.append(BodyPageDue(id: card.key, title: card.title, detail: card.message,
                                     symbol: card.kind == .checkIn ? "checklist" : "flag.checkered", action: card.primary.action))
        }
        return items
    }

    static func header(_ context: CoachContext) -> BodyPagePhaseHeader? {
        let plan = context.plan
        guard plan.isSetUp else { return nil }
        let calendar = context.calendar
        let today = context.today
        let summary = context.summary
        guard let phase = context.activePhase else {
            let planned = plan.phases.filter { !$0.isStarted && $0.start != nil }
                .sorted { ($0.start ?? today) < ($1.start ?? today) }
            guard let next = planned.first, let start = next.start else { return nil }
            let isDue = plan.duePhase(on: today)?.id == next.id
            return BodyPagePhaseHeader(
                phaseID: next.id, title: "Next: \(BodyPageText.name(of: next))",
                dates: "from " + BodyPageText.day(start, approx: next.startApprox, today: today), rate: rateText(next),
                status: isDue ? "Ready to start" : "Planned", tone: .neutral, progress: nil, projectedEnd: nil,
                checkpointLine: nil, isActive: false)
        }
        var title = BodyPageText.name(of: phase)
        if let week = phase.week(on: today, calendar: calendar) {
            if let weeks = phase.weeks(calendar: calendar) {
                title += " · week \(week) of \(weeks)"
            } else {
                title += " · week \(week)"
            }
        }
        var progress: Double?
        if let start = phase.start, let end = phase.end, end >= start {
            let total = Double(start.days(to: end, calendar: calendar) + 1)
            let gone = Double(start.days(to: today, calendar: calendar) + 1)
            progress = min(1, max(0, gone / total))
        }
        let (status, tone) = statusWords(context, phase: phase)
        var checkpointLine: String?
        if let reached = summary.checkpointReached {
            checkpointLine = "Review weight reached on \(Fmt.shortDay(reached, calendar: calendar))"
        } else if let checkpoint = summary.checkpoint {
            if let weeks = summary.weeksToCheckpoint, weeks >= 0.5 {
                let rounded = Int(weeks.rounded())
                checkpointLine = "Review at \(Fmt.kilograms(checkpoint)) in about \(rounded) \(rounded == 1 ? "week" : "weeks")"
            } else {
                checkpointLine = "Review at \(Fmt.kilograms(checkpoint))"
            }
        }
        return BodyPagePhaseHeader(
            phaseID: phase.id, title: title, dates: phaseDates(phase, today: today), rate: rateText(phase), status: status, tone: tone,
            progress: progress, projectedEnd: summary.projectedEnd, checkpointLine: checkpointLine, isActive: true)
    }

    /// The status words of the active phase: the weight signal's, "Off track" only after the
    /// check-ins in a row outside the range on the same side.
    static func statusWords(_ context: CoachContext, phase: CoachPlan.Phase) -> (String, BodyPageTone) {
        guard let status = context.summary.status else { return ("No rate set", .neutral) }
        let deviations: [CheckInEngine.Deviation?] = context.checkIns.filter { $0.phaseID == phase.id }.map(\.deviation)
        let inARow = max(2, context.plan.adjust.confirmChecks)
        if status.isOutside, WeightSignal.Status.isOffTrack(deviations: deviations, inARow: inARow) {
            return (CheckInVerdict.offTarget.title, .alert)
        }
        return (status.title, tone(of: status))
    }

    static func tone(of status: WeightSignal.Status) -> BodyPageTone {
        switch status {
        case .inRange: .good
        case .slower, .faster: .watch
        case .gathering: .neutral
        }
    }

    static func tone(of verdict: CheckInVerdict?) -> BodyPageTone {
        switch verdict {
        case .inRange?: .good
        case .slower?, .faster?: .watch
        case .offTarget?: .alert
        default: .neutral
        }
    }

    /// "+0.15 to +0.25 kg a week" (signed by the phase's direction); nil without a range.
    static func rateText(_ phase: CoachPlan.Phase) -> String? {
        guard let range = WeightSignal.range(for: phase) else { return nil }
        return BodyPageText.range(range) + " kg a week"
    }

    /// "7 Jan – ~26 May", "from 7 Jan", nil without a start.
    static func phaseDates(_ phase: CoachPlan.Phase, today: DayKey) -> String? {
        guard let start = phase.start else { return nil }
        let from = BodyPageText.day(start, approx: phase.startApprox, today: today)
        guard let end = phase.end else { return "from " + from }
        return from + " – " + BodyPageText.day(end, approx: phase.endApprox, today: today)
    }

    // MARK: Weight

    static func weight(_ context: CoachContext) -> BodyPageWeight {
        let summary = context.summary
        let phase = context.activePhase
        let hasWeighIns = !context.weights.isEmpty || !context.healthReadings.isEmpty
        let average = summary.average.value
        var rateNote: String?
        if summary.rate.value == nil, hasWeighIns {
            rateNote = "The rate needs \(summary.rate.minimumWeighIns) morning weigh-ins over \(summary.rate.minimumDays / 7) weeks (\(summary.rate.weighIns) so far)."
        }
        let goalText = phase.flatMap { rateText($0) }
        var charts: [BodyPageRange: BodyPageWeightChart] = [:]
        for range in BodyPageRange.allCases { charts[range] = chart(context, range: range) }
        return BodyPageWeight(
            average: average,
            averagePrompt: hasWeighIns ? summary.average.prompt : nil,
            estimate: average == nil ? summary.bodyWeight?.kilograms : nil,
            weeklyChange: summary.weeklyChange,
            rate: summary.rate.value,
            rateNote: rateNote,
            noise: summary.noise,
            usesHealth: summary.usesHealth,
            goalText: goalText,
            charts: charts,
            summaryText: weightSummary(context),
            hasWeighIns: hasWeighIns)
    }

    /// "This week +0.20 kg, inside your goal of +0.15 to +0.25 kg a week. 7-day average 76.4 kg."
    static func weightSummary(_ context: CoachContext) -> String {
        let summary = context.summary
        var parts: [String] = []
        var first: String
        if let change = summary.weeklyChange {
            first = "This week " + BodyPageText.signed(change.kilograms, decimals: 2) + " kg"
        } else if let rate = summary.rate.value {
            first = "Rate " + BodyPageText.signed(rate, decimals: 2) + " kg a week"
        } else if context.weights.isEmpty, context.healthReadings.isEmpty {
            first = "No weigh-ins yet"
        } else {
            first = summary.average.prompt ?? "Not enough weigh-ins for a weekly change yet"
        }
        if let phase = context.activePhase, let range = WeightSignal.range(for: phase), let status = summary.status {
            let goal = BodyPageText.range(range) + " kg a week"
            switch status {
            case .inRange: first += ", inside your goal of " + goal
            case .slower, .faster, .gathering: first += ", " + status.title.lowercased() + " – your goal is " + goal
            }
        }
        parts.append(first)
        if let average = summary.average.value { parts.append("7-day average " + Fmt.kilograms(average)) }
        return parts.joined(separator: ". ") + "."
    }

    static func chart(_ context: CoachContext, range: BodyPageRange) -> BodyPageWeightChart {
        let calendar = context.calendar
        let signal = context.signal
        let today = context.today
        let phase = context.activePhase
        let firstWeighIn = ([signal.days.first] + signal.others.map { Optional($0.day) }).compactMap { $0 }.min() ?? today
        var start: DayKey
        var end = today
        switch range {
        case .month:
            start = today.adding(days: -27, calendar: calendar)
        case .phase:
            start = phase?.start ?? firstWeighIn
            if let phaseEnd = phase?.end, phaseEnd > end { end = phaseEnd }
        case .all:
            start = min(firstWeighIn, today.adding(days: -27, calendar: calendar))
        }
        start = min(start, today)
        let last = min(end, today)

        let mornings: [BodyPageWeightDot] = signal.mornings(from: start, through: last).map { reading in
            BodyPageWeightDot(id: "m-\(reading.day.rawValue)", day: reading.day, date: reading.day.date(calendar: calendar),
                              kilograms: reading.kilograms, isTagged: reading.isTagged, isHealth: reading.source == .health)
        }
        let others: [BodyPageWeightDot] = signal.others.filter { $0.day >= start && $0.day <= last }.enumerated().map { index, reading in
            BodyPageWeightDot(id: "o-\(index)-\(reading.day.rawValue)", day: reading.day, date: reading.day.date(calendar: calendar),
                              kilograms: reading.kilograms, isTagged: reading.isTagged, isHealth: reading.source == .health)
        }
        let averages: [BodyPageWeightValue] = signal.averages(from: start, through: last).map { point in
            BodyPageWeightValue(id: "a-\(point.day.rawValue)", date: point.day.date(calendar: calendar), kilograms: point.kilograms)
        }
        let trend: [BodyPageWeightValue] = mornings.compactMap { dot in
            signal.trend(on: dot.day).map { BodyPageWeightValue(id: "t-\(dot.day.rawValue)", date: dot.date, kilograms: $0) }
        }
        var corridor: [BodyPageBand] = []
        if let phase, let startWeight = context.summary.startWeight, let phaseStart = phase.start {
            let first = max(start, phaseStart)
            let through = range == .phase ? end : last
            if first <= through {
                for day in DayKey.range(first, through: through, calendar: calendar) {
                    guard let band = WeightSignal.corridor(startWeight: startWeight, phase: phase, on: day, calendar: calendar) else { continue }
                    corridor.append(BodyPageBand(id: "c-\(day.rawValue)", date: day.date(calendar: calendar),
                                                 low: band.lowerBound, high: band.upperBound))
                }
            }
        }
        var pauses: [BodyPageSpan] = []
        for (index, pause) in context.plan.pauses.enumerated() {
            let from = max(pause.start, start)
            let to = min(pause.end ?? end, end)
            guard from <= to else { continue }
            pauses.append(BodyPageSpan(id: "p-\(index)", start: from.date(calendar: calendar),
                                       end: to.adding(days: 1, calendar: calendar).date(calendar: calendar)))
        }
        var target: Double?
        var review: ClosedRange<Double>?
        var phaseEnd: Date?
        if let phase {
            if phase.targetWeight > 0 { target = phase.targetWeight }
            let bounds = [phase.reviewMin, phase.reviewMax].filter { $0 > 0 }
            if let low = bounds.min(), let high = bounds.max() { review = low...high }
            if let endDay = phase.end, endDay >= start, endDay <= end { phaseEnd = endDay.date(calendar: calendar) }
        }
        var values: [Double] = mornings.map(\.kilograms) + others.map(\.kilograms) + averages.map(\.kilograms)
        values += corridor.flatMap { [$0.low, $0.high] }
        if let target { values.append(target) }
        if let review { values += [review.lowerBound, review.upperBound] }
        let fallback = context.bodyWeight?.kilograms ?? NinaSettings.fallbackWeightKg
        let low = ((values.min() ?? fallback) - 0.5).rounded(.down)
        let high = max(((values.max() ?? fallback) + 0.5).rounded(.up), low + 1)
        return BodyPageWeightChart(
            range: range, start: start.date(calendar: calendar), end: end.adding(days: 1, calendar: calendar).date(calendar: calendar),
            mornings: mornings, others: others, averages: averages, trend: trend, corridor: corridor, pauses: pauses, target: target,
            review: review, phaseEnd: phaseEnd, yDomain: low...high)
    }

    // MARK: Tape

    /// The tiles: Waist (the narrow waist when the routine uses it), Chest, Arm, Thigh, Hip, plus
    /// Neck when the routine measures it; the left side when that's the chosen side.
    static func tileSites(routine: CoachPlan.Routine) -> [BodySite] {
        let measured = Set((routine.weeklySites + routine.fullSites).map(\.base))
        let waist: BodySite = measured.contains(.waistNarrow) && !measured.contains(.waist) ? .waistNarrow : .waist
        var sites: [BodySite] = [waist, .chest, .arm, .thigh, .hip]
        if measured.contains(.neck) { sites.append(.neck) }
        if routine.side == .left { sites = sites.map { $0.left ?? $0 } }
        return sites
    }

    /// A tile: the latest reading (standard or not) and the standard readings' change since `since`.
    static func tile(_ site: BodySite, records: [BodyTapeRecord], since: DayKey?) -> BodyPageTile {
        let latest = GirthTrend.readings(site, in: records, includeNonStandard: true).last
        let change = GirthTrend.change(site, in: records, since: since)
        return BodyPageTile(site: site, value: latest?.value, day: latest?.day, change: change)
    }

    // MARK: Composition

    struct CompositionResult {
        let page: BodyPageComposition
        let trackingPoints: [BodyCompositionPoint]
    }

    static func composition(_ context: CoachContext, heightCm: Double) -> CompositionResult {
        let calendar = context.calendar
        let today = context.today
        let sex = context.settings.body.sex
        let formula = NavyBodyFat.Formula(sex: sex)
        let tape = context.tapeRecords
        let navy = NavyBodyFat.series(formula: formula, heightCm: heightCm, records: tape, calendar: calendar)
            .map { BodyFatReading(navy: $0) }
        let groups = BodyFatSeries.group(context.bodyFatReadings + navy)
        let tracking = BodyFatSeries.tracking(groups, method: context.plan.routine.bodyFatMethod)
        let typed = context.latestWeight?.kilograms
        let trackingPoints = tracking.map { context.signal.compositionPoints($0.readings, today: today, typedWeight: typed) } ?? []

        var points: [BodyPageFatPoint] = []
        var series: [BodyPageFatSeries] = []
        for group in groups {
            guard let latest = group.latest else { continue }
            let band = group.errorBand
            for (index, reading) in group.readings.enumerated() {
                points.append(BodyPageFatPoint(
                    id: "\(group.id)-\(index)", series: group.title, date: reading.day.date(calendar: calendar),
                    bodyFat: reading.bodyFat, low: band.map { reading.bodyFat - $0 }, high: band.map { reading.bodyFat + $0 }))
            }
            series.append(BodyPageFatSeries(id: group.id, title: group.title, latest: latest.bodyFat, latestDay: latest.day,
                                            band: group.method.errorText, count: group.count, isTracking: group.id == tracking?.id))
        }

        let latestPoint = trackingPoints.last
        var change: CompositionChange?
        if trackingPoints.count >= 2 {
            change = CompositionChange(from: trackingPoints[trackingPoints.count - 2], to: trackingPoints[trackingPoints.count - 1])
        }

        var waistToHeight: Double?
        var waistToHip: Double?
        let withWaist = tape.filter { BodyComposition.waist(in: $0.values, sex: sex) != nil }
            .sorted { ($0.day, $0.time ?? .distantPast) < ($1.day, $1.time ?? .distantPast) }
        if let record = withWaist.last, let waist = BodyComposition.waist(in: record.values, sex: sex) {
            if heightCm > 0 { waistToHeight = BodyComposition.waistToHeight(waistCm: waist, heightCm: heightCm) }
            if let hip = record.values[.hip] { waistToHip = BodyComposition.waistToHip(waistCm: waist, hipCm: hip) }
        }
        var ffmi: Double?
        var normalised: Double?
        if let latestPoint, heightCm > 0 {
            ffmi = latestPoint.composition.ffmi(heightCm: heightCm)
            normalised = latestPoint.composition.normalisedFFMI(heightCm: heightCm)
        }

        var tapeNote: String?
        if !tape.isEmpty {
            switch NavyBodyFat.estimate(formula: formula, heightCm: heightCm, records: tape, calendar: calendar) {
            case .needsHeight:
                tapeNote = "Height " + NavyBodyFat.heightNeeded + " – add it in Goals."
            case .needsFormula:
                tapeNote = "Choose female or male in Goals to see the tape estimate."
            case .needsSites(let sites):
                let names = sites.map { $0.title.lowercased() }.joined(separator: " and ")
                tapeNote = "Measure your \(names) for the tape estimate."
            case .implausible, .available:
                tapeNote = nil
            }
        }

        let page = BodyPageComposition(
            points: points, series: series, latest: latestPoint?.composition, latestDay: latestPoint?.day,
            latestTitle: tracking?.title, change: change, waistToHeight: waistToHeight, waistToHip: waistToHip,
            ffmi: ffmi, normalisedFFMI: normalised, nextFull: context.isSetUp ? context.nextFull : nil, tapeNote: tapeNote)
        return CompositionResult(page: page, trackingPoints: trackingPoints)
    }

    // MARK: Goal

    static func goal(_ context: CoachContext, points: [BodyCompositionPoint], seriesTitle: String?) -> BodyPageGoal? {
        let plan = context.plan
        guard plan.isSetUp, plan.longTerm.isSet else { return nil }
        let card = BodyGoalCard(goal: plan.longTerm, points: points, goalSetOn: nil, phaseGoal: context.activePhase?.goal)
        let now = context.summary.average.value ?? context.bodyWeight?.kilograms
        let weightRow = now.map {
            BodyGoalWeightRow(now: $0, phaseTarget: context.activePhase?.targetWeight ?? 0, longTermTarget: plan.longTerm.weightKg)
        }
        var outlook: String?
        if let leanToGo = card.gap?.leanToGo {
            outlook = LeanGainOutlook(leanToGo: leanToGo, today: context.today, goalDate: plan.longTerm.date,
                                      calendar: context.calendar)?.text
        }
        return BodyPageGoal(card: card, goal: plan.longTerm, seriesTitle: seriesTitle, weightRow: weightRow,
                            honestLine: card.gap?.honestLine, outlook: outlook)
    }

    // MARK: Phases

    static func phaseState(_ phase: CoachPlan.Phase, active: CoachPlan.Phase?) -> BodyPagePhaseState {
        if phase.id == active?.id { return .active }
        if phase.status == .done || phase.isStarted { return .done }
        return .planned
    }

    static func timeline(_ context: CoachContext) -> BodyPageTimeline? {
        let plan = context.plan
        guard plan.isSetUp, !plan.phases.isEmpty else { return nil }
        let calendar = context.calendar
        let today = context.today
        let active = context.activePhase
        let dated = plan.phases.filter { $0.start != nil }.sorted { ($0.start ?? today) < ($1.start ?? today) }
        var spans: [(phase: CoachPlan.Phase, start: DayKey, end: DayKey)] = []
        for (index, phase) in dated.enumerated() {
            guard let start = phase.start else { continue }
            var end: DayKey
            if let own = phase.end, own >= start {
                end = own
            } else if index + 1 < dated.count, let next = dated[index + 1].start, next > start {
                end = next.adding(days: -1, calendar: calendar)
            } else {
                end = max(today, start.adding(days: 83, calendar: calendar))
            }
            spans.append((phase: phase, start: start, end: end))
        }
        let undated = plan.phases.filter { $0.start == nil }
        let rows: [BodyPagePhaseRow] = (dated + undated).map { phase in
            BodyPagePhaseRow(id: phase.id, name: BodyPageText.name(of: phase), goal: phase.goal,
                             state: phaseState(phase, active: active), dates: phaseDates(phase, today: today) ?? "No date yet",
                             detail: rateText(phase))
        }
        guard let first = spans.map(\.start).min(), var last = spans.map(\.end).max() else {
            return BodyPageTimeline(segments: [], rows: rows, today: nil, review: nil, goalFlag: nil, startText: "", endText: "")
        }
        if let goalDate = plan.longTerm.date, goalDate > last, first.days(to: goalDate, calendar: calendar) <= 3 * 365 {
            last = goalDate
        }
        let total = Double(first.days(to: last, calendar: calendar) + 1)
        func fraction(_ day: DayKey) -> Double {
            min(1, max(0, Double(first.days(to: day, calendar: calendar)) / total))
        }
        let segments: [BodyPageSegment] = spans.map { span in
            BodyPageSegment(id: span.phase.id, name: BodyPageText.name(of: span.phase), goal: span.phase.goal,
                            state: phaseState(span.phase, active: active), x0: fraction(span.start),
                            x1: min(1, Double(first.days(to: span.end, calendar: calendar) + 1) / total),
                            dates: phaseDates(span.phase, today: today) ?? "")
        }
        var todayMark: Double?
        if today >= first, today <= last { todayMark = (Double(first.days(to: today, calendar: calendar)) + 0.5) / total }
        var review: ClosedRange<Double>?
        if let active, let average = context.summary.average.value, context.summary.checkpointReached == nil,
           let dates = WeightSignal.checkpointDates(average: average, on: today, phase: active, calendar: calendar),
           dates.lowerBound <= last {
            review = fraction(dates.lowerBound)...fraction(dates.upperBound)
        }
        var goalFlag: Double?
        if let goalDate = plan.longTerm.date, goalDate >= first, goalDate <= last { goalFlag = fraction(goalDate) }
        return BodyPageTimeline(segments: segments, rows: rows, today: todayMark, review: review, goalFlag: goalFlag,
                                startText: BodyPageText.day(first, approx: false, today: today), endText: BodyPageText.day(last, approx: false, today: today))
    }

    // MARK: Check-ins and checks

    /// The saved check-ins, newest first (`snapshots` oldest first, as the store returns them).
    static func checkIns(_ snapshots: [CheckInSnapshot], calendar: Calendar) -> [BodyPageCheckIn] {
        snapshots.reversed().map { snapshot in
            let monday = snapshot.day.startOfWeek(calendar: calendar)
            var delta: String?
            if let kcal = snapshot.deltaKcal, kcal != 0 { delta = BodyPageText.signed(kcal, decimals: 0) + " kcal" }
            let decision: String
            switch snapshot.decision {
            case .applied?: decision = "Applied"
            case .edited?: decision = "Applied (changed)"
            case .kept?: decision = "Kept"
            case nil: decision = delta == nil ? "No change" : "Open"
            }
            return BodyPageCheckIn(id: snapshot.key(calendar: calendar), week: monday,
                                   title: "Week of " + Fmt.shortDay(monday, calendar: calendar),
                                   verdict: snapshot.verdict?.title ?? "Saved", tone: tone(of: snapshot.verdict), delta: delta,
                                   decision: decision)
        }
    }

    /// "Creatine 6 of 7 days · Fish oil 4 days" over the last 7 days. A check still open today
    /// doesn't count as missed yet; paused days are left out; optional checks only count the ticks.
    static func checkLine(_ context: CoachContext, store: NinaStore) -> String? {
        let plan = context.plan
        guard plan.isSetUp, !plan.checks.isEmpty else { return nil }
        let calendar = context.calendar
        let today = context.today
        let start = today.adding(days: -6, calendar: calendar)
        let done = store.doneChecks(from: start, through: today)
        let days = DayKey.range(start, through: today, calendar: calendar).filter { !plan.isPaused(on: $0) }
        var parts: [String] = []
        for check in plan.checks {
            var due = 0
            var ticked = 0
            for day in days {
                let isDone = done[day]?.contains(check.id) ?? false
                let typeID = context.settings.dayType(for: day, calendar: calendar)?.id
                let isDue = check.isDue(on: day, dayTypeID: typeID, calendar: calendar)
                if day == today, !isDone { continue }
                if isDue || isDone { due += 1 }
                if isDone { ticked += 1 }
            }
            let name = check.name.isEmpty ? "Check" : check.name
            if check.isOptional {
                if ticked > 0 { parts.append("\(name) \(ticked) \(ticked == 1 ? "day" : "days")") }
            } else if due > 0 {
                parts.append("\(name) \(ticked) of \(due) \(due == 1 ? "day" : "days")")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Text

/// Number and date pieces for the body page.
enum BodyPageText {
    /// "+0.15", "−0.30" (a real minus), "0" for zero.
    static func signed(_ value: Double, decimals: Int) -> String {
        let text = abs(value).formatted(.number.precision(.fractionLength(decimals)))
        let zero = 0.0.formatted(.number.precision(.fractionLength(decimals)))
        if text == zero { return zero }
        return (value < 0 ? "−" : "+") + text
    }

    /// "+0.15 to +0.25", "−0.30 to −0.50", "±0.10".
    static func range(_ range: ClosedRange<Double>) -> String {
        let low = range.lowerBound, high = range.upperBound
        if abs(low + high) < 1e-9 { return "±" + abs(high).formatted(.number.precision(.fractionLength(2))) }
        if high <= 0 { return signed(high, decimals: 2) + " to " + signed(low, decimals: 2) }
        return signed(low, decimals: 2) + " to " + signed(high, decimals: 2)
    }

    /// "7 Jan", "~26 May", with the year when it is not this year: "~26 May 2031".
    static func day(_ day: DayKey, approx: Bool, today: DayKey) -> String {
        let text = (approx ? "~" : "") + Fmt.shortDay(day)
        return day.year == today.year ? text : "\(text) \(day.year)"
    }

    /// The phase's name, else the default name for its goal.
    static func name(of phase: CoachPlan.Phase) -> String {
        phase.name.isEmpty ? CoachPlan.Phase.defaultName(for: phase.goal) : phase.name
    }

    /// "84.0 cm".
    static func centimeters(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " cm"
    }

    /// "20.1 %".
    static func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " %"
    }
}
