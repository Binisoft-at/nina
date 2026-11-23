import Foundation
import NinaCore

// The ⓘ texts of the body page, the body sheets and the photos (an `InfoButton` each, see
// BodyPageInfoViews.swift): a title and one or two plain sentences – what it means and what to do.
// Numbers come from the rules that compute them (NinaCore and the plan's own settings), so the
// texts stay true when a rule or a setting changes. Foundation and NinaCore only.

/// A title and a short explanation for an `InfoButton`.
struct BodyPageInfo: Equatable {
    let title: String
    let text: String
}

// MARK: - Weight

extension BodyPageInfo {
    /// The 7-day average tile.
    static let average = BodyPageInfo(
        title: "7-day average",
        text: "The mean of your morning weights of the last \(WeightSignal.averageDays) days – it needs at least "
            + "\(WeightSignal.averageMinimum). Single days swing by half a kilo or more with water and salt; the average evens that out.")

    /// The rate tile: how the pace is worked out, with the plan's window (`rate`: the summary's
    /// decision rate, `maxDays`: the plan's longest window).
    static func rate(_ rate: WeightSignal.Rate, maxDays: Int, hasPlan: Bool) -> BodyPageInfo {
        var text = "How fast your weight moves, in kg a week: a straight line through your morning weights of the last "
            + "\(BodyPageInfo.span(days: maxDays)). It shows once it spans \(rate.minimumDays) days with "
            + "\(rate.minimumWeighIns) morning weigh-ins"
        text += hasPlan ? ", counted from the phase start or your last calorie change." : "."
        return BodyPageInfo(title: "Rate", text: text)
    }

    /// The weight chart: the corridor when the active phase draws one, else what the marks mean.
    static func chart(hasCorridor: Bool) -> BodyPageInfo {
        if hasCorridor {
            return BodyPageInfo(
                title: "Your corridor",
                text: "The shaded band shows where your 7-day average would be at your phase's pace range, starting from "
                    + "your weight at the phase start. Orange diamonds are weigh-ins with a reason: shown, but left out of your pace.")
        }
        return BodyPageInfo(
            title: "Weight chart",
            text: "Dots are your morning weigh-ins and the line is your 7-day average; faint dots are later weigh-ins that "
                + "don't count. Orange diamonds are weigh-ins with a reason: shown, but left out of your pace.")
    }

    /// The review weight line under the phase header.
    static let reviewWeight = BodyPageInfo(
        title: "Review weight",
        text: "When your 7-day average – never a single weigh-in – reaches this weight, Nina asks for a review: keep going, "
            + "hold your weight or start the next phase. Nothing changes until you choose.")
}

// MARK: - Phase status

extension BodyPageInfo {
    /// What the active phase's status words mean, by the same rules that pick them
    /// (`WeightSignal.statusLine`): `line` nil means the phase has no pace range. `range`: the
    /// phase's range ("+0.15 to +0.25 kg a week").
    static func status(_ line: WeightSignal.StatusLine?, plan: CoachPlan, rate: WeightSignal.Rate, range: String?) -> BodyPageInfo {
        guard let line else {
            return BodyPageInfo(title: "No rate set",
                                text: "This phase has no pace range, so Nina can't judge how fast your weight moves. Open the phase to set one.")
        }
        let confirm = BodyPageInfo.inARow(plan.adjust.confirmChecks)
        switch line.state {
        case .status(let status):
            switch status {
            case .inRange:
                let goal = range.map { " (\($0))" } ?? ""
                return BodyPageInfo(title: status.title,
                                    text: "Your weight moves at the pace this phase asks for\(goal). Keep doing what you're doing.")
            case .slower, .faster:
                return BodyPageInfo(title: status.title,
                                    text: "Your pace is outside this phase's range right now. One week means little: Nina only "
                                        + "suggests a calorie change after \(confirm) outside the range on the same side.")
            case .gathering:
                return BodyPageInfo(title: status.title,
                                    text: "Nina needs \(rate.minimumDays) days with at least \(rate.minimumWeighIns) morning "
                                        + "weigh-ins before it can judge your pace. Weigh in each morning – the days count from "
                                        + "the phase start or your last calorie change.")
            }
        case .offTrack:
            return BodyPageInfo(title: "Off track",
                                text: "Your pace was outside the range at \(confirm) on the same side, and still is. The weekly "
                                    + "check-in can suggest a small calorie change – nothing changes until you tap Apply.")
        case .newTargets:
            return BodyPageInfo(title: "New targets",
                                text: "Your calories changed, so your pace starts counting again from that day. The first look "
                                    + "is the check-in that can judge the new targets.")
        case .paused:
            return BodyPageInfo(title: "Paused",
                                text: "No checks, check-ins or coach reminders, and the paused days stay out of your pace. "
                                    + "Resume Coaching starts again.")
        }
    }

