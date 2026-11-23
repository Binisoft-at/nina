import Foundation
import Testing
@testable import NinaCore

// "Back Up Everything" and "Restore from Backup". All records are made up.

private let created = Date(timeIntervalSince1970: 1_894_003_200) // 2030-01-07 08:00 UTC

private func entry(_ name: String, uuid: UUID = UUID(), deleted: Date? = nil, modified: Date = created) -> BackupRecord {
    var record = BackupRecord(.entry, uuid: uuid)
    record.set("day", "2030-01-07")
    record.set("time", date: created)
    record.set("meal", "breakfast")
    record.set("name", name)
    record.set("quantity", 1.5)
    record.set("nutrients", "energy=52.3333;protein=0.26")
    record.set("sortOrder", 820_000_123.456)
    record.set("createdAt", date: created)
    record.set("modifiedAt", date: modified)
    record.set("deletedAt", date: deleted)
    return record
}

@Suite("Backup")
struct BackupTests {
    @Test func recordsComeBackExactly() throws {
        var recipe = BackupRecord(.recipe, uuid: UUID())
        recipe.set("name", "Overnight oats, \"classic\" 🥣")
        recipe.set("isFavorite", true)
        recipe.set("servings", 2)
        recipe.set("lastUsedAt", date: nil)
        var item = BackupRecord(type: "RecipeItem", uuid: UUID())
        item.set("name", "Oats\nrolled")
        item.set("quantity", 80)
        recipe.set("items", [item])
        let records = [entry("Banana"), recipe, entry("Kaffee ☕️", deleted: created)]
        let data = NinaBackup.encode(records)
        #expect(String(decoding: data, as: UTF8.self).split(separator: "\n").count == 3) // one line each
        let back = NinaBackup.decode(data)
        #expect(back.unreadable == 0)
        #expect(back.records == records)
        let restored = try #require(back.records.dropFirst().first)
        #expect(restored.bool("isFavorite"))
        #expect(restored.int("servings") == 2)
        #expect(restored.date("lastUsedAt") == nil)
        #expect(restored.records("items").first?.string("name") == "Oats\nrolled")
        #expect(back.records.first?.date("time") == created)
        #expect(back.records.first?.double("sortOrder") == 820_000_123.456)
        #expect(back.records.last?.deletedAt == created)
    }

    @Test func datesKeepTheirMilliseconds() {
        let date = Date(timeIntervalSince1970: 1_894_003_200.125)
        let text = NinaBackup.text(of: date)
        #expect(text == "2030-01-07T08:00:00.125Z")
        #expect(NinaBackup.date(from: text) == date)
        #expect(NinaBackup.date(from: "2030-01-07T08:00:00Z") == created)
    }

    @Test func aBrokenLineIsCountedNotFatal() {
        var data = NinaBackup.encode([entry("A")])
        data.append(Data("{not json\n\n".utf8))
        data.append(NinaBackup.encode([entry("B")]))
        let back = NinaBackup.decode(data)
        #expect(back.records.map { $0.string("name") } == ["A", "B"])
        #expect(back.unreadable == 1)
    }

    @Test func manifestChecksFormatAndVersion() throws {
        let manifest = NinaBackup.Manifest(app: "Nina", appVersion: "1.2.0", created: created, device: "iPhone",
                                           counts: ["LogEntry": 2, "Food": 1], photos: 0)
        let data = NinaBackup.encode(manifest)
        #expect(try NinaBackup.decodeManifest(data) == manifest)
        #expect(manifest.total == 3)
        var newer = manifest
        newer.version = NinaBackup.version + 1
        #expect(throws: NinaBackup.ReadError.newerVersion(NinaBackup.version + 1)) { try NinaBackup.decodeManifest(NinaBackup.encode(newer)) }
        var other = manifest
        other.format = "something-else"
        #expect(throws: NinaBackup.ReadError.notABackup) { try NinaBackup.decodeManifest(NinaBackup.encode(other)) }
        #expect(throws: NinaBackup.ReadError.notABackup) { try NinaBackup.decodeManifest(Data(#"{"hello":1}"#.utf8)) }
        #expect(throws: NinaBackup.ReadError.unreadable) { try NinaBackup.decodeManifest(Data("no".utf8)) }
    }

