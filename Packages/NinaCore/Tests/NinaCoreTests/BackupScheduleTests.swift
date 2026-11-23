import Foundation
import Testing
@testable import NinaCore

// The automatic weekly backup: when it is due, folder names, keeping the last 4, the status line
// and the device-only state. All dates and paths are made up.

private var utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// 2030-01-07 08:00 UTC plus `days` days and `hours` hours.
private func at(_ days: Double, hours: Double = 0) -> Date {
    Date(timeIntervalSince1970: 1_894_003_200 + days * 86_400 + hours * 3600)
}

private func made(_ name: String, day: Double, records: Int = 100, place: String = BackupAutoState.appFolder) -> BackupAutoState.Made {
    BackupAutoState.Made(name: name, place: place, created: at(day), records: records)
}

@Suite("Backup: automatic schedule")
struct BackupScheduleTests {
    @Test func onByDefaultOnlyOnIPhone() {
        #expect(BackupSchedule.isOnByDefault(isPhone: true))
        #expect(!BackupSchedule.isOnByDefault(isPhone: false))
    }

    @Test func dueTheFirstTimeAndThenEverySevenDays() {
        var state = BackupAutoState()
        #expect(BackupSchedule.isDue(state, now: at(0), calendar: utc))
        state.succeeded(made("Nina Backup 2030-01-07", day: 0), usedFallback: false)
        #expect(!BackupSchedule.isDue(state, now: at(0, hours: 7), calendar: utc))
        #expect(!BackupSchedule.isDue(state, now: at(6, hours: 15), calendar: utc)) // Sunday 23:00
        // Calendar days: next Monday at 00:30 is due, even before 08:00.
        #expect(BackupSchedule.isDue(state, now: at(6, hours: 16.5), calendar: utc))
        #expect(BackupSchedule.isDue(state, now: at(30), calendar: utc))
    }

    @Test func aFailedTryWaitsSixHours() {
        var state = BackupAutoState()
        state.succeeded(made("Nina Backup 2030-01-07", day: 0), usedFallback: false)
        _ = state.failed(.write, at: at(7), calendar: utc)
        #expect(!BackupSchedule.isDue(state, now: at(7, hours: 5.9), calendar: utc))
        #expect(BackupSchedule.isDue(state, now: at(7, hours: 6), calendar: utc))
        // Nothing to back up yet waits too.
        var empty = BackupAutoState()
        empty.skipped(at: at(0))
        #expect(!BackupSchedule.isDue(empty, now: at(0, hours: 1), calendar: utc))
        #expect(BackupSchedule.isDue(empty, now: at(0, hours: 6), calendar: utc))
    }

    @Test func aClockSetBackDoesntStopTheBackups() {
        var state = BackupAutoState()
        // Made while the clock was a year ahead.
        state.succeeded(made("Nina Backup 2031-01-07", day: 365), usedFallback: false)
        #expect(BackupSchedule.isDue(state, now: at(10), calendar: utc))
        #expect(BackupSchedule.daysUntilNext(state, now: at(10), calendar: utc) == 0)
        // Less than a day ahead (a time-zone trip) is just today.
        var trip = BackupAutoState()
        trip.succeeded(made("Nina Backup 2030-01-08", day: 0, records: 10), usedFallback: false)
        #expect(!BackupSchedule.isDue(trip, now: at(0, hours: -10), calendar: utc))
    }

    @Test func daysUntilTheNextOne() {
        var state = BackupAutoState()
        #expect(BackupSchedule.daysUntilNext(state, now: at(0), calendar: utc) == nil)
        state.succeeded(made("A", day: 0), usedFallback: false)
        #expect(BackupSchedule.daysUntilNext(state, now: at(0), calendar: utc) == 7)
        #expect(BackupSchedule.daysUntilNext(state, now: at(3), calendar: utc) == 4)
        #expect(BackupSchedule.daysUntilNext(state, now: at(12), calendar: utc) == 0)
    }

    @Test func onlyABackupWithDataIsWritten() {
        #expect(!BackupSchedule.hasData([:]))
        #expect(!BackupSchedule.hasData(["NinaProfile": 1]))
        #expect(!BackupSchedule.hasData(["NinaProfile": 1, "LogEntry": 0]))
        #expect(BackupSchedule.hasData(["NinaProfile": 1, "WeightEntry": 1]))
        #expect(BackupSchedule.hasData(["Food": 3]))
    }

