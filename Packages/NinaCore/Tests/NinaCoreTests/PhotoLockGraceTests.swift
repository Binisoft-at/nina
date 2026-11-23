import Foundation
import Testing
@testable import NinaCore

/// The Mac's photo lock: five minutes away from Nina lock the photos again, leaving the Mac locks
/// them at once. Made-up times.
@Suite("Photo lock grace")
struct PhotoLockGraceTests {
    static let start = Date(timeIntervalSince1970: 1_900_000_000)

    static func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    @Test func graceIsFiveMinutes() {
        #expect(NinaPhotoLockGrace.macBackground == 300)
        #expect(NinaPhotoLockGrace().grace == 300)
    }

    @Test func backgroundStartsTheTimerForTheWholeGrace() {
        var grace = NinaPhotoLockGrace()
        let action = grace.handle(.background, at: Self.start)
        #expect(action == .lockAfter(300))
        #expect(grace.leftAt == Self.start)
        #expect(grace.lockTime == Self.at(300))
    }

    @Test func quickSwitchDoesNotLock() {
        var grace = NinaPhotoLockGrace()
        _ = grace.handle(.background, at: Self.start)
        let back = grace.handle(.foreground, at: Self.at(299))
        #expect(back == .cancelTimer)
        #expect(grace.leftAt == nil)
    }

    @Test func fiveMinutesAwayLocksOnTheTimer() {
        var grace = NinaPhotoLockGrace()
        _ = grace.handle(.background, at: Self.start)
        let fired = grace.handle(.timerFired, at: Self.at(300))
        #expect(fired == .lock)
    }

    @Test func lateTimerStillLocksWhenComingBack() {
        // App Nap held the timer back: coming back after the grace locks before the photos show.
        var grace = NinaPhotoLockGrace()
        _ = grace.handle(.background, at: Self.start)
        let back = grace.handle(.foreground, at: Self.at(301))
        #expect(back == .lock)
        #expect(grace.leftAt == nil)
    }

    @Test func earlyTimerWaitsForTheRest() {
        var grace = NinaPhotoLockGrace()
        _ = grace.handle(.background, at: Self.start)
        let fired = grace.handle(.timerFired, at: Self.at(200))
        #expect(fired == .lockAfter(100))
    }

    @Test func timerAfterComingBackDoesNothing() {
        var grace = NinaPhotoLockGrace()
        _ = grace.handle(.background, at: Self.start)
        _ = grace.handle(.foreground, at: Self.at(10))
        let fired = grace.handle(.timerFired, at: Self.at(300))
        #expect(fired == .nothing)
    }

    @Test func hidingAfterSwitchingKeepsTheFirstTime() {
        // ⌘H right after another app came forward: both report "background", the first one counts.
        var grace = NinaPhotoLockGrace()
        _ = grace.handle(.background, at: Self.start)
        let hidden = grace.handle(.background, at: Self.at(120))
        #expect(hidden == .lockAfter(180))
        #expect(grace.leftAt == Self.start)
        let back = grace.handle(.foreground, at: Self.at(310))
        #expect(back == .lock)
    }

    @Test func leavingTheMacLocksAtOnce() {
        var inFront = NinaPhotoLockGrace()
        let lockedInFront = inFront.handle(.away, at: Self.start)
        #expect(lockedInFront == .lock)

        var behind = NinaPhotoLockGrace()
        _ = behind.handle(.background, at: Self.start)
        let lockedBehind = behind.handle(.away, at: Self.at(5))
        #expect(lockedBehind == .lock)
    }

    @Test func comingBackWithoutLeavingOnlyStopsTheTimer() {
        var grace = NinaPhotoLockGrace()
        let back = grace.handle(.foreground, at: Self.start)
        #expect(back == .cancelTimer)
        #expect(grace.leftAt == nil)
    }

    @Test func clockSetBackCountsFromNow() {
        var grace = NinaPhotoLockGrace()
        _ = grace.handle(.background, at: Self.at(1000))
        // The clock jumped back an hour while Nina was away.
        let fired = grace.handle(.timerFired, at: Self.at(1000 - 3600))
        #expect(fired == .lockAfter(300))
        #expect(grace.leftAt == Self.at(1000 - 3600))
        let back = grace.handle(.foreground, at: Self.at(1000 - 3600 + 300))
        #expect(back == .lock)
    }

    @Test func zeroGraceLocksRightAway() {
        var grace = NinaPhotoLockGrace(grace: 0)
        let action = grace.handle(.background, at: Self.start)
        #expect(action == .lock)
        #expect(NinaPhotoLockGrace(grace: -5).grace == 0)
    }
}
