import Foundation
import SwiftData
import CoreData
import BinisoftKit
import NinaCore
#if os(iOS)
import UIKit
import WatchConnectivity
#endif

/// iPhone → Apple Watch: whenever the widget snapshot changes (a save here, a CloudKit import of
/// what was logged on the Mac or iPad, a new day), today's numbers go to the watch device to
/// device – never through iCloud – so its face is right even while the watch app isn't running.
/// With them goes what only the iPhone knows from Apple Health (the coach part: this morning's
/// Health weigh-in, the status line over typed and Health weigh-ins, today's active energy for the
/// activity bonus), also when only that changed. Rules in NinaCore `WatchSnapshotRelay`; the watch
/// side is `WatchPhoneLink`. The session starts with the first message (`install` at launch only
/// hooks in), and only in the iPhone app itself: never in the widgets, never on the Mac, never in
/// the demo or with a store that isn't saved.
@MainActor
final class PhoneWatchLink {
    static let shared = PhoneWatchLink()

    #if os(iOS)
    private let delegate = PhoneWatchSessionDelegate()
    private var started = false
    private var sendTask: Task<Void, Never>?
    private var frontTask: Task<Void, Never>?
    /// The last snapshot handed over (without its time): the same numbers again aren't resent,
    /// which keeps the watch face's daily transfer budget for real changes.
    private var lastSent: TodaySnapshot?
    /// The last coach part handed over: the same again isn't resent.
    private var lastCoach: WatchSnapshotRelay.PhoneCoach?
    /// Apple Health was read in this run of the app: it came to the front, and the app reads
    /// Health then. A launch in the background (a CloudKit import while the iPhone is locked)
    /// reads nothing, so until then no coach part goes out – the watch keeps the last one.
    private var healthRead = false
    private var observers: [NSObjectProtocol] = []
    #endif

    /// Called once at launch: from then on every snapshot the app writes, and every change of the
    /// coach part, is handed to the watch.
    static func install() {
        #if os(iOS)
        guard WCSession.isSupported(), Bundle.main.bundleURL.pathExtension == "app", !LaunchOptions.current.isDemo else { return }
        WidgetBridge.didWrite = PhoneWatchLink.snapshotWritten
        shared.observe()
        #endif
    }

    /// The app refreshed (after a save, an iCloud import or a new read of Apple Health): hand on
    /// what changed. Nothing off the iPhone, or before `install` hooked in.
    static func refreshed() {
        #if os(iOS)
        guard !shared.observers.isEmpty else { return }
        shared.scheduleSend()
        #endif
    }

    #if os(iOS)
    /// `WidgetBridge` wrote a new snapshot (on the main thread, from any caller).
    nonisolated private static func snapshotWritten(_ snapshot: TodaySnapshot) {
        Task { @MainActor in PhoneWatchLink.shared.scheduleSend() }
    }

