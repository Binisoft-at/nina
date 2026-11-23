import Foundation
import SwiftData
import NinaCore

extension NinaStore {
    /// The plan keys the routines must not plan again from `today` for `horizon` days
    /// (`PlanSchedule.takenKeys`): those of the window's entries (`window`, live or in the trash,
    /// as the clean-up sees them) and those of entries moved to another day ("Move to Day…", a new
    /// date in the entry editor). A moved entry keeps the key of the day it was planned for, so the
    /// day the person moved a planned meal away from isn't planned again, and that new copy can't
    /// later be taken for a duplicate of the moved one.
    func takenPlanKeys(window: [PlanSchedule.Item], rules: [PlanRule], from today: DayKey, horizon: Int) -> Set<String> {
        var items = window
        let present = Set(window.map(\.key))
        var wanted: [String] = []
        for rule in rules {
            wanted += PlanSchedule.keys(rule: rule.uuid, weekdays: rule.days, from: today, horizon: horizon,
                                        startDay: rule.start, endDay: rule.end, calendar: calendar)
        }
        let missing = wanted.filter { !present.contains($0) }
        if !missing.isEmpty {
            let descriptor = FetchDescriptor<LogEntry>(predicate: #Predicate<LogEntry> { missing.contains($0.planKey) })
            let moved: [LogEntry] = (try? context.fetch(descriptor)) ?? []
            items += moved.map { (entry: LogEntry) -> PlanSchedule.Item in
                PlanSchedule.Item(id: entry.uuid.uuidString, key: entry.planKey, groupID: entry.groupID, status: entry.status,
                                  source: entry.source, createdAt: entry.createdAt, modifiedAt: entry.modifiedAt,
                                  isTrashed: entry.deletedAt != nil)
            }
        }
        return PlanSchedule.takenKeys(items)
    }
}
