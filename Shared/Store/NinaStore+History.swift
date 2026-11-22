import Foundation
import SwiftData
import NinaCore

// The weight & body history import and export (BodyHistoryCSV): past weigh-ins, tape sessions and
// body-fat values. Compiled into the app and the watch, so Foundation and SwiftData only. Only
// Nina's own records are read and written here – never values read from Apple Health, and imported
// weigh-ins are not written to Apple Health.

// MARK: - Bridges to Core

extension WeightEntry {
    /// The weigh-in as a row of the history file.
    var historyRecord: BodyHistoryRecord {
        BodyHistoryRecord.weight(day: dayKey, minutes: ClockTime.minutes(of: time), kilograms: kilograms, bodyFat: bodyFat, note: note)
    }
}

extension BodyMeasurement {
    /// The tape session or body-fat value as a row of the history file (no method counts as an estimate).
    var historyRecord: BodyHistoryRecord {
        let minutes = ClockTime.minutes(of: time)
        switch recordKind {
        case .tape:
            return BodyHistoryRecord.tape(day: dayKey, minutes: minutes, values: bodyValues, conditions: conditions, note: note)
        case .assessment:
            return BodyHistoryRecord.assessment(day: dayKey, minutes: minutes, values: bodyValues, method: bodyMethod ?? .estimate,
                                                device: device, conditions: conditions, note: note)
        }
    }
}

// MARK: - Reading and writing

extension NinaStore {
    /// Every live weigh-in, tape session and body-fat value typed or imported in Nina, as history
    /// records (weigh-ins first, each oldest first).
    func bodyHistory() -> [BodyHistoryRecord] {
        weights().map(\.historyRecord) + measurements().map(\.historyRecord)
    }

    /// The history file of everything in `bodyHistory()`, oldest first.
    func bodyHistoryExport() -> String {
        BodyHistoryCSV.export(bodyHistory())
    }

    /// What importing a history file would add: rows Nina already has (the same import key, or the
    /// same values on the same day) are left out. `cutoffMinutes`: the morning cutoff of the
    /// measuring routine (rows without conditions get morning and fasted before it).
    func bodyHistoryPlan(_ text: String, cutoffMinutes: Int, today: DayKey) -> BodyHistoryPlan {
        let keys = Set(measurements().map(\.importKey).filter { !$0.isEmpty })
        return BodyHistoryCSV.plan(text, existing: bodyHistory(), existingKeys: keys, cutoffMinutes: cutoffMinutes, today: today)
    }

    /// Adds the plan's weigh-ins and measurements in one save; returns them for Undo
    /// (`trash(weights)`, `trash(measurements)`). Measurements keep their row's import key.
    @discardableResult
    func importBodyHistory(_ plan: BodyHistoryPlan) -> (weights: [WeightEntry], measurements: [BodyMeasurement]) {
        var weights: [WeightEntry] = []
        var measurements: [BodyMeasurement] = []
        for record in plan.records {
            let time = record.day.date(minutes: record.minutes, calendar: calendar)
            guard let kind = record.kind.recordKind else {
                let entry = WeightEntry(day: record.day, time: time, kilograms: record.kilograms)
                entry.bodyFat = record.bodyFat
                entry.note = record.note
                context.insert(entry)
                weights.append(entry)
                continue
            }
            let draft = BodyMeasurementDraft(day: record.day, time: time, kind: kind, values: record.values, method: record.method,
                                             device: record.device, conditions: record.conditions, note: record.note)
            let measurement = BodyMeasurement(day: record.day, time: time, kind: kind, values: record.values)
            draft.write(to: measurement)
            measurement.importKey = record.importKey
            context.insert(measurement)
            measurements.append(measurement)
        }
        if !weights.isEmpty || !measurements.isEmpty { save() }
        return (weights, measurements)
    }
}
