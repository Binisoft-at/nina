import Foundation
import Testing
import BinisoftKitCore
@testable import NinaCore

/// The storage and sync banner (DS-5), the error clock behind "for a day", the save-failure toast
/// throttle and the Mac sidebar's sync line. Made-up dates.
@Suite("Storage notice")
struct StorageNoticeTests {
    static let now = Date(timeIntervalSince1970: 1_900_000_000)
    static let cloud = StorageMode.iCloud(container: "iCloud.example.test")

    @Test func memoryIsRedAndSaysNothingIsSaved() throws {
        let notice = try #require(NinaStorageNotice.current(state: SyncState(mode: .memory(reason: "disk")), errorSince: nil,
                                                            now: Self.now, appName: "Nina"))
        #expect(notice.level == .critical)
        #expect(notice.message.contains("Nothing you add now is saved"))
        #expect(notice.message.contains("Settings → App Log → Copy log"))
    }

    @Test func localIsOrange() throws {
        let notice = try #require(NinaStorageNotice.current(state: SyncState(mode: .local(reason: "store")), errorSince: nil,
                                                            now: Self.now, appName: "Nina"))
        #expect(notice.level == .warning)
        #expect(notice.message.contains("stay on this device"))
    }

    @Test func demoAndHealthySyncShowNothing() {
        #expect(NinaStorageNotice.current(state: SyncState(mode: .demo), errorSince: nil, now: Self.now, appName: "Nina") == nil)
        let fine = SyncState(mode: Self.cloud, account: .available, lastSync: Self.now.addingTimeInterval(-60))
        #expect(NinaStorageNotice.current(state: fine, errorSince: nil, now: Self.now, appName: "Nina") == nil)
        // Still checking the account: no banner yet.
        #expect(NinaStorageNotice.current(state: SyncState(mode: Self.cloud), errorSince: nil, now: Self.now, appName: "Nina") == nil)
    }

    @Test func noAccountAndRestrictedAreOrange() throws {
        let signedOut = try #require(NinaStorageNotice.current(state: SyncState(mode: Self.cloud, account: .noAccount),
                                                               errorSince: nil, now: Self.now, appName: "Nina"))
        #expect(signedOut.level == .warning)
        #expect(signedOut.message.contains("Sign in to iCloud"))
        let restricted = try #require(NinaStorageNotice.current(state: SyncState(mode: Self.cloud, account: .restricted),
                                                                errorSince: nil, now: Self.now, appName: "Nina"))
        #expect(restricted.message.contains("restricted"))
    }

    @Test func fullICloudShowsAtOnce() throws {
        let full = SyncErrorText.describe("CKError: quota exceeded", appName: "Nina")
        let state = SyncState(mode: Self.cloud, account: .available, lastError: full)
        let notice = try #require(NinaStorageNotice.current(state: state, errorSince: Self.now, now: Self.now, appName: "Nina"))
        #expect(notice.title == "iCloud is full")
        #expect(notice.message == full)
    }

    @Test func otherErrorsWaitADay() throws {
        let state = SyncState(mode: Self.cloud, account: .available, lastError: "No network – Nina syncs when you're back online.")
        let fresh = NinaStorageNotice.current(state: state, errorSince: Self.now.addingTimeInterval(-3600), now: Self.now, appName: "Nina")
        #expect(fresh == nil)
        #expect(NinaStorageNotice.current(state: state, errorSince: nil, now: Self.now, appName: "Nina") == nil)
        let lasting = try #require(NinaStorageNotice.current(state: state, errorSince: Self.now.addingTimeInterval(-25 * 3600),
                                                             now: Self.now, appName: "Nina"))
        #expect(lasting.level == .warning)
        #expect(lasting.message == state.lastError)
    }

    @Test func errorClockStartsKeepsAndClears() {
        let start = Self.now.addingTimeInterval(-7200)
        var state = SyncState(mode: Self.cloud, account: .available, lastError: "Not syncing")
        // A new error starts the clock.
        let started = NinaSyncErrorClock.update(nil, state: state, now: start)
        #expect(started == start)
        // It keeps running while the error lasts.
        let kept = NinaSyncErrorClock.update(started, state: state, now: Self.now)
        #expect(kept == start)
        // A fresh launch hasn't heard from CloudKit yet: keep it.
        let relaunched = NinaSyncErrorClock.update(start, state: SyncState(mode: Self.cloud), now: Self.now)
        #expect(relaunched == start)
        // A sync that worked after it clears it.
        state.lastError = nil
        state.lastSync = Self.now.addingTimeInterval(-60)
        let cleared = NinaSyncErrorClock.update(start, state: state, now: Self.now)
        #expect(cleared == nil)
        // A sync before the error doesn't.
        state.lastSync = start.addingTimeInterval(-60)
        let older = NinaSyncErrorClock.update(start, state: state, now: Self.now)
        #expect(older == start)
        // Not syncing at all: no clock.
        let local = NinaSyncErrorClock.update(start, state: SyncState(mode: .local(reason: nil)), now: Self.now)
        #expect(local == nil)
    }

    @Test func newErrorAfterASuccessfulSyncStartsAgain() {
        let first = Self.now.addingTimeInterval(-30 * 3600)
        let state = SyncState(mode: Self.cloud, account: .available, lastSync: Self.now.addingTimeInterval(-3600), lastError: "Not syncing")
        #expect(NinaSyncErrorClock.update(first, state: state, now: Self.now) == Self.now)
    }

    @Test func throttleAllowsOneToastAMinute() {
        var throttle = NinaToastThrottle()
        let first = throttle.allows(at: Self.now)
        let soon = throttle.allows(at: Self.now.addingTimeInterval(30))
        let later = throttle.allows(at: Self.now.addingTimeInterval(61))
        let again = throttle.allows(at: Self.now.addingTimeInterval(90))
        #expect(first)
        #expect(!soon)
        #expect(later)
        #expect(!again)
    }

    @Test func sidebarLine() {
        let relative: (Date) -> String = { _ in "2 min. ago" }
        #expect(NinaSyncLine.text(SyncState(mode: .demo), relative: relative) == nil)
        #expect(NinaSyncLine.text(SyncState(mode: .local(reason: nil)), relative: relative) == "On this device only")
        #expect(NinaSyncLine.text(SyncState(mode: .memory(reason: nil)), relative: relative) == "Not saved")
        let synced = SyncState(mode: Self.cloud, account: .available, lastSync: Self.now)
        #expect(NinaSyncLine.text(synced, relative: relative) == "Synced 2 min. ago")
        #expect(NinaSyncLine.text(SyncState(mode: Self.cloud, isSyncing: true), relative: relative) == "Syncing…")
        #expect(NinaSyncLine.text(SyncState(mode: Self.cloud, lastError: "x"), relative: relative) == "Not syncing")
        #expect(NinaSyncLine.text(SyncState(mode: Self.cloud, account: .noAccount), relative: relative) == "iCloud: not signed in")
        #expect(NinaSyncLine.text(SyncState(mode: Self.cloud), relative: relative) == "iCloud sync on")
    }
}
