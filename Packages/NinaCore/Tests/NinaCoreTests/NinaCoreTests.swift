import Foundation
import Testing
import BinisoftKitCore
@testable import NinaCore

@Suite("Tour")
struct TourCatalogTests {
    @Test func catalogHasNoProblems() {
        #expect(NinaTour.catalog.problems().isEmpty)
    }

    @Test func firstRunShowsEverything() {
        let steps = NinaTour.catalog.steps(newerThan: 0)
        #expect(steps.first?.id == "welcome")
        #expect(steps.last?.id == "finish")
        #expect(steps.count == NinaTour.catalog.steps.count + 2)
    }

    @Test func nothingNewForTheCurrentVersion() {
        #expect(NinaTour.catalog.steps(newerThan: NinaTour.version).isEmpty)
    }

    @Test func stepsTickOffOnThePracticePage() {
        var page = NinaTourSnapshot()
        page.itemCount = 5
        page.order = ["a", "b", "c"]
        var progress = TourProgress(steps: NinaTour.catalog.allSteps, start: page, startAt: "add")
        page.itemCount = 6
        let added = progress.observe(page)
        #expect(added)

        var undo = TourProgress(steps: NinaTour.catalog.allSteps, start: page, startAt: "undo")
        page.trashedCount = 1
        let deleted = undo.observe(page)
        page.trashedCount = 0
        let restored = undo.observe(page)
        #expect(!deleted)
        #expect(restored)
    }
}

@Suite("CSV")
struct CSVTests {
    let file = """
    id,title,notes,done,folder
    1,Water the plants,,,Home
    2,Send the invoice,"Before Friday, please",yes,Work
    3,,no title here,,
    """

    @Test func parsesRowsAndSkipsBadOnes() {
        let parsed = ItemCSV.parse(file)
        #expect(parsed.rows.count == 2)
        #expect(parsed.rows[1].draft == ItemDraft(title: "Send the invoice", notes: "Before Friday, please", isDone: true, folder: "Work"))
        #expect(parsed.rows[0].key == "id:1")
        #expect(parsed.skipped == ["Row 4: no title"])
    }

    @Test func reimportingTheSameFileChangesNothing() {
        let first = ItemCSV.plan(file, existing: [:])
        #expect(first.creates == 2)
        let existing = Dictionary(uniqueKeysWithValues: first.entries.map { ($0.key, $0.record) })
        let second = ItemCSV.plan(file, existing: existing)
        #expect(!second.hasChanges)
        #expect(second.unchanged == 2)
    }

    @Test func withoutIdColumnTheContentIsTheKey() {
        let text = "title;folder\nMilk;Shopping\nmilk ;shopping\n"
        let parsed = ItemCSV.parse(text)
        #expect(parsed.rows.count == 2)
        #expect(parsed.rows[0].key == parsed.rows[1].key)
        #expect(ItemCSV.plan(text, existing: [:]).creates == 1)
    }

    @Test func missingTitleColumnIsExplained() {
        let parsed = ItemCSV.parse("name,notes\nMilk,\n")
        #expect(parsed.rows.isEmpty)
        #expect(parsed.skipped.first?.contains("title") == true)
    }

    @Test func exportRoundTrips() {
        let rows: [(key: String, draft: ItemDraft)] = [
            ("id:7", ItemDraft(title: "Call, then email", notes: "Line one\nline two", isDone: true, folder: "Work")),
            ("plain key", ItemDraft(title: "Milk")),
        ]
        let parsed = ItemCSV.parse(ItemCSV.export(rows))
        #expect(parsed.rows.map(\.draft) == rows.map(\.draft))
        #expect(parsed.rows[0].key == "id:7")
        #expect(parsed.rows[1].key == "id:plain key")
    }

    @Test func exportedFileReimportsWithoutDuplicates() {
        // Imported once without ids (content keys), exported, imported again.
        let original = ItemCSV.parse("title,folder\nMilk,Shopping\n")
        var existing: [String: ItemDraft] = [:]
        for row in original.rows {
            for key in ItemCSV.lookupKeys(forKey: row.key) { existing[key] = row.draft }
        }
        let exported = ItemCSV.export(original.rows.map { ($0.key, $0.draft) })
        let plan = ItemCSV.plan(exported, existing: existing)
        #expect(plan.creates == 0)
        #expect(plan.unchanged == 1)
        #expect(ItemCSV.lookupKeys(forKey: "id:7") == ["id:7"])
    }

    @Test func doneAcceptsCommonWords() {
        for word in ["yes", "Y", "true", "1", "x", "ja", "✓"] {
            #expect(ItemCSV.isYes(word))
        }
        #expect(!ItemCSV.isYes(""))
        #expect(!ItemCSV.isYes("no"))
    }

    @Test func promptHasTheHeaderAndFolders() {
        let text = ItemCSV.prompt(appName: "Nina", existingFolders: ["Home", "Work"]).text
        #expect(text.contains("\nid,title,notes,done,folder\n"))
        #expect(text.contains("Folders: Home, Work"))
    }

    /// Runs only with a real file: NINA_REAL_FILE=/path/to/export.csv swift test
    /// The file stays in the session scratchpad and is never committed; CI skips this test.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NINA_REAL_FILE"] != nil))
    func realFileImports() throws {
        let path = try #require(ProcessInfo.processInfo.environment["NINA_REAL_FILE"])
        let text = CSV.decode(try Data(contentsOf: URL(fileURLWithPath: path)))
        let plan = ItemCSV.plan(text, existing: [:])
        print("Real file: \(plan.summary)")
        #expect(plan.creates > 0)
    }
}

@Suite("Summary")
struct SummaryTests {
    @Test func makesHeadlineAndNext() {
        let summary = ItemSummary.make(open: ["a", "b", "c", "d"], doneCount: 2, now: Date(timeIntervalSince1970: 0))
        #expect(summary.openCount == 4)
        #expect(summary.next == ["a", "b", "c"])
        #expect(summary.headline == "4 open")
        #expect(ItemSummary.make(open: [], doneCount: 1).headline == "All done")
    }

    @Test func sameContentIgnoresTime() {
        let a = ItemSummary.make(open: ["a"], doneCount: 0, now: Date(timeIntervalSince1970: 0))
        let b = ItemSummary.make(open: ["a"], doneCount: 0, now: Date(timeIntervalSince1970: 99))
        #expect(a.hasSameContent(as: b))
        #expect(!a.hasSameContent(as: nil))
        #expect(!a.hasSameContent(as: ItemSummary.make(open: ["a"], doneCount: 1)))
    }

    @Test func snapshotFileRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nina-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = SnapshotFile<ItemSummary>(folder: folder, name: ItemSummary.fileName)
        try file.write(.placeholder)
        #expect(file.read() == .placeholder)
    }
}
