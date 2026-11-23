import Foundation
import SwiftData
import WatchConnectivity
import BinisoftKit
import NinaCore

/// iPhone → Apple Watch, the watch side: the iPhone sends today's snapshot device to device
/// (`PhoneWatchLink` there, rules in NinaCore `WatchSnapshotRelay`), and the watch writes it for
/// its face unless it has fresher numbers of its own. Also while the app isn't running: the
/// system wakes it in the background for the face's transfers (`finishPendingTransfers`). Nothing
/// goes through iCloud, and nothing from Apple Health is in it.
@MainActor
enum WatchPhoneLink {
    private static let delegate = WatchPhoneSessionDelegate()
    private static let markKey = "nina.watchlink.phone"
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

    /// A snapshot from the iPhone: written for the face unless this watch has fresher numbers
    /// (a change made here the iPhone hasn't seen yet) or it is older than one already taken.
    static func receive(_ payload: WatchSnapshotRelay.Payload) {
        guard WatchSnapshotRelay.isNewer(payload, than: lastPhoneMark) else { return }
        lastPhoneMark = payload.mark
        let store = NinaStore(context: Persistence.shared.container.mainContext)
        let today = store.settings.today()
        let freshness = store.watchLinkFreshness(on: today)
        guard WatchSnapshotRelay.acceptsPhone(payload, watchFreshness: freshness, watchToday: today.rawValue) else { return }
        WidgetBridge.publish(payload.snapshot)
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