    @Test func namesAndPaths() {
        #expect(NinaBackup.folderName(app: "Nina", day: DayKey("2030-01-07")!) == "Nina Backup 2030-01-07")
        let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
        #expect(NinaBackup.photoPath(id) == "photos/6F9619FF-8B86-D011-B42D-00C04FC964FF.jpg")
        #expect(NinaBackup.photoPath(id, thumbnail: true) == "photos/6F9619FF-8B86-D011-B42D-00C04FC964FF-thumb.jpg")
        #expect(NinaBackup.counts([entry("A"), entry("B")]) == ["LogEntry": 2])
    }
}

@Suite("Backup: restore")
struct BackupRestoreTests {
    @Test func addsOnlyWhatIsMissing() {
        let here = entry("Here")
        let changed = entry("Changed since", modified: created.addingTimeInterval(60))
        let missing = entry("Missing")
        let trashed = entry("Deleted last week", deleted: created.addingTimeInterval(-7 * 86_400))
        let longGone = entry("Deleted long ago", deleted: created.addingTimeInterval(-40 * 86_400))
        var food = BackupRecord(.food, uuid: UUID())
        food.set("name", "Skyr")
        let records = [missing, here, changed, trashed, longGone, food, here]
        let existing: [BackupType: [UUID: Date]] = [.entry: [here.uuid: created, changed.uuid: created]]
        let plan = BackupRestorePlan(records, existing: existing, currentProfile: nil, now: created)
        // Foods are added before the diary entries that may use them.
        #expect(plan.inserts.map { $0.string("name") } == ["Skyr", "Missing", "Deleted last week"])
        let diary = plan.lines.first { $0.type == .entry }
        #expect(diary?.inFile == 5) // the repeated record counts once
        #expect(diary?.new == 2)
        #expect(diary?.alreadyHere == 2)
        #expect(diary?.differ == 1)
        #expect(diary?.expired == 1)
        #expect(diary?.detail == "2 new · 2 already here (1 changed since – yours are kept) · 1 deleted long ago, left out")
        #expect(plan.summary == "3 to add · 2 already here")
        #expect(plan.hasChanges)
        #expect(plan.profileState == BackupRestorePlan.ProfileState.none)
    }

    @Test func aBackupOfTheSameDataChangesNothing() {
        let records = [entry("A"), entry("B")]
        var existing: [UUID: Date] = [:]
        for record in records { existing[record.uuid] = created }
        let plan = BackupRestorePlan(records, existing: [.entry: existing], currentProfile: nil, now: created)
        #expect(!plan.hasChanges)
        #expect(plan.summary == "Everything in this backup is already in Nina")
    }

    @Test func goalsAndPlan() {
        var profile = BackupRecord(.profile, uuid: UUID())
        profile.set("goal", "lose")
        profile.set("coachPlan", "{}")
        profile.set("modifiedAt", date: created)
        var mine = BackupRecord(.profile, uuid: UUID())
        mine.set("goal", "lose")
        mine.set("coachPlan", "{}")
        mine.set("modifiedAt", date: created.addingTimeInterval(3600))
        #expect(BackupRestorePlan([profile], existing: [:], currentProfile: nil).profileState == .new)
        #expect(BackupRestorePlan([profile], existing: [:], currentProfile: nil).hasChanges)
        #expect(BackupRestorePlan([profile], existing: [:], currentProfile: mine).profileState == .same)
        mine.set("goal", "gain")
        let differs = BackupRestorePlan([profile], existing: [:], currentProfile: mine)
        #expect(differs.profileState == .differs)
        #expect(!differs.hasChanges) // replaced only when switched on
        #expect(differs.inserts.isEmpty)
    }

    @Test func typesFromANewerVersionAreLeftOut() {
        let plan = BackupRestorePlan([BackupRecord(type: "Shopping", uuid: UUID()), entry("A")], existing: [:], currentProfile: nil)
        #expect(plan.unknownTypes == ["Shopping"])
        #expect(plan.inserts.count == 1)
    }

    @Test func everyTypeHasATitle() {
        for type in BackupType.allCases { #expect(!type.title.isEmpty) }
        #expect(Set(BackupType.allCases.map(\.title)).count == BackupType.allCases.count)
    }
}