    private func observe() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        // A save on this iPhone counts as its newest change, also when it deleted a record for
        // good. A weigh-in or a check-in changes the coach part even when today's numbers stay.
        observers.append(center.addObserver(forName: .ninaDataChanged, object: nil, queue: .main) { _ in
            WatchLinkLocalChange.record()
            MainActor.assumeIsolated { PhoneWatchLink.shared.scheduleSend() }
        })
        // A weigh-in or a plan change from the iPad, the Mac or the watch arriving through iCloud
        // (after the app's own refresh of it).
        observers.append(center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PhoneWatchLink.shared.scheduleSend(milliseconds: 1_200) }
        })
        // In front, the app reads Apple Health again (weigh-ins, active energy).
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PhoneWatchLink.shared.cameToFront() }
        })
    }

    /// Coalesces a burst of saves into one message.
    func scheduleSend(milliseconds: Int = 500) {
        sendTask?.cancel()
        sendTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(milliseconds))
            guard !Task.isCancelled else { return }
            self?.send()
        }
    }

    /// Back in front, the app reads Apple Health again (`AppModel.becameActive`) and refreshes
    /// when something changed: look once that is likely done, and once more for a slow read.
    private func cameToFront() {
        frontTask?.cancel()
        frontTask = Task { @MainActor [weak self] in
            for seconds in [3, 10] {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, let self else { return }
                self.healthRead = true
                self.scheduleSend(milliseconds: 0)
            }
        }
    }

    /// The live Health weigh-ins are in memory (`CoachContext.latestHealthReadings`): Health was
    /// read since launch, or this iPhone doesn't read weight from Health at all. Today's active
    /// energy is kept on the device with its day (`WidgetBridge`), so it never needs a fresh read.
    private var healthIsCurrent: Bool {
        healthRead || !UserDefaults.standard.bool(forKey: HealthService.Option.weight.key)
    }

    /// Today's active energy from Apple Health (kcal, before "Add to my budget") as the iPhone's
    /// own ring adds it to the diary day `today`: the reading this device keeps with its day
    /// (`WidgetBridge`), whether that day is the diary day or the calendar day (they differ
    /// between midnight and a later day start); 0 when it is older.
    private static func activeEnergy(today: DayKey, now: Date, calendar: Calendar) -> Double {
        let onDiaryDay = WidgetBridge.activityBonus(on: today)
        let calendarDay = DayKey(date: now, calendar: calendar)
        guard calendarDay != today else { return onDiaryDay }
        return max(onDiaryDay, WidgetBridge.activityBonus(on: calendarDay))
    }

    private func send() {
        let session = WCSession.default
        guard session.activationState == .activated else {
            start()
            return
        }
        guard session.isPaired, session.isWatchAppInstalled else { return }
        // Never the numbers of the demo or of a store that is lost on quit.
        guard HealthService.savesData(Persistence.shared.mode) else { return }
        let store = NinaStore(context: Persistence.shared.container.mainContext)
        let now = Date()
        let today = store.settings.today(now: now, calendar: store.calendar)
        let activeEnergy = Self.activeEnergy(today: today, now: now, calendar: store.calendar)
        // With the activity bonus exactly as the iPhone's own widget has it: the watch adds the
        // same bonus from the coach part to its ring and to the snapshots it writes itself.
        let snapshot = store.todaySnapshot(now: now)
        let coach = healthIsCurrent
            ? store.watchLinkPhoneCoach(health: CoachContext.latestHealthReadings, activeEnergy: activeEnergy, now: now)
            : nil
        let snapshotChanged = !snapshot.hasSameContent(as: lastSent)
        let coachChanged = coach != nil && coach != lastCoach
        guard snapshotChanged || coachChanged else { return }
        let payload = WatchSnapshotRelay.Payload(snapshot: snapshot, freshness: store.watchLinkFreshness(on: today), sentAt: now,
                                                 coach: coach)
        guard let message = WatchSnapshotRelay.message(payload) else { return }
        if snapshotChanged, session.isComplicationEnabled, session.remainingComplicationUserInfoTransfers > 0 {
            // Wakes the watch so the face updates now (a limited number a day: only for new numbers).
            session.transferCurrentComplicationUserInfo(message)
        } else {
            do {
                try session.updateApplicationContext(message)
            } catch {
                AppLog.warning("Watch snapshot not sent: \(error.localizedDescription)", category: "watch")
                return
            }
        }
        lastSent = snapshot
        if let coach { lastCoach = coach }
    }

    /// Starts the session; the snapshot goes out once it is active.
    private func start() {
        guard !started else { return }
        started = true
        let session = WCSession.default
        session.delegate = delegate
        session.activate()
    }

    /// The session is up (or the watch changed: paired, app installed, a complication added).
    fileprivate func sessionChanged(resend: Bool) {
        if resend {
            lastSent = nil
            lastCoach = nil
        }
        scheduleSend()
    }
    #endif
}

#if os(iOS)
/// WatchConnectivity calls this on its own queue; everything is handed to the main actor.
private final class PhoneWatchSessionDelegate: NSObject, WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            AppLog.warning("Watch session not activated: \(error.localizedDescription)", category: "watch")
        }
        guard activationState == .activated else { return }
        Task { @MainActor in PhoneWatchLink.shared.sessionChanged(resend: false) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Switching to another Apple Watch: start again for the new one.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in PhoneWatchLink.shared.sessionChanged(resend: true) }
    }
}
#endif
