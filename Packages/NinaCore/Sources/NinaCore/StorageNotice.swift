import Foundation
import BinisoftKitCore

/// The banner for storage and sync problems (RootView: at the top on iPhone and iPad, under the Mac
/// sidebar). Red when Nina runs on an empty temporary store, so nothing typed is kept; orange when
/// it doesn't sync: this device only, not signed in to iCloud, iCloud full, or a sync error that
/// has lasted a day (a short offline spell is no reason for a banner). Settings → iCloud & Data
/// keeps the details.
public struct NinaStorageNotice: Equatable, Sendable {
    public enum Level: String, Equatable, Sendable {
        /// Nothing is saved: red.
        case critical
        /// Saved, but not syncing: orange.
        case warning
    }

    public var level: Level
    /// A few words in bold, e.g. "Not syncing".
    public var title: String
    /// One or two plain sentences: what it means and what to do.
    public var message: String

    public init(level: Level, title: String, message: String) {
        self.level = level
        self.title = title
        self.message = message
    }

    /// How long a sync error has to last before it gets a banner.
    public static let lastingError: TimeInterval = 24 * 3600

    /// The banner for this sync state, or nil when all is well (and for the demo).
    /// - Parameter errorSince: when the current sync error was first seen (`NinaSyncErrorClock`).
    public static func current(state: SyncState, errorSince: Date?, now: Date, appName: String) -> NinaStorageNotice? {
        switch state.mode {
        case .demo:
            return nil
        case .memory:
            return NinaStorageNotice(
                level: .critical, title: "Nothing is being saved",
                message: "\(appName) couldn't open your data. Nothing you add now is saved – quit and reopen \(appName). If this stays: Settings → App Log → Copy log."
            )
        case .local:
            return NinaStorageNotice(
                level: .warning, title: "Not syncing",
                message: "Changes stay on this device. Settings → iCloud & Data says why."
            )
        case .iCloud:
            if state.account == .noAccount {
                return NinaStorageNotice(level: .warning, title: "Not syncing",
                                         message: SyncErrorText.describe("no account", appName: appName))
            }
            if state.account == .restricted {
                return NinaStorageNotice(level: .warning, title: "Not syncing",
                                         message: "iCloud is restricted on this device, so \(appName) can't sync.")
            }
            guard let error = state.lastError else { return nil }
            if isStorageFull(error) {
                return NinaStorageNotice(level: .warning, title: "iCloud is full", message: error)
            }
            guard let errorSince, now.timeIntervalSince(errorSince) >= lastingError else { return nil }
            return NinaStorageNotice(level: .warning, title: "Not syncing for a day", message: error)
        }
    }

    /// iCloud storage is full (the friendly sentence of `SyncErrorText`, or CloudKit's own words).
    static func isStorageFull(_ error: String) -> Bool {
        let lowered = error.lowercased()
        return lowered.contains("storage is full") || lowered.contains("quota")
    }
}

/// When the current sync error was first seen, kept on the device (UserDefaults) so a lasting
/// error can be told from a blip – also across launches, before the new launch's first sync
/// reports. A sync that succeeds after it clears it.
public enum NinaSyncErrorClock {
    public static func update(_ since: Date?, state: SyncState, now: Date) -> Date? {
        guard state.mode.isSynced else { return nil }
        var since = since
        if let started = since, let synced = state.lastSync, synced > started { since = nil }
        if state.lastError != nil { return since ?? now }
        return since
    }
}

/// At most one toast per interval (a failing store fails on every save).
public struct NinaToastThrottle: Equatable, Sendable {
    public let interval: TimeInterval
    public private(set) var lastShown: Date?

    public init(interval: TimeInterval = 60) {
        self.interval = interval
    }

    /// True (and remembered) when a toast may show now.
    public mutating func allows(at now: Date) -> Bool {
        if let lastShown, now.timeIntervalSince(lastShown) < interval { return false }
        lastShown = now
        return true
    }
}

/// The short sync line under the Mac sidebar, e.g. "Synced 2 min. ago".
public enum NinaSyncLine {
    /// - Parameter relative: formats the last sync ("2 min. ago"); the app passes the system style.
    public static func text(_ state: SyncState, relative: (Date) -> String) -> String? {
        switch state.mode {
        case .demo: return nil
        case .memory: return "Not saved"
        case .local: return "On this device only"
        case .iCloud:
            if state.account == .noAccount { return "iCloud: not signed in" }
            if state.account == .restricted { return "iCloud: restricted" }
            if state.lastError != nil { return "Not syncing" }
            if state.isSyncing { return "Syncing…" }
            if let lastSync = state.lastSync { return "Synced \(relative(lastSync))" }
            return "iCloud sync on"
        }
    }
}
