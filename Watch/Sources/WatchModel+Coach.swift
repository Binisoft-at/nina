import Foundation
import SwiftData
import NinaCore

// The coach on the wrist (F20): what the home screen shows for today with a set-up plan, and
// the writes it makes – day type, daily checks, weigh-ins and the weekly tape – through the
// same store as the phone, each with a short Undo. Logic lives in NinaCore `WatchCoach`; the
// watch reads no Apple Health data, so its weight signal has the weigh-ins typed in Nina.

/// A short Undo after a coach write on the watch.
struct WatchUndo: Identifiable {
    let id = UUID()
    let message: String
    let symbol: String
    let action: @MainActor () -> Void
}

/// Where a tap in the coach part of the home screen goes.
enum WatchCoachRoute: Hashable {
    case dayType
    case weighIn
    case measure([BodySite])
}

/// One load of the coach for a day: the chip, the checks row, the status line and where the
/// Crown screens start. nil without a set-up plan, so the watch then looks as before.
struct WatchCoachData {
    let day: DayKey
    let plan: CoachPlan
    let chip: CoachBoard.Chip?
    /// The watch's part of the checks strip (`WatchCoach.pills`); empty = no row.
    let pills: [CoachBoard.StripItem]
    let status: WatchCoach.Status?
    /// The newest weigh-in typed in Nina ("Last 74.2 kg").
    let latestWeight: Double?
    /// Where the weigh-in Crown starts.
    let startWeight: Double
    /// The 7-day average (else the trend) a new weight is checked against.
    let weightReference: Double?
    /// The tape records, for each site's last reading.
    let tapeRecords: [BodyTapeRecord]

    @MainActor
    static func load(store: NinaStore, day: DayKey, now: Date = Date()) -> WatchCoachData? {
        var settings = store.settings
        let plan = settings.plan
        guard plan.isSetUp else { return nil }
        let calendar = store.calendar
        let today = settings.today(now: now, calendar: calendar)
        let signal = store.weightSignal(settings: settings)
        settings.bodyWeightKg = signal.bodyWeight(on: today)?.kilograms
        let board = store.coachBoard(for: day, settings: settings, signal: signal, now: now)
        let summary = signal.summary(on: today, plan: plan)
        let latest = store.weights().max { $0.time < $1.time }?.kilograms
        return WatchCoachData(
            day: day, plan: plan, chip: board.chip, pills: WatchCoach.pills(board.strip),
            status: WatchCoach.status(summary: summary, plan: plan, checkIns: store.checkIns()),
            latestWeight: latest, startWeight: WatchCoach.startWeight(latest: latest, bodyWeight: settings.bodyWeightKg),
            weightReference: signal.average(on: today).value ?? signal.trend(on: today),
            tapeRecords: store.tapeRecords())
    }
}

extension WatchModel {
    // MARK: Undo

    /// Shows a short Undo on the home screen; it goes after `seconds` or the next coach write.
    func offerUndo(_ message: String, symbol: String, seconds: Double = 8, action: @escaping @MainActor () -> Void) {
        let offer = WatchUndo(message: message, symbol: symbol, action: action)
        undo = offer
        let id = offer.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.undo?.id == id else { return }
            self.undo = nil
        }
    }

    func performUndo() {
        guard let offer = undo else { return }
        undo = nil
        offer.action()
        WKHaptics.click()
    }

    // MARK: Coach writes

    /// Picks a day's type by hand (nil = back to the schedule), like the phone's chip menu.
    func setDayType(_ typeID: String?, on day: DayKey) {
        let store = self.store
        let plan = settings.plan
        let change = store.setDayType(day: day, typeID: typeID)
        WKHaptics.success()
        guard !change.isEmpty else { return }
        var message = "Back to the schedule"
        if let typeID, let type = plan.dayType(id: typeID) {
            let emoji = type.emoji.isEmpty ? CoachPlan.DayType.suggestedEmoji(for: type.name) : type.emoji
            message = [emoji, type.name].filter { !$0.isEmpty }.joined(separator: " ")
        }
        offerUndo(message, symbol: "calendar") { [weak self] in
            self?.store.undo(change)
        }
    }

    /// A tap on a check pill: open or skipped → done, done → open again.
    func toggleCheck(_ checkID: String, on day: DayKey) {
        let store = self.store
        let name = settings.plan.check(id: checkID)?.name ?? "Check"
        let wasDone = store.checkStates(on: day)[checkID] == .done
        let change = store.setCheck(day: day, checkID: checkID, state: wasDone ? nil : .done)
        if wasDone { WKHaptics.click() } else { WKHaptics.success() }
        offerUndo(wasDone ? "\(name) open again" : "\(name) done", symbol: wasDone ? "circle" : "checkmark.circle.fill") { [weak self] in
            self?.store.undo(change)
        }
    }

    /// A weigh-in from the Crown, now and on today's diary day (the weight signal decides whether
    /// it is the morning weight, as for one typed on the phone).
    func logWeight(_ kilograms: Double, time: Date = Date()) {
        let store = self.store
        let entry = store.addWeight(kilograms, day: settings.today(now: time, calendar: store.calendar), time: time)
        WKHaptics.success()
        offerUndo("Weight \(Fmt.kilograms(kilograms)) saved", symbol: "scalemass.fill") { [weak self] in
            _ = self?.store.trash([entry])
        }
    }

    /// Saves a watch tape session: the first site adds a tape record with the automatic
    /// conditions (morning and fasted before the cutoff with nothing eaten logged, else later),
    /// the next sites update it. Undo moves the session's record to the trash.
    @discardableResult
    func saveTape(_ values: BodyValues, into record: BodyMeasurement?, message: String, time: Date) -> BodyMeasurement {
        let store = self.store
        let saved: BodyMeasurement
        if let record {
            var draft = record.draft
            draft.values = values
            _ = store.update(record, to: draft)
            saved = record
        } else {
            let calendar = store.calendar
            let day = settings.today(now: time, calendar: calendar)
            let automatic = BodyProtocol.automatic(at: time, cutoffMinutes: settings.plan.routine.morningCutoffMinutes,
                                                   hasEaten: store.watchHasEaten(on: day, before: time), calendar: calendar)
            let draft = BodyMeasurementDraft(day: day, time: time, kind: .tape, values: values,
                                             conditions: BodyProtocol.encode(automatic))
            saved = store.addMeasurement(draft)
        }
        WKHaptics.success()
        offerUndo(message, symbol: "ruler.fill") { [weak self] in
            _ = self?.store.trash([saved])
        }
        return saved
    }
}

extension NinaStore {
    /// Something eaten is logged on `day` at or before `time` (a tape reading then isn't fasted),
    /// as the phone's measure sheet checks it.
    func watchHasEaten(on day: DayKey, before time: Date) -> Bool {
        entries(on: day).contains { $0.entryStatus == .eaten && $0.time <= time }
    }
}