    /// The next phase before it has started ("Planned", "Ready to start").
    static func plannedPhase(isDue: Bool) -> BodyPageInfo {
        if isDue {
            return BodyPageInfo(title: "Ready to start",
                                text: "This phase's start date has come. A card with Start shows on Today – nothing switches by itself until you tap it.")
        }
        return BodyPageInfo(title: "Planned",
                            text: "This phase hasn't started yet. On its start date a card asks you to start it – nothing switches by itself.")
    }

    /// "2 check-ins in a row", "a check-in".
    static func inARow(_ confirmChecks: Int) -> String {
        let count = max(1, confirmChecks)
        return count == 1 ? "a check-in" : "\(count) check-ins in a row"
    }

    /// "3 weeks" for 21 days, "20 days" otherwise.
    static func span(days: Int) -> String {
        guard days >= 7, days % 7 == 0 else { return days == 1 ? "day" : "\(days) days" }
        let weeks = days / 7
        return weeks == 1 ? "week" : "\(weeks) weeks"
    }
}

// MARK: - Goal, tape and composition

extension BodyPageInfo {
    static let bodyGoal = BodyPageInfo(
        title: "Body goal",
        text: "Your long-term goal from My Plan as lean mass, fat mass and body fat, with how far you've come since you set "
            + "it. The numbers follow the body-fat method you track, so measure it the same way each time.")

    /// The tape tiles: `sincePhase` when the changes count from a phase start, `hasHealth` when the
    /// waist tile shows Apple Health's waist too.
    static func tiles(sincePhase: Bool, hasHealth: Bool) -> BodyPageInfo {
        let since = sincePhase ? "the phase start" : "your first reading"
        var text = "Your latest value and its change since \(since), from morning readings before eating. Changes under "
            + "\(BodyPageInfo.centimeters(BodySite.waist.mdc)) (\(BodyPageInfo.centimeters(BodySite.arm.mdc)) for arm and "
            + "neck) read “\(GirthTrend.noClearChange)” – a careful tape varies that much."
        if hasHealth { text += " Pink “Health” values come from Apple Health." }
        return BodyPageInfo(title: "Measurements", text: text)
    }

    static func baseline(sincePhase: Bool) -> BodyPageInfo {
        let text = sincePhase
            ? "Each site's value when this phase started next to your latest, so you see what the phase has changed so far."
            : "Each site's first reading next to your latest, so you see what has changed so far."
        return BodyPageInfo(title: "Baseline", text: text)
    }

    /// A site's 4-week change (`GirthTrend.fourWeekChange`).
    static let fourWeekChange = BodyPageInfo(
        title: "4-week change",
        text: "Where this site is heading: a straight line through your last \(GirthTrend.minReadings)–\(GirthTrend.maxReadings) "
            + "readings, scaled to 4 weeks. It needs \(GirthTrend.minReadings) readings over at least "
            + "\(BodyPageInfo.span(days: GirthTrend.minSpanDays)).")

    static let composition = BodyPageInfo(
        title: "Body fat by method",
        text: "Each method and each device is its own series, drawn with a band for its typical error – "
            + "\(BodyMethod.dexa.errorText) points for a DEXA scan, \(BodyMethod.scale.errorText) for a smart scale. Changes "
            + "smaller than that read “\(CompositionChange.withinErrorText)”, so compare like with like.")

    static let waistToHeight = BodyPageInfo(
        title: "Waist-to-height",
        text: "Your latest waist divided by your height, both in cm – from a morning reading when there is one. Under 0.5 is the usual health guideline.")

    static let ffmi = BodyPageInfo(
        title: "FFMI",
        text: "Fat-free mass index: your lean mass in kg divided by the square of your height in metres – lean mass for "
            + "your size. “Normalised” adjusts it to a height of 1.80 m, so different heights compare.")

    static let phases = BodyPageInfo(
        title: "Phases",
        text: "A phase is a stretch of weeks with one goal – gain, maintain or lose – and a pace range. Nothing switches by "
            + "itself: when a phase's start date comes, a card asks you to start it.")

