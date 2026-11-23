import Foundation

/// When the progress photos lock again on the Mac. The lock shouldn't get in the way there: a
/// quick look at another app, or Nina hidden for a moment (⌘H), doesn't ask again – only five
/// minutes away from Nina do. Leaving the Mac locks them at once: the screen locks, the screen
/// saver starts, the displays or the Mac go to sleep, or another user takes over the screen.
/// (iPhone and iPad lock as soon as Nina stops being active, early enough for the app switcher's
/// picture – that needs no rule.)
///
/// The app reports what happened (`handle(_:at:)`) and does what the answer says: lock now, start
/// or restart the timer, or stop it. Coming back checks the time too, so a timer that ran late
/// (App Nap holds back timers of apps in the background) still locks before the photos show.
public struct NinaPhotoLockGrace: Equatable, Sendable {
    /// How long Nina may stay in the background on the Mac before the photos lock again.
    public static let macBackground: TimeInterval = 5 * 60

    public enum Event: Equatable, Sendable {
        /// Nina went behind another app, or was hidden.
        case background
        /// Nina is the active app again.
        case foreground
        /// The person left the Mac: the screen locked, the screen saver started, the displays or
        /// the Mac went to sleep, or another user took over the screen.
        case away
        /// The timer started by `lockAfter` went off.
        case timerFired
    }

    public enum Action: Equatable, Sendable {
        /// Nothing to do.
        case nothing
        /// Lock the photos now (and stop the timer).
        case lock
        /// Start the timer (replacing a running one): lock after this many seconds.
        case lockAfter(TimeInterval)
        /// Stop the timer; the photos stay as they are.
        case cancelTimer
    }

    /// How long Nina may stay away before the photos lock.
    public let grace: TimeInterval
    /// When Nina went to the background; nil while it is in front.
    public private(set) var leftAt: Date?

    public init(grace: TimeInterval = NinaPhotoLockGrace.macBackground) {
        self.grace = max(0, grace)
    }

    /// What the app does after `event`.
    public mutating func handle(_ event: Event, at now: Date) -> Action {
        // The clock was set back since Nina left: the grace counts from now.
        if let left = leftAt, now < left { leftAt = now }
        switch event {
        case .background:
            // Hidden right after going behind another app: the first time counts.
            if leftAt == nil { leftAt = now }
            return lockAfterOrNow(at: now)
        case .foreground:
            defer { self.leftAt = nil }
            guard let leftAt else { return .cancelTimer }
            return isDue(since: leftAt, at: now) ? .lock : .cancelTimer
        case .away:
            return .lock
        case .timerFired:
            // Back in front before the timer went off: nothing to lock.
            guard leftAt != nil else { return .nothing }
            return lockAfterOrNow(at: now)
        }
    }

    /// When the photos lock if Nina stays in the background.
    public var lockTime: Date? {
        leftAt?.addingTimeInterval(grace)
    }

    /// `lock` once the grace is over, else the time still left.
    private func lockAfterOrNow(at now: Date) -> Action {
        guard let leftAt else { return .nothing }
        if isDue(since: leftAt, at: now) { return .lock }
        return .lockAfter(grace - now.timeIntervalSince(leftAt))
    }

    private func isDue(since leftAt: Date, at now: Date) -> Bool {
        now.timeIntervalSince(leftAt) >= grace
    }
}
