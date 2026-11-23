import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore
#if os(macOS)
import AppKit
#endif

/// Which way the next Copy-to-Day sheet opens. `AppSheet.copyEntries` stands for copying and
/// moving, so "Move to Day…" leaves the mode here and `CopyEntriesView` reads it as it opens.
@MainActor
enum TodayEntrySheetMode {
    static var opensToMove = false
}

/// An entry's place before a move, for the toast's Undo.
private struct TodayMovedEntry {
    let entry: LogEntry
    let day: DayKey
    let time: Date
    let meal: String
}

extension AppModel {
    /// Opens the Copy-to-Day sheet ("Another Day…"), or the same sheet to move ("Move to Day…").
    func todayOpenDaySheet(_ entries: [LogEntry], move: Bool) {
        guard !entries.isEmpty else { return }
        TodayEntrySheetMode.opensToMove = move
        sheet = .copyEntries(entries)
    }

    /// Moves entries to another day at the same clock time (a late snack stays at the end of the
    /// day), and to `meal` when given. Written through `NinaStore.update`, so each entry is touched
    /// (sync and Apple Health see the change); the toast's Undo puts day, time and meal back.
    func todayMove(_ entries: [LogEntry], to day: DayKey, meal: String? = nil) {
        let moving = entries.filter { $0.dayKey != day || (meal != nil && $0.meal != meal) }
        guard !moving.isEmpty else { return }
        let store = self.store
        let dayStartHour = settings.dayStartHour
        let before = moving.map { TodayMovedEntry(entry: $0, day: $0.dayKey, time: $0.time, meal: $0.meal) }
        let changesDay = moving.contains { $0.dayKey != day }
        for entry in moving {
            let time = DiaryEntryEdits.movedTime(entry.time, from: entry.dayKey, to: day, dayStartHour: dayStartHour)
            store.update(entry, name: entry.name, meal: meal ?? entry.meal, day: day, time: time, note: entry.note,
                         status: entry.entryStatus)
        }
        let message = todayMoveMessage(moving, to: day, meal: meal, changesDay: changesDay)
        toasts.show(message, symbol: "arrow.left.arrow.right") { [weak self] in
            guard let self else { return }
            let store = self.store
            for old in before where old.entry.modelContext != nil {
                store.update(old.entry, name: old.entry.name, meal: old.meal, day: old.day, time: old.time,
                             note: old.entry.note, status: old.entry.entryStatus)
            }
        }
    }

    /// "Moved Banana to tomorrow", "Moved 3 entries to Lunch on Mon, 17 Nov", "Moved to Dinner".
    private func todayMoveMessage(_ entries: [LogEntry], to day: DayKey, meal: String?, changesDay: Bool) -> String {
        let what = entries.count == 1 ? entries[0].displayName : "\(entries.count) entries"
        let title = Fmt.dayTitle(day, today: today)
        // "today", "yesterday", "tomorrow" inside a sentence; a date stays as it is.
        let isNear = abs(today.days(to: day)) <= 1
        guard let meal else { return "Moved \(what) to \(isNear ? title.lowercased() : title)" }
        let mealName = settings.meal(meal).name
        guard changesDay else { return "Moved \(what) to \(mealName)" }
        return "Moved \(what) to \(mealName) \(isNear ? title.lowercased() : "on " + title)"
    }

    /// Copies entries to `day` as they are pasted (⌘V): eaten up to today, planned on a later day.
    func todayPaste(_ ids: [UUID], on day: DayKey) {
        guard !ids.isEmpty else { return }
        let wanted = ids
        let descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate<LogEntry> { wanted.contains($0.uuid) && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.time), SortDescriptor(\.sortOrder)]
        )
        let found = (try? container.mainContext.fetch(descriptor)) ?? []
        guard !found.isEmpty else {
            toasts.show("The copied entries are gone", symbol: "info.circle")
            return
        }
        self.copy(found, to: day, status: day > today ? .planned : .eaten)
    }
}

#if os(macOS)
/// ⌘C and ⌘V of diary entries on the Mac. The pasteboard gets readable lines ("Banana · 105 kcal")
/// for any other app; Nina remembers which entries those lines stand for, so ⌘V on another day of
/// the diary copies them there (while the pasteboard still holds them).
@MainActor
enum TodayEntryClipboard {
    private static var copiedText = ""
    private static var copiedIDs: [UUID] = []

    /// What ⌘C puts on the pasteboard for these entries.
    static func providers(for entries: [LogEntry], unit: EnergyUnit) -> [NSItemProvider] {
        guard !entries.isEmpty else { return [] }
        let text = entries.map { "\($0.displayName) · \(Fmt.energy($0.energy, unit: unit))" }.joined(separator: "\n")
        copiedText = text
        copiedIDs = entries.map(\.uuid)
        return [NSItemProvider(object: text as NSString)]
    }

    /// The entries behind the pasteboard's text, if it is still what Nina copied.
    static func pastedIDs() -> [UUID] {
        guard !copiedIDs.isEmpty, let pasted = NSPasteboard.general.string(forType: .string) else { return [] }
        let same = pasted.trimmingCharacters(in: .whitespacesAndNewlines) == copiedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return same ? copiedIDs : []
    }
}
#endif