    @Test func folderNamesNeverClash() {
        let day = DayKey("2030-01-07")!
        #expect(BackupSchedule.folderName(app: "Nina", day: day, existing: []) == "Nina Backup 2030-01-07")
        #expect(BackupSchedule.folderName(app: "Nina", day: day, existing: ["Nina Backup 2030-01-06", "Notes.txt"])
            == "Nina Backup 2030-01-07")
        #expect(BackupSchedule.folderName(app: "Nina", day: day, existing: ["Nina Backup 2030-01-07"]) == "Nina Backup 2030-01-07 (2)")
        #expect(BackupSchedule.folderName(app: "Nina", day: day, existing: ["nina backup 2030-01-07", "Nina Backup 2030-01-07 (2)"])
            == "Nina Backup 2030-01-07 (3)")
        // A folder iCloud Drive hasn't downloaded yet is listed as ".Name.icloud".
        #expect(BackupSchedule.folderName(app: "Nina", day: day, existing: [".Nina Backup 2030-01-07.icloud"])
            == "Nina Backup 2030-01-07 (2)")
        #expect(BackupSchedule.listedName(".Nina Backup 2030-01-07.icloud") == "Nina Backup 2030-01-07")
        #expect(BackupSchedule.listedName(".icloud") == ".icloud")
        #expect(BackupSchedule.listedName(".DS_Store") == ".DS_Store")
    }

    @Test func keepsTheLastFour() {
        let backups = (0..<6).map { made("B\($0)", day: Double($0) * 7) }
        let removed = BackupSchedule.removals(backups.shuffled(), in: BackupAutoState.appFolder)
        #expect(removed.map(\.name) == ["B0", "B1"])
        #expect(BackupSchedule.removals(Array(backups.prefix(4)), in: BackupAutoState.appFolder).isEmpty)
    }

    @Test func onlyRemovesBackupsOfTheSamePlace() {
        let backups = (0..<5).map { made("App\($0)", day: Double($0) * 7) }
            + (0..<3).map { made("Cloud\($0)", day: Double($0) * 7 + 1, place: "/iCloud/Nina") }
        #expect(BackupSchedule.removals(backups, in: BackupAutoState.appFolder).map(\.name) == ["App0"])
        #expect(BackupSchedule.removals(backups, in: "/iCloud/Nina").isEmpty)
    }

    @Test func aMuchFullerBackupIsKeptWhenDataWentMissing() {
        // Four weeks after most of the data disappeared, the last full backup would go – it stays.
        var backups = [made("Full1", day: 0, records: 5_000), made("Full2", day: 7, records: 5_100)]
        backups += (2..<6).map { made("Thin\($0)", day: Double($0) * 7, records: 40) }
        let removed = BackupSchedule.removals(backups, in: BackupAutoState.appFolder)
        #expect(removed.map(\.name) == ["Full1"])
        // Data that only grew: nothing special.
        let growing = (0..<6).map { made("G\($0)", day: Double($0) * 7, records: 1_000 + $0 * 10) }
        #expect(BackupSchedule.removals(growing, in: BackupAutoState.appFolder).map(\.name) == ["G0", "G1"])
        // Once the newer ones are about as full again, it goes too.
        let refilled = [made("Full2", day: 7, records: 5_100)] + (2..<6).map { made("New\($0)", day: Double($0) * 7, records: 3_000) }
        #expect(BackupSchedule.removals(refilled, in: BackupAutoState.appFolder).map(\.name) == ["Full2"])
    }

    @Test func onlyTheBackupItselfIsRemovedNotAnotherFolderOfThatName() {
        let backup = made("Nina Backup 2030-01-07", day: 0, records: 120)
        func manifest(created: Date) -> Data {
            NinaBackup.encode(NinaBackup.Manifest(app: "Nina", appVersion: "1.2.0", created: created, device: "iPhone",
                                                  counts: ["Food": 120], photos: 0))
        }
        // The one this device wrote (the manifest keeps milliseconds).
        #expect(BackupSchedule.isSameBackup(backup, manifestData: manifest(created: at(0).addingTimeInterval(0.0004))))
        // Nothing to read: the list decides.
        #expect(BackupSchedule.isSameBackup(backup, manifestData: nil))
        // Saved by hand (or by another device) later under the same name, or not a backup at all: it stays.
        #expect(!BackupSchedule.isSameBackup(backup, manifestData: manifest(created: at(0, hours: 3))))
        #expect(!BackupSchedule.isSameBackup(backup, manifestData: Data("holiday photos".utf8)))
        #expect(!BackupSchedule.isSameBackup(backup, manifestData: Data(#"{"format": "something-else"}"#.utf8)))
    }

    @Test func stateRecordsWhatHappened() {
        var state = BackupAutoState()
        state.succeeded(made("A", day: 0), usedFallback: false)
        state.succeeded(made("B", day: 7), usedFallback: true)
        #expect(state.made.map(\.name) == ["A", "B"])
        #expect(state.lastSuccess == at(7) && state.usedFallback)
        // Writing the same folder again (Back Up Now twice) doesn't list it twice.
        state.succeeded(made("B", day: 7.5), usedFallback: false)
        #expect(state.made.map(\.name) == ["A", "B"])
        state.forget([made("A", day: 0)])
        #expect(state.made.map(\.name) == ["B"])
    }

    @Test func oneCalmNoticePerRunOfFailures() {
        var state = BackupAutoState()
        // Never backed up: the first failure says so once.
        let first = state.failed(.space, at: at(0), calendar: utc)
        let second = state.failed(.space, at: at(1), calendar: utc)
        #expect(first && !second)
        state.succeeded(made("A", day: 2), usedFallback: false)
        #expect(state.problem == nil && !state.noticeShown)
        // A recent backup: failing is quiet …
        let recent = state.failed(.write, at: at(9), calendar: utc)
        #expect(!recent)
        // … until there has been none for two weeks.
        let late = state.failed(.write, at: at(16), calendar: utc)
        let later = state.failed(.write, at: at(17), calendar: utc)
        #expect(late && !later)
    }

    @Test func choosingAFolderForgetsOtherPlaces() {
        var state = BackupAutoState()
        state.succeeded(made("A", day: 0), usedFallback: false)
        state.succeeded(made("B", day: 7, place: "/Old"), usedFallback: false)
        _ = state.failed(.folder, at: at(8), calendar: utc)
        let folder = BackupAutoState.Folder(id: "/New", title: "New", bookmark: Data([1, 2, 3]))
        state.choose(folder)
        #expect(state.place == "/New")
        #expect(state.made.map(\.name) == ["A"])
        #expect(state.problem == nil)
        state.choose(nil)
        #expect(state.place == BackupAutoState.appFolder)
    }

    @Test func placeTitles() {
        #expect(BackupSchedule.placeTitle(path: "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Nina")
            == "iCloud Drive → Nina")
        #expect(BackupSchedule.placeTitle(path: "/Users/someone/Library/Mobile Documents/com~apple~CloudDocs/Backups/Nina/")
            == "iCloud Drive → Backups → Nina")
        #expect(BackupSchedule.placeTitle(path: "/Users/someone/Documents/Nina Backups") == "Documents → Nina Backups")
        #expect(BackupSchedule.placeTitle(path: "/Volumes/USB/Nina") == "USB → Nina")
        #expect(BackupSchedule.placeTitle(path: "/private/var/mobile/Containers/Shared/AppGroup/X/File Provider Storage/Backups")
            == "Backups")
        #expect(BackupSchedule.placeTitle(path: "/") == "/")
    }

    @Test func statusLines() {
        var state = BackupAutoState()
        #expect(BackupSchedule.status(state, now: at(0), calendar: utc) == "No automatic backup yet – the first one starts soon.")
        state.succeeded(made("A", day: 0), usedFallback: false)
        #expect(BackupSchedule.status(state, now: at(0, hours: 2), calendar: utc) == "Last backup: today · next in 7 days.")
        #expect(BackupSchedule.status(state, now: at(1), calendar: utc) == "Last backup: yesterday · next in 6 days.")
        #expect(BackupSchedule.status(state, now: at(6), calendar: utc) == "Last backup: 6 days ago · next in 1 day.")
        #expect(BackupSchedule.status(state, now: at(8), calendar: utc) == "Last backup: 8 days ago · the next one starts soon.")
        _ = state.failed(.space, at: at(8), calendar: utc)
        #expect(BackupSchedule.status(state, now: at(8), calendar: utc)
            == "Last backup: 8 days ago. The latest try didn't work – there isn't enough free space on this device. Nina tries again later.")
        state.succeeded(made("B", day: 9), usedFallback: true)
        #expect(BackupSchedule.status(state, now: at(9), calendar: utc)
            == "Last backup: today · next in 7 days. Your chosen folder couldn't be opened, so it went to Nina's own folder.")
        var never = BackupAutoState()
        _ = never.failed(.write, at: at(0), calendar: utc)
        #expect(BackupSchedule.status(never, now: at(0), calendar: utc)
            == "The automatic backup didn't work – the backup couldn't be written. Nina tries again later.")
    }

    @Test func stateSurvivesStorageAndBrokenData() {
        var state = BackupAutoState(folder: BackupAutoState.Folder(id: "/Cloud/Nina", title: "iCloud Drive → Nina", bookmark: Data([9, 8, 7])))
        state.succeeded(made("A", day: 0, place: "/Cloud/Nina"), usedFallback: false)
        _ = state.failed(.write, at: at(7, hours: 0.5), calendar: utc)
        let back = BackupAutoState.decode(state.encoded())
        #expect(back == state)
        // Nothing stored, garbage, or fields from a newer version: never a crash.
        #expect(BackupAutoState.decode(nil) == BackupAutoState())
        #expect(BackupAutoState.decode(Data("nope".utf8)) == BackupAutoState())
        let newer = Data(#"{"lastSuccess": 1894003200, "problem": "gremlins", "made": [], "future": true, "usedFallback": "yes"}"#.utf8)
        let lenient = BackupAutoState.decode(newer)
        #expect(lenient.lastSuccess == at(0))
        #expect(lenient.problem == nil && !lenient.usedFallback && lenient.made.isEmpty)
    }
}
