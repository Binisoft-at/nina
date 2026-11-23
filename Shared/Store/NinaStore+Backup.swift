#if !os(watchOS)
import Foundation
import SwiftData
import BinisoftKit
import NinaCore

// "Back Up Everything" and "Restore from Backup" (NinaBackup in NinaCore): every synced model as
// backup records and back. Every stored attribute travels, with the uuid and the dates, so a
// restored record is the same record (links, plan keys and day marks stay intact). Apple Health
// values aren't in here: Nina never stores them, and the device-only Health ledger isn't a model.
// iPhone, iPad and Mac only (the watch has no photos and no backup).

extension NinaStore {
    // MARK: Writing a backup

    /// Writes the backup folder (manifest, records and – with `includePhotos` – the photos' JPEGs)
    /// at `folder`, which must not exist yet. Returns its manifest.
    @discardableResult
    func writeBackup(to folder: URL, includePhotos: Bool, appVersion: String, device: String, now: Date = Date()) throws -> NinaBackup.Manifest {
        try NinaBackupWriter(context: context).write(to: folder, records: backupRecords(), includePhotos: includePhotos,
                                                     appVersion: appVersion, device: device, now: now)
    }

    /// Every record but the photos, live and in Recently Deleted, the profile first.
    func backupRecords() -> [BackupRecord] {
        var records: [BackupRecord] = []
        if let profile = profile() { records.append(profile.backupRecord) }
        records += everyRecord(Food.self).map(\.backupRecord)
        records += everyRecord(Recipe.self).map(\.backupRecord)
        records += everyRecord(LogEntry.self).map(\.backupRecord)
        records += everyRecord(WaterLog.self).map(\.backupRecord)
        records += everyRecord(WeightEntry.self).map(\.backupRecord)
        records += everyRecord(PlanRule.self).map(\.backupRecord)
        records += everyRecord(BodyMeasurement.self).map(\.backupRecord)
        records += everyRecord(DayMark.self).map(\.backupRecord)
        return records
    }

    /// Every record of a model, live and in Recently Deleted.
    func everyRecord<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    // MARK: Restoring

    /// What Nina has, per type: uuid → last change (live and in Recently Deleted).
    func backupExisting() -> [BackupType: [UUID: Date]] {
        func stamps<T: PersistentModel>(_ type: T.Type, _ uuid: (T) -> UUID, _ modified: (T) -> Date) -> [UUID: Date] {
            var result: [UUID: Date] = [:]
            for record in everyRecord(type) { result[uuid(record)] = modified(record) }
            return result
        }
        return [
            .food: stamps(Food.self, \.uuid, \.modifiedAt),
            .recipe: stamps(Recipe.self, \.uuid, \.modifiedAt),
            .entry: stamps(LogEntry.self, \.uuid, \.modifiedAt),
            .water: stamps(WaterLog.self, \.uuid, \.modifiedAt),
            .weight: stamps(WeightEntry.self, \.uuid, \.modifiedAt),
            .rule: stamps(PlanRule.self, \.uuid, \.modifiedAt),
            .measurement: stamps(BodyMeasurement.self, \.uuid, \.modifiedAt),
            .mark: stamps(DayMark.self, \.uuid, \.modifiedAt),
            .photo: stamps(ProgressPhoto.self, \.uuid, \.modifiedAt),
        ]
    }

    /// Adds what the plan says is missing, with its uuid and dates, in one save. With
    /// `useBackupProfile` the backup's goals & plan replace Nina's. `photo` reads a photo's JPEGs
    /// (image, thumbnail) from the backup; a photo without its image is left out.
    func restoreBackup(_ plan: BackupRestorePlan, useBackupProfile: Bool,
                       photo: (BackupRecord) -> (image: Data?, thumbnail: Data?)) -> BackupRestoreUndo {
        var undo = BackupRestoreUndo()
        for record in plan.inserts {
            switch record.kind {
            case .food?: undo.add(insert(Food(record)))
            case .recipe?: undo.add(insertRecipe(record))
            case .entry?: undo.add(insert(LogEntry(record)))
            case .water?: undo.add(insert(WaterLog(record)))
            case .weight?: undo.add(insert(WeightEntry(record)))
            case .rule?: undo.add(insert(PlanRule(record)))
            case .measurement?: undo.add(insert(BodyMeasurement(record)))
            case .mark?: undo.add(insert(DayMark(record)))
            case .photo?:
                let data = photo(record)
                guard let image = data.image else {
                    undo.missingPhotos += 1
                    continue
                }
                let restored = ProgressPhoto(record)
                restored.image = image
                restored.thumbnail = data.thumbnail
                undo.add(insert(restored))
            case .profile?, nil:
                continue
            }
        }
        if let backup = plan.profile {
            if plan.profileState == .new {
                let profile = NinaProfile()
                profile.apply(backup: backup, keepIdentity: false)
                context.insert(profile)
                undo.insertedProfile = profile
            } else if plan.profileState == .differs, useBackupProfile, let profile = profile() {
                undo.profileBefore = SettingsImportUndo.Profile(profile)
                profile.apply(backup: backup, keepIdentity: true)
                profile.modifiedAt = Date()
            }
        }
        save()
        AppLog.info("Backup restored: \(undo.count) records added, \(undo.missingPhotos) photos missing", category: "backup")
        return undo
    }

