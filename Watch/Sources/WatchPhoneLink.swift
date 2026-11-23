import Foundation
import SwiftData
import WatchConnectivity
import BinisoftKit
import NinaCore

extension Notification.Name {
    /// A newer message from the iPhone was taken (`WatchPhoneLink.receive`): the coach reloads.
    static let ninaWatchPhoneMessage = Notification.Name("nina.watch.phoneMessage")
}

/// iPhone → Apple Watch, the watch side: the iPhone sends today's snapshot device to device
/// (`PhoneWatchLink` there, rules in NinaCore `WatchSnapshotRelay`), and the watch writes it for
/// its face unless it has fresher numbers of its own. Also while the app isn't running: the
/// system wakes it in the background for the face's transfers (`finishPendingTransfers`). Nothing
/// goes through iCloud. With the snapshot comes what only the iPhone knows from Apple Health (the
/// coach part: this morning's Health weigh-in, its status line, today's active energy): it is
/// kept in this watch's UserDefaults only – never in its SwiftData store, which syncs.
@MainActor
enum WatchPhoneLink {
    private static let delegate = WatchPhoneSessionDelegate()
    private static let markKey = "nina.watchlink.phone"
    private static let coachKey = "nina.watchlink.phoneCoach"
    private static var isActivated = false

    /// Called at launch.
    static func activate() {
        guard !isActivated, WCSession.isSupported() else { return }
        isActivated = true
        let session = WCSession.default
        session.delegate = delegate
        session.activate()
    }

    /// The last snapshot taken from the iPhone (device-only).
    static var lastPhoneMark: WatchSnapshotRelay.PhoneMark? {
        get {
            guard let data = UserDefaults.standard.data(forKey: markKey) else { return nil }
            return try? JSONDecoder().decode(WatchSnapshotRelay.PhoneMark.self, from: data)
        }
        set {
            let data = newValue.flatMap { try? JSONEncoder().encode($0) }
            UserDefaults.standard.set(data, forKey: markKey)
        }
    }

    /// The last coach part from the iPhone (device-only: it holds values read from Apple Health).
    static var phoneCoach: WatchSnapshotRelay.PhoneCoach? {
        get { UserDefaults.standard.data(forKey: coachKey).flatMap(WatchSnapshotRelay.PhoneCoach.init(encoded:)) }
        set { UserDefaults.standard.set(newValue?.encoded(), forKey: coachKey) }
    }

    /// Today's active energy from the iPhone's Apple Health (kcal, before "Add to my budget"), as
    /// the iPhone last reported it; 0 once that is from another calendar day. Kept where every
    /// snapshot this watch writes reads it (`WidgetBridge.activityBonus`, this watch only), so the
    /// face has the same budget as the iPhone's after a save here too.
    static func activeEnergy() -> Double {
        WidgetBridge.activityBonus
    }

    /// Keeps the iPhone's reading of active energy for the snapshots (`receive`).
    private static func keepActiveEnergy(of coach: WatchSnapshotRelay.PhoneCoach?) {
        guard let coach, let day = DayKey(coach.activeEnergyDay) else { return }
        WidgetBridge.setActivityBonus(WatchSnapshotRelay.activeEnergy(coach, on: coach.activeEnergyDay), day: day)
    }

    /// A message from the iPhone: its coach part is kept, and its snapshot is written for the face
    /// unless this watch has fresher numbers (a change made here the iPhone hasn't seen yet) – then
    /// the watch's own snapshot is written again when the iPhone's activity bonus changed. Messages
    /// older than one already taken are ignored.
    static func receive(_ payload: WatchSnapshotRelay.Payload) {
        guard WatchSnapshotRelay.isNewer(payload, than: lastPhoneMark) else { return }
        lastPhoneMark = payload.mark
        let previous = phoneCoach
        let kept = WatchSnapshotRelay.keptCoach(payload, previous: previous)
        let bonusBefore = activeEnergy()
        if kept != previous {
            phoneCoach = kept
            keepActiveEnergy(of: kept)
        }
        let store = NinaStore(context: Persistence.shared.container.mainContext)
        let today = store.settings.today()
        let freshness = store.watchLinkFreshness(on: today)
        if WatchSnapshotRelay.acceptsPhone(payload, watchFreshness: freshness, watchToday: today.rawValue) {
            WidgetBridge.publish(payload.snapshot)
        } else if activeEnergy() != bonusBefore,
                  WatchSnapshotRelay.acceptsOwn(day: today.rawValue, freshness: freshness, phone: payload.mark) {
            // With the iPhone's new activity bonus (`todaySnapshot` reads it).
            WidgetBridge.publish(store.todaySnapshot())
        }
        NotificationCenter.default.post(name: .ninaWatchPhoneMessage, object: nil)
    }

    /// The background task for WatchConnectivity: waits until what the iPhone sent has arrived and
    /// been written (a few seconds at most); then the system may suspend the app again.
    static func finishPendingTransfers() async {
        activate()
        var waited = 0
        while WCSession.default.hasContentPending, waited < 20 {
            try? await Task.sleep(for: .milliseconds(250))
            waited += 1
        }
        // The last message hops to the main actor before it is written.
        try? await Task.sleep(for: .milliseconds(250))
    }
}

/// WatchConnectivity calls this on its own queue; the payload is decoded here and handed to the
/// main actor.
private final class WatchPhoneSessionDelegate: NSObject, WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            AppLog.warning("Phone session not activated: \(error.localizedDescription)", category: "watch")
        }
        guard activationState == .activated else { return }
        // The newest snapshot may have come while the app wasn't running.
        receive(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        receive(userInfo)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }

    private func receive(_ message: [String: Any]) {
        guard let payload = WatchSnapshotRelay.payload(from: message) else { return }
        Task { @MainActor in WatchPhoneLink.receive(payload) }
    }
}
