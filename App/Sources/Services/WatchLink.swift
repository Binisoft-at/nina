import Foundation
import SwiftData
import BinisoftKit
import NinaCore
#if os(iOS)
import WatchConnectivity
#endif

/// iPhone → Apple Watch: whenever the widget snapshot changes (a save here, a CloudKit import of
/// what was logged on the Mac or iPad, a new day), today's numbers go to the watch device to
/// device – never through iCloud – so its face is right even while the watch app isn't running.
/// Rules in NinaCore `WatchSnapshotRelay`; the watch side is `WatchPhoneLink`. The session starts
/// with the first snapshot (`install` at launch only hooks into `WidgetBridge`), and only in the
/// iPhone app itself: never in the widgets, never on the Mac.
@MainActor
final class PhoneWatchLink {
    static let shared = PhoneWatchLink()

    #if os(iOS)
    private let delegate = PhoneWatchSessionDelegate()
    private var started = false
    private var sendTask: Task<Void, Never>?
    /// The last snapshot handed over (without its time): the same numbers again aren't resent,
    /// which keeps the watch face's daily transfer budget for real changes.
    private var lastSent: TodaySnapshot?
    private var observer: NSObjectProtocol?
    #endif

    /// Called once at launch: from then on every snapshot the app writes is handed to the watch.
    static func install() {
        #if os(iOS)
        guard WCSession.isSupported(), Bundle.main.bundleURL.pathExtension == "app" else { return }
        WidgetBridge.didWrite = PhoneWatchLink.snapshotWritten
        shared.observeLocalSaves()
        #endif
    }

    #if os(iOS)
    /// `WidgetBridge` wrote a new snapshot (on the main thread, from any caller).
    nonisolated private static func snapshotWritten(_ snapshot: TodaySnapshot) {
        Task { @MainActor in PhoneWatchLink.shared.scheduleSend() }
    }

    /// A save on this iPhone counts as its newest change, also when it deleted a record for good.
    private func observeLocalSaves() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .ninaDataChanged, object: nil, queue: .main) { _ in
            WatchLinkLocalChange.record()
        }
    }

    /// Coalesces a burst of saves into one message.
    func scheduleSend() {
        sendTask?.cancel()
        sendTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.send()
        }
    }

    private func send() {
        let session = WCSession.default
        guard session.activationState == .activated else {
            start()
            return
        }
        guard session.isPaired, session.isWatchAppInstalled else { return }
        let store = NinaStore(context: Persistence.shared.container.mainContext)
        let today = store.settings.today()
        // Without the Apple Health activity bonus: the watch's own ring leaves it out too.
        let snapshot = store.todaySnapshot(activityBonus: 0)
        guard !snapshot.hasSameContent(as: lastSent) else { return }
        let payload = WatchSnapshotRelay.Payload(snapshot: snapshot, freshness: store.watchLinkFreshness(on: today))
        guard let message = WatchSnapshotRelay.message(payload) else { return }
        if session.isComplicationEnabled, session.remainingComplicationUserInfoTransfers > 0 {
            // Wakes the watch so the face updates now (a limited number a day).
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
        if resend { lastSent = nil }
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