    /// Puts back what a restore did: the added records go to Recently Deleted (records that came
    /// from the backup's Recently Deleted stay there), the goals & plan get their values back.
    func undo(_ restore: BackupRestoreUndo) {
        let now = Date()
        for record in restore.live { record.moveToTrash(now: now) }
        if let profile = restore.insertedProfile { context.delete(profile) }
        if let before = restore.profileBefore, let profile = profile() {
            before.write(to: profile)
            profile.modifiedAt = now
        }
        save()
    }

    private func insert<T: PersistentModel & SoftDeletable>(_ record: T) -> T {
        context.insert(record)
        return record
    }

    private func insertRecipe(_ record: BackupRecord) -> Recipe {
        let recipe = Recipe(record)
        context.insert(recipe)
        recipe.items = []
        for itemRecord in record.records("items") {
            let item = RecipeItem(itemRecord)
            item.recipe = recipe
            context.insert(item)
        }
        return recipe
    }
}

/// What a restore added, for its Undo.
struct BackupRestoreUndo {
    /// Added records that aren't in Recently Deleted (Undo moves them there).
    var live: [any SoftDeletable] = []
    /// How many records were added (live and from the backup's Recently Deleted).
    var count = 0
    var missingPhotos = 0
    /// The goals & plan, when Nina had none.
    var insertedProfile: NinaProfile?
    /// Nina's goals & plan before the backup's replaced them.
    var profileBefore: SettingsImportUndo.Profile?

    var isEmpty: Bool { count == 0 && insertedProfile == nil && profileBefore == nil }

    mutating func add(_ record: some SoftDeletable) {
        count += 1
        if record.deletedAt == nil { live.append(record) }
    }
}

/// Writes a backup from any model context: the main one (`NinaStore.writeBackup`), or a background
/// one made from the container (`ModelContext(container)`), so Back Up Everything and the
/// automatic weekly backup never hold up the app. It only reads: nothing is changed or saved.
struct NinaBackupWriter {
    let context: ModelContext

    /// Every record of a model, live and in Recently Deleted.
    func every<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    /// Every record but the photos, live and in Recently Deleted, the profile first.
    func records() -> [BackupRecord] {
        var records: [BackupRecord] = []
        if let profile = profileRecord() { records.append(profile) }
        records += every(Food.self).map(\.backupRecord)
        records += every(Recipe.self).map(\.backupRecord)
        records += every(LogEntry.self).map(\.backupRecord)
        records += every(WaterLog.self).map(\.backupRecord)
        records += every(WeightEntry.self).map(\.backupRecord)
        records += every(PlanRule.self).map(\.backupRecord)
        records += every(BodyMeasurement.self).map(\.backupRecord)
        records += every(DayMark.self).map(\.backupRecord)
        return records
    }

