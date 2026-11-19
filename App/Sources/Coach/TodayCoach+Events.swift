import Foundation
import SwiftData
import NinaCore

// Day events Today writes (`DayMark(kind: event)`): for now "incompleteLog", a day whose diary
// is not complete. The weekly check-in, adherence and "Copy for my AI" leave such days out
// (CoachContext and PlanEditorData read the mark). No SwiftUI here.

extension NinaStore {
    /// Whether `day` has a live event mark with this key ("incompleteLog", "ill", "travel", "period").
    func hasDayEvent(_ key: String, on day: DayKey) -> Bool {
        dayMarks(.event, on: day).contains { $0.key == key }
    }

    /// Marks `day` with an event, or takes the mark off (soft delete: the marks go to the trash).
    /// Saves; `undo(result)` puts it back. Nothing changes (an empty result) when the day is
    /// already that way.
    @discardableResult
    func setDayEvent(_ key: String, on day: DayKey, isOn: Bool) -> CoachUndo {
        let live = dayMarks(.event, on: day).filter { $0.key == key }
        var undo = CoachUndo()
        if isOn {
            guard live.isEmpty else { return undo }
            let mark = DayMark(day: day, kind: .event, key: key)
            context.insert(mark)
            undo.inserted.append(mark)
        } else {
            guard !live.isEmpty else { return undo }
            let now = Date()
            for mark in live {
                mark.deletedAt = now
                mark.modifiedAt = now
                undo.trashed.append(mark)
            }
        }
        save()
        return undo
    }
}

extension AppModel {
    /// Marks `day`'s log as incomplete (left out of check-ins and adherence) or complete again,
    /// with an Undo toast.
    func setIncompleteLog(_ isOn: Bool, on day: DayKey) {
        let store = self.store
        let change = store.setDayEvent(TodayCoachEvent.incompleteLog, on: day, isOn: isOn)
        if isOn {
            showUndo(change, "Log marked as incomplete", symbol: "exclamationmark.circle.fill")
        } else {
            showUndo(change, "Log marked as complete", symbol: "checkmark.circle.fill")
        }
    }
}