    static func checkIns(confirmChecks: Int) -> BodyPageInfo {
        BodyPageInfo(
            title: "Weekly check-in",
            text: "Once a week Nina looks at your 7-day average, your pace and how closely you followed the plan. Only when "
                + "your pace is outside the range at \(BodyPageInfo.inARow(confirmChecks)) does it propose a small calorie "
                + "change – and only your tap applies it.")
    }

    /// "1.0 cm".
    static func centimeters(_ value: Double) -> String {
        DisplayNumber.plain(value, decimals: 1) + " cm"
    }
}

// MARK: - Sheets

extension BodyPageInfo {
    /// The weigh-in sheet's reason tags.
    static let unusualReading = BodyPageInfo(
        title: "Unusual readings",
        text: "Nina asks “anything special?” when a weigh-in is more than "
            + "\(DisplayNumber.plain(WeightSignal.unusualShare * 100, decimals: 1)) % away from your trend. Salt, a late "
            + "meal, alcohol or poor sleep often add water overnight – a reason explains the jump.")

    /// The measuring guide (measure sheet).
    static let sameConditions = BodyPageInfo(
        title: "Same conditions every time",
        text: "Food, drink, training and the time of day change your measurements a little – a pump after training adds "
            + "0.5–1 cm to arm, chest and thigh. Measuring the same way each time means the changes you see are real.")

    /// The conditions of a tape or body-fat reading.
    static let conditions = BodyPageInfo(
        title: "Conditions",
        text: "Nina sets Morning and Before eating by itself from the time and what you've logged today. Add an exception "
            + "if one applies: only readings without one count for your trends.")

    /// The 2nd and 3rd readings of a site: `twoReadings` in a full set, else the weekly re-check.
    static func readings(twoReadings: Bool) -> BodyPageInfo {
        let third = "If the two differ by more than \(BodyPageInfo.centimeters(BodyReadings.maxDifference)), a third one "
            + "settles it and the middle one counts."
        if twoReadings {
            return BodyPageInfo(title: "Two readings",
                                text: "A tape reading varies a little each time, so a full set takes two per site and Nina saves their average. " + third)
        }
        return BodyPageInfo(title: "Measure once more",
                            text: "This value moved more than \(BodyPageInfo.centimeters(BodyReadings.recheckChange)) since last "
                                + "time, so Nina asks for a second reading and saves the average. " + third)
    }

    /// The tape estimate of body fat (measure sheet).
    static let tapeEstimate = BodyPageInfo(
        title: "Tape estimate",
        text: "Body fat worked out from your height and tape – waist and neck, for women narrow waist, hip and neck – with "
            + "the US Navy formula. It's never saved and typically \(BodyMethod.navy.errorText) points off, so it's best for following a trend.")

    /// The body-fat methods (assessment sheet).
    static let methods = BodyPageInfo(
        title: "Methods and their error",
        text: "Body fat can't be measured exactly: “\(BodyMethod.scale.errorText)” means a smart scale may be that many "
            + "points off either way. Pick one method, repeat it under the same conditions and watch the change within it.")
}

// MARK: - Photos

extension BodyPageInfo {
    static let comparablePhotos = BodyPageInfo(
        title: "Photos you can compare",
        text: "Same spot and light, same distance with the phone at chest height, same clothes – ideally the morning of a "
            + "full measurement. They're kept in Nina's private iCloud only, not in iCloud Photos.")

    static let compare = BodyPageInfo(
        title: "Compare",
        text: "Pick a pose and two days, then Side by Side, Fade or Slider. The weight and waist below come from the days "
            + "around each photo and are never saved with them.")

    /// When the photo lock locks again on this device (`isMac`: the Mac's grace).
    static func photoLock(isMac: Bool) -> BodyPageInfo {
        if isMac {
            let minutes = Int((NinaPhotoLockGrace.macBackground / 60).rounded())
            return BodyPageInfo(
                title: "Photo lock",
                text: "A quick switch to another app doesn't ask again. After \(minutes) minutes in other apps (or with Nina "
                    + "hidden), or as soon as the screen locks, the photos lock.")
        }
        return BodyPageInfo(
            title: "Photo lock",
            text: "With the lock on, your photos lock again as soon as you leave Nina, so the app switcher shows them "
                + "blurred. Each device has its own switch.")
    }
}