    /// The goals & plan: the oldest profile, as `NinaStore.profile()` keeps it, with the plan of a
    /// newer duplicate when the oldest has none (the store merges duplicates the same way; this
    /// only reads).
    func profileRecord() -> BackupRecord? {
        let all = (try? context.fetch(FetchDescriptor<NinaProfile>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        guard let first = all.first else { return nil }
        var record = first.backupRecord
        if first.coachPlan.isEmpty,
           let donor = all.dropFirst().filter({ !$0.coachPlan.isEmpty }).max(by: { $0.modifiedAt < $1.modifiedAt }) {
            let fields = donor.backupRecord
            for key in ["coachPlan", "targets", "trainingTargets", "trainingDays", "goal", "ratePerWeek", "targetWeight"] {
                record[key] = fields[key]
            }
        }
        // The settings for every device (Thalia's switch), from a newer duplicate when the oldest
        // has none – as the store merges them.
        if first.syncedSettings.isEmpty,
           let donor = all.dropFirst().filter({ !$0.syncedSettings.isEmpty }).max(by: { $0.modifiedAt < $1.modifiedAt }) {
            record.set("syncedSettings", donor.syncedSettings)
        }
        return record
    }

    /// Writes the backup folder (manifest, records and – with `includePhotos` – the photos' JPEGs)
    /// at `folder`, which must not exist yet. `records`: what `records()` gave, when the caller
    /// already has them. Returns its manifest.
    @discardableResult
    func write(to folder: URL, records given: [BackupRecord]? = nil, includePhotos: Bool, appVersion: String, device: String,
               now: Date = Date()) throws -> NinaBackup.Manifest {
        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        var records = given ?? self.records()
        var photoFiles = 0
        if includePhotos {
            try files.createDirectory(at: folder.appendingPathComponent(NinaBackup.photosFolder), withIntermediateDirectories: true)
            for photo in every(ProgressPhoto.self) {
                var record = photo.backupRecord
                if let image = photo.image {
                    let path = NinaBackup.photoPath(photo.uuid)
                    try image.write(to: folder.appendingPathComponent(path))
                    record.set("image", path)
                    photoFiles += 1
                }
                if let thumbnail = photo.thumbnail {
                    let path = NinaBackup.photoPath(photo.uuid, thumbnail: true)
                    try thumbnail.write(to: folder.appendingPathComponent(path))
                    record.set("thumbnail", path)
                }
                records.append(record)
            }
        }
        try NinaBackup.encode(records).write(to: folder.appendingPathComponent(NinaBackup.recordsName))
        let manifest = NinaBackup.Manifest(app: AppInfo.name, appVersion: appVersion, created: now, device: device,
                                           counts: NinaBackup.counts(records), photos: photoFiles)
        try NinaBackup.encode(manifest).write(to: folder.appendingPathComponent(NinaBackup.manifestName))
        AppLog.info("Backup written: \(records.count) records, \(photoFiles) photos", category: "backup")
        return manifest
    }
}

// MARK: - Models ↔ backup records

private extension BackupRecord {
    mutating func stamp(created: Date, modified: Date, deleted: Date?) {
        set("createdAt", date: created)
        set("modifiedAt", date: modified)
        set("deletedAt", date: deleted)
    }
}

/// The dates every restored record keeps.
private protocol BackupStamped: AnyObject {
    var createdAt: Date { get set }
    var modifiedAt: Date { get set }
}

private extension BackupStamped {
    func restoreDates(_ record: BackupRecord) {
        createdAt = record.createdAt ?? createdAt
        modifiedAt = record.modifiedAt ?? modifiedAt
    }
}

extension LogEntry: BackupStamped {}
extension Food: BackupStamped {}
extension Recipe: BackupStamped {}
extension WaterLog: BackupStamped {}
extension WeightEntry: BackupStamped {}
extension PlanRule: BackupStamped {}
extension BodyMeasurement: BackupStamped {}
extension DayMark: BackupStamped {}
extension ProgressPhoto: BackupStamped {}
extension NinaProfile: BackupStamped {}

/// The day of a record ("2030-01-07"), for the models' initialisers (the raw text is set after).
private func backupDay(_ record: BackupRecord) -> DayKey {
    DayKey(record.string("day")) ?? DayKey(date: record.date("time") ?? Date())
}

extension LogEntry {
    var backupRecord: BackupRecord {
        var r = BackupRecord(.entry, uuid: uuid)
        r.set("day", day)
        r.set("time", date: time)
        r.set("meal", meal)
        r.set("status", status)
        r.set("name", name)
        r.set("brand", brand)
        r.set("foodRef", foodRef)
        r.set("category", category)
        r.set("quantity", quantity)
        r.set("unitLabel", unitLabel)
        r.set("unitAmount", unitAmount)
        r.set("baseUnit", baseUnit)
        r.set("nutrients", nutrients)
        r.set("note", note)
        r.set("tags", tags)
        r.set("source", source)
        r.set("planKey", planKey)
        r.set("groupID", groupID)
        r.set("sortOrder", sortOrder)
        r.set("importKey", importKey)
        r.stamp(created: createdAt, modified: modifiedAt, deleted: deletedAt)
        return r
    }

    convenience init(_ r: BackupRecord) {
        self.init(day: backupDay(r), time: r.date("time") ?? Date(), meal: r.string("meal", "snack"), name: r.string("name"))
        uuid = r.uuid
        day = r.string("day", day)
        status = r.string("status", "eaten")
        brand = r.string("brand")
        foodRef = r.string("foodRef")
        category = r.string("category", "other")
        quantity = r.double("quantity", 1)
        unitLabel = r.string("unitLabel", "g")
        unitAmount = r.double("unitAmount", 1)
        baseUnit = r.string("baseUnit", "g")
        nutrients = r.string("nutrients")
        note = r.string("note")
        tags = r.string("tags")
        source = r.string("source")
        planKey = r.string("planKey")
        groupID = r.string("groupID")
        sortOrder = r.double("sortOrder")
        importKey = r.string("importKey")
        deletedAt = r.deletedAt
        restoreDates(r)
    }
}

extension Food {
    var backupRecord: BackupRecord {
        var r = BackupRecord(.food, uuid: uuid)
        r.set("catalogID", catalogID)
        r.set("name", name)
        r.set("nameDE", nameDE)
        r.set("brand", brand)
        r.set("category", category)
        r.set("unit", unit)
        r.set("density", density)
        r.set("nutrients", nutrients)
        r.set("servings", servings)
        r.set("aliases", aliases)
        r.set("barcode", barcode)
        r.set("tags", tags)
        r.set("notes", notes)
        r.set("isFavorite", isFavorite)
        r.set("isHidden", isHidden)
        r.set("source", source)
        r.set("usualAmount", usualAmount)
        r.set("importKey", importKey)
        r.stamp(created: createdAt, modified: modifiedAt, deleted: deletedAt)
        return r
    }

    convenience init(_ r: BackupRecord) {
        self.init(name: r.string("name"))
        uuid = r.uuid
        catalogID = r.string("catalogID")
        nameDE = r.string("nameDE")
        brand = r.string("brand")
        category = r.string("category", "other")
        unit = r.string("unit", "g")
        density = r.double("density", 1)
        nutrients = r.string("nutrients")
        servings = r.string("servings")
        aliases = r.string("aliases")
        barcode = r.string("barcode")
        tags = r.string("tags")
        notes = r.string("notes")
        isFavorite = r.bool("isFavorite")
        isHidden = r.bool("isHidden")
        source = r.string("source", "custom")
        usualAmount = r.double("usualAmount")
        importKey = r.string("importKey")
        deletedAt = r.deletedAt
        restoreDates(r)
    }
}

extension Recipe {
    var backupRecord: BackupRecord {
        var r = BackupRecord(.recipe, uuid: uuid)
        r.set("name", name)
        r.set("kind", kind)
        r.set("emoji", emoji)
        r.set("notes", notes)
        r.set("tags", tags)
        r.set("servings", servings)
        r.set("totalWeight", totalWeight)
        r.set("defaultMeal", defaultMeal)
        r.set("isFavorite", isFavorite)
        r.set("sortOrder", sortOrder)
        r.set("lastUsedAt", date: lastUsedAt)
        r.set("importKey", importKey)
        r.set("items", sortedItems.map(\.backupRecord))
        r.stamp(created: createdAt, modified: modifiedAt, deleted: deletedAt)
        return r
    }

    convenience init(_ r: BackupRecord) {
        self.init(name: r.string("name"), kind: RecipeKind(rawValue: r.string("kind")) ?? .meal)
        uuid = r.uuid
        kind = r.string("kind", "meal")
        emoji = r.string("emoji")
        notes = r.string("notes")
        tags = r.string("tags")
        servings = r.double("servings", 1)
        totalWeight = r.double("totalWeight")
        defaultMeal = r.string("defaultMeal")
        isFavorite = r.bool("isFavorite")
        sortOrder = r.double("sortOrder")
        lastUsedAt = r.date("lastUsedAt")
        importKey = r.string("importKey")
        deletedAt = r.deletedAt
        restoreDates(r)
    }
}

extension RecipeItem {
    var backupRecord: BackupRecord {
        var r = BackupRecord(type: "RecipeItem", uuid: uuid)
        r.set("name", name)
        r.set("brand", brand)
        r.set("foodRef", foodRef)
        r.set("category", category)
        r.set("quantity", quantity)
        r.set("unitLabel", unitLabel)
        r.set("unitAmount", unitAmount)
        r.set("baseUnit", baseUnit)
        r.set("nutrients", nutrients)
        r.set("sortOrder", sortOrder)
        return r
    }

    convenience init(_ r: BackupRecord) {
        self.init(name: r.string("name"))
        uuid = r.uuid
        brand = r.string("brand")
        foodRef = r.string("foodRef")
        category = r.string("category", "other")
        quantity = r.double("quantity", 1)
        unitLabel = r.string("unitLabel", "g")
        unitAmount = r.double("unitAmount", 1)
        baseUnit = r.string("baseUnit", "g")
        nutrients = r.string("nutrients")
        sortOrder = r.double("sortOrder")
    }
}

extension WaterLog {
    var backupRecord: BackupRecord {
        var r = BackupRecord(.water, uuid: uuid)
        r.set("day", day)
        r.set("time", date: time)
        r.set("amount", amount)
        r.stamp(created: createdAt, modified: modifiedAt, deleted: deletedAt)
        return r
    }

    convenience init(_ r: BackupRecord) {
        self.init(day: backupDay(r), time: r.date("time") ?? Date(), amount: r.double("amount"))
        uuid = r.uuid
        day = r.string("day", day)
        deletedAt = r.deletedAt
        restoreDates(r)
    }
}

extension WeightEntry {
    var backupRecord: BackupRecord {
        var r = BackupRecord(.weight, uuid: uuid)
        r.set("day", day)
        r.set("time", date: time)
        r.set("kilograms", kilograms)
        r.set("bodyFat", bodyFat)
        r.set("note", note)
        r.stamp(created: createdAt, modified: modifiedAt, deleted: deletedAt)
        return r
    }

    convenience init(_ r: BackupRecord) {
        self.init(day: backupDay(r), time: r.date("time") ?? Date(), kilograms: r.double("kilograms"))
        uuid = r.uuid
        day = r.string("day", day)
        bodyFat = r.double("bodyFat")
        note = r.string("note")
        deletedAt = r.deletedAt
        restoreDates(r)
    }
}

extension PlanRule {
    var backupRecord: BackupRecord {
        var r = BackupRecord(.rule, uuid: uuid)
        r.set("recipeID", recipeID)
        r.set("title", title)
        r.set("meal", meal)
        r.set("minutes", minutes)
        r.set("weekdays", weekdays)
        r.set("isActive", isActive)
        r.set("notify", notify)
        r.set("startDay", startDay)
        r.set("endDay", endDay)
        r.stamp(created: createdAt, modified: modifiedAt, deleted: deletedAt)
        return r
    }

    convenience init(_ r: BackupRecord) {
        self.init(recipeID: r.uuidValue("recipeID") ?? UUID(), title: r.string("title"), meal: r.string("meal", "breakfast"),
                  minutes: r.int("minutes", 450), weekdays: Weekdays(encoded: r.string("weekdays", "1,2,3,4,5,6,7")))
        uuid = r.uuid
        recipeID = r.string("recipeID", recipeID)
        weekdays = r.string("weekdays", weekdays)
        isActive = r.bool("isActive", true)
        notify = r.bool("notify", true)
        startDay = r.string("startDay")
        endDay = r.string("endDay")
        deletedAt = r.deletedAt
        restoreDates(r)
    }
}

extension BodyMeasurement {
    var backupRecord: BackupRecord {
        var r = BackupRecord(.measurement, uuid: uuid)
        r.set("day", day)
        r.set("time", date: time)
        r.set("kind", kind)
        r.set("values", values)
        r.set("method", method)
        r.set("device", device)
        r.set("conditions", conditions)
        r.set("note", note)
        r.set("importKey", importKey)
        r.stamp(created: createdAt, modified: modifiedAt, deleted: deletedAt)
        return r
    }

    convenience init(_ r: BackupRecord) {
        self.init(day: backupDay(r), time: r.date("time") ?? Date(), kind: BodyRecordKind(rawValue: r.string("kind")) ?? .tape,
                  values: BodyValues(encoded: r.string("values")))
        uuid = r.uuid
        day = r.string("day", day)
        kind = r.string("kind", kind)
        values = r.string("values")
        method = r.string("method")
        device = r.string("device")
        conditions = r.string("conditions")
        note = r.string("note")
        importKey = r.string("importKey")
        deletedAt = r.deletedAt
        restoreDates(r)
    }
}

extension DayMark {
    var backupRecord: BackupRecord {
        var r = BackupRecord(.mark, uuid: uuid)
        r.set("day", day)
        r.set("time", date: time)
        r.set("kind", kind)
        r.set("key", key)
        r.set("values", values)
        r.set("meta", meta)
        r.set("note", note)
        r.set("importKey", importKey)
        r.stamp(created: createdAt, modified: modifiedAt, deleted: deletedAt)
        return r
    }

    convenience init(_ r: BackupRecord) {
        self.init(day: backupDay(r), kind: DayMarkKind(rawValue: r.string("kind")) ?? .event, key: r.string("key"),
                  time: r.date("time") ?? Date())
        uuid = r.uuid
        day = r.string("day", day)
        kind = r.string("kind", kind)
        values = r.string("values")
        meta = r.string("meta")
        note = r.string("note")
        importKey = r.string("importKey")
        deletedAt = r.deletedAt
        restoreDates(r)
    }
}

extension ProgressPhoto {
    /// Without the JPEGs: `writeBackup` adds their paths when it writes them.
    var backupRecord: BackupRecord {
        var r = BackupRecord(.photo, uuid: uuid)
        r.set("day", day)
        r.set("time", date: time)
        r.set("pose", pose)
        r.set("note", note)
        r.set("measurementID", measurementID)
        r.stamp(created: createdAt, modified: modifiedAt, deleted: deletedAt)
        return r
    }

    convenience init(_ r: BackupRecord) {
        self.init(day: backupDay(r), time: r.date("time") ?? Date(), pose: PhotoPose(rawValue: r.string("pose")) ?? .front)
        uuid = r.uuid
        day = r.string("day", day)
        pose = r.string("pose", pose)
        note = r.string("note")
        measurementID = r.string("measurementID")
        deletedAt = r.deletedAt
        restoreDates(r)
    }
}

extension NinaProfile {
    var backupRecord: BackupRecord {
        var r = BackupRecord(.profile, uuid: uuid)
        r.set("targets", targets)
        r.set("trainingTargets", trainingTargets)
        r.set("trainingDays", trainingDays)
        r.set("meals", meals)
        r.set("sex", sex)
        r.set("birthYear", birthYear)
        r.set("heightCm", heightCm)
        r.set("activity", activity)
        r.set("goal", goal)
        r.set("ratePerWeek", ratePerWeek)
        r.set("targetWeight", targetWeight)
        r.set("macroSplit", macroSplit)
        r.set("foodLanguage", foodLanguage)
        r.set("energyUnit", energyUnit)
        r.set("dayStartHour", dayStartHour)
        r.set("activityBonusShare", activityBonusShare)
        r.set("focusNutrients", focusNutrients)
        r.set("waterGlass", waterGlass)
        r.set("coachPlan", coachPlan)
        // Only when there is one: a backup from before this field reads the same as a profile
        // without synced settings (the restore's "same goals & plan" check compares every field).
        if !syncedSettings.isEmpty { r.set("syncedSettings", syncedSettings) }
        r.set("createdAt", date: createdAt)
        r.set("modifiedAt", date: modifiedAt)
        return r
    }

    /// The backup's goals, preferences and plan. `keepIdentity`: an existing profile keeps its uuid
    /// and creation date (it replaces values, not the record).
    func apply(backup r: BackupRecord, keepIdentity: Bool) {
        if !keepIdentity {
            uuid = r.uuid
            restoreDates(r)
        }
        targets = r.string("targets", targets)
        trainingTargets = r.string("trainingTargets")
        trainingDays = r.string("trainingDays")
        meals = r.string("meals", meals)
        sex = r.string("sex", "unspecified")
        birthYear = r.int("birthYear")
        heightCm = r.double("heightCm")
        activity = r.string("activity", "light")
        goal = r.string("goal", "maintain")
        ratePerWeek = r.double("ratePerWeek", 0.5)
        targetWeight = r.double("targetWeight")
        macroSplit = r.string("macroSplit", "balanced")
        foodLanguage = r.string("foodLanguage")
        energyUnit = r.string("energyUnit", "kcal")
        dayStartHour = r.int("dayStartHour")
        activityBonusShare = r.double("activityBonusShare")
        focusNutrients = r.string("focusNutrients", "protein,carbs,fat")
        waterGlass = r.double("waterGlass", 250)
        coachPlan = r.string("coachPlan")
        // Thalia's switch and the other settings for every device (lenient JSON, read by
        // `SyncedSettings`). A backup from before them leaves what is here: empty on a new profile.
        syncedSettings = r.string("syncedSettings", syncedSettings)
    }
}
#endif
