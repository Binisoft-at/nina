import Foundation
import SwiftData
import BinisoftKit
import NinaCore

// Nina's synced data (private database of iCloud.at.binisoft.nina).
//
// CloudKit rules: every attribute has a default, relationships are optional with an inverse,
// nothing is unique. New fields are optional or have a default (older builds keep working), and
// cloudkit/schema.ckdb gets the same field before the next TestFlight build. Enum-like values are
// stored as raw strings, nutrients as one text field ("energy=52;protein=0.3"), so adding a
// nutrient or a category never needs a schema change.

/// One thing eaten (or planned) on a day. Nutrients are the totals of this entry, copied when it
/// was logged – editing a food later never rewrites history.
@Model
final class LogEntry {
    var uuid: UUID = UUID()
    /// The day it counts for, "2026-11-13" (see DayKey).
    var day: String = ""
    /// When it was eaten, or is planned.
    var time: Date = Date()
    /// Meal slot id: breakfast, lunch, dinner, snack or an own meal's id.
    var meal: String = "snack"
    /// eaten · planned · skipped
    var status: String = "eaten"
    var name: String = ""
    var brand: String = ""
    /// usda:… / nina:… / food:<uuid> / recipe:<uuid>; empty for quick entries.
    var foodRef: String = ""
    var category: String = "other"
    /// How it was entered: 2 × "slice" of 30 g, or 150 × "g" of 1 g.
    var quantity: Double = 1
    var unitLabel: String = "g"
    var unitAmount: Double = 1
    /// g · ml · serving
    var baseUnit: String = "g"
    /// Totals for this entry (NutrientValues.encoded).
    var nutrients: String = ""
    var note: String = ""
    /// Own labels, "|"-separated.
    var tags: String = ""
    /// search · quick · barcode · plan · watch · import · copy · recipe · shortcut
    var source: String = ""
    /// Set on entries created from a plan rule: "rule:<uuid>:<day>".
    var planKey: String = ""
    /// Entries logged together (a saved meal) share a group id.
    var groupID: String = ""
    var sortOrder: Double = 0
    var importKey: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var deletedAt: Date?

    init(day: DayKey, time: Date, meal: String, name: String) {
        let now = Date()
        self.uuid = UUID()
        self.day = day.rawValue
        self.time = time
        self.meal = meal
        self.name = name
        self.createdAt = now
        self.modifiedAt = now
    }
}

/// A food the person created, imported, scanned – or a catalog food they personalised
/// (`catalogID` set: favourite, tags, own portions or corrected values).
@Model
final class Food {
    var uuid: UUID = UUID()
    var catalogID: String = ""
    var name: String = ""
    var nameDE: String = ""
    var brand: String = ""
    var category: String = "other"
    /// g · ml · serving
    var unit: String = "g"
    var density: Double = 1
    /// Per 100 g / 100 ml (NutrientValues.encoded).
    var nutrients: String = ""
    /// Household portions (Serving.encode).
    var servings: String = ""
    var aliases: String = ""
    var barcode: String = ""
    var tags: String = ""
    var notes: String = ""
    var isFavorite: Bool = false
    /// A catalog food the person doesn't want in search results.
    var isHidden: Bool = false
    /// custom · import · barcode · catalog
    var source: String = "custom"
    var usualAmount: Double = 0
    var importKey: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var deletedAt: Date?

    init(name: String) {
        let now = Date()
        self.uuid = UUID()
        self.name = name
        self.createdAt = now
        self.modifiedAt = now
    }
}

/// A saved meal (logged as its foods) or a recipe (logged by portion or weight).
@Model
final class Recipe {
    var uuid: UUID = UUID()
    var name: String = ""
    /// meal · recipe
    var kind: String = "meal"
    var emoji: String = ""
    var notes: String = ""
    var tags: String = ""
    var servings: Double = 1
    /// Cooked weight in g (0 = sum of the ingredients).
    var totalWeight: Double = 0
    /// Meal slot it is usually eaten at ("" = any).
    var defaultMeal: String = ""
    var isFavorite: Bool = false
    var sortOrder: Double = 0
    var lastUsedAt: Date?
    var importKey: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var deletedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \RecipeItem.recipe)
    var items: [RecipeItem]? = []

    init(name: String, kind: RecipeKind) {
        let now = Date()
        self.uuid = UUID()
        self.name = name
        self.kind = kind.rawValue
        self.createdAt = now
        self.modifiedAt = now
    }
}

/// One food of a saved meal or recipe, with the totals of its amount.
@Model
final class RecipeItem {
    var uuid: UUID = UUID()
    var name: String = ""
    var brand: String = ""
    var foodRef: String = ""
    var category: String = "other"
    var quantity: Double = 1
    var unitLabel: String = "g"
    var unitAmount: Double = 1
    var baseUnit: String = "g"
    var nutrients: String = ""
    var sortOrder: Double = 0
    var recipe: Recipe?

    init(name: String) {
        self.uuid = UUID()
        self.name = name
    }
}

/// Water (and other plain drinks counted as water), in ml.
@Model
final class WaterLog {
    var uuid: UUID = UUID()
    var day: String = ""
    var time: Date = Date()
    var amount: Double = 0
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var deletedAt: Date?

    init(day: DayKey, time: Date, amount: Double) {
        let now = Date()
        self.uuid = UUID()
        self.day = day.rawValue
        self.time = time
        self.amount = amount
        self.createdAt = now
        self.modifiedAt = now
    }
}

/// A weigh-in typed into Nina (weights from Apple Health are read live and never stored here).
@Model
final class WeightEntry {
    var uuid: UUID = UUID()
    var day: String = ""
    var time: Date = Date()
    var kilograms: Double = 0
    /// Percent, 0 = not measured.
    var bodyFat: Double = 0
    var note: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var deletedAt: Date?

    init(day: DayKey, time: Date, kilograms: Double) {
        let now = Date()
        self.uuid = UUID()
        self.day = day.rawValue
        self.time = time
        self.kilograms = kilograms
        self.createdAt = now
        self.modifiedAt = now
    }
}

/// "My usual breakfast, Mon–Fri at 07:30": creates planned entries for the next days, which
/// are confirmed with one tap (or from the notification).
@Model
final class PlanRule {
    var uuid: UUID = UUID()
    /// The saved meal or recipe it plans.
    var recipeID: String = ""
    var title: String = ""
    var meal: String = "breakfast"
    /// Minutes after midnight.
    var minutes: Int = 450
    /// ISO weekdays "1,2,3,4,5".
    var weekdays: String = "1,2,3,4,5,6,7"
    var isActive: Bool = true
    /// Remind to confirm at the planned time.
    var notify: Bool = true
    var startDay: String = ""
    var endDay: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var deletedAt: Date?

    init(recipeID: UUID, title: String, meal: String, minutes: Int, weekdays: Weekdays) {
        let now = Date()
        self.uuid = UUID()
        self.recipeID = recipeID.uuidString
        self.title = title
        self.meal = meal
        self.minutes = minutes
        self.weekdays = weekdays.encoded
        self.createdAt = now
        self.modifiedAt = now
    }
}

/// Goals and preferences that follow the person to every device. There is one; if two devices
/// each created one before they synced, the newest wins (`NinaStore.profile()`).
@Model
final class NinaProfile {
    var uuid: UUID = UUID()
    /// DailyTargets.encoded
    var targets: String = ""
    /// Second set for training days ("" = off).
    var trainingTargets: String = ""
    /// Weekdays the training targets apply to, "1,3,5".
    var trainingDays: String = ""
    /// MealSlot.encode
    var meals: String = ""
    var sex: String = "unspecified"
    var birthYear: Int = 0
    var heightCm: Double = 0
    var activity: String = "light"
    var goal: String = "maintain"
    var ratePerWeek: Double = 0.5
    var targetWeight: Double = 0
    var macroSplit: String = "balanced"
    /// "" = the device language.
    var foodLanguage: String = ""
    var energyUnit: String = "kcal"
    /// Hour the diary day starts (0 = midnight; 3 = a 2 am snack still counts for yesterday).
    var dayStartHour: Int = 0
    /// Share of Apple Health active energy added to the daily budget (0, 0.5 or 1).
    var activityBonusShare: Double = 0
    /// Nutrients shown first everywhere (the person's priorities), "protein,carbs,fat".
    var focusNutrients: String = "protein,carbs,fat"
    var waterGlass: Double = 250
    /// CoachPlan JSON ("" = no plan).
    var coachPlan: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    init() {
        let now = Date()
        self.uuid = UUID()
        self.targets = DailyTargets.standard.encoded
        self.meals = MealSlot.encode(MealSlot.defaults)
        self.createdAt = now
        self.modifiedAt = now
    }
}

/// A body measurement typed into Nina: tape values in cm or a body-fat assessment (values from
/// Apple Health are read live and never stored here). Navy body fat is computed live, never stored.
@Model
final class BodyMeasurement {
    var uuid: UUID = UUID()
    var day: String = ""
    var time: Date = Date()
    /// "tape" | "assessment"
    var kind: String = "tape"
    /// BodyValues k=v, cm or kg/%: "waist=84.0;chest=101.5;arm=34.5"
    /// assessments: "bodyFat=20;leanKg=64;fatKg=16;boneKg=3.1;sf_chest=12"
    var values: String = ""
    /// assessments: dexa|bodpod|bia_pro|scale|skinfold|estimate
    var method: String = ""
    /// e.g. "InBody 570": separates BIA series
    var device: String = ""
    /// comma tags: "morning,fasted" or "after_training,high_salt"
    var conditions: String = ""
    var note: String = ""
    var importKey: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var deletedAt: Date?

    init(day: DayKey, time: Date, kind: BodyRecordKind, values: BodyValues) {
        let now = Date()
        self.uuid = UUID()
        self.day = day.rawValue
        self.time = time
        self.kind = kind.rawValue
        self.values = values.encoded
        self.createdAt = now
        self.modifiedAt = now
    }
}

/// A small record for a day: the day type picked by hand, a ticked daily check, a weekly check-in,
/// a phase decision or a day event (see DayMarkKind).
@Model
final class DayMark {
    var uuid: UUID = UUID()
    var day: String = ""
    var time: Date = Date()
    /// "dayType" | "check" | "checkIn" | "phase" | "event"
    var kind: String = ""
    /// day-type id | check id | "week-2030-01-07" | phase id | event name
    var key: String = ""
    /// numbers k=v (like NutrientValues.encoded)
    var values: String = ""
    /// text k=v: "state=done", "verdict=slower;applied=yes;phase=1"
    var meta: String = ""
    var note: String = ""
    var importKey: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var deletedAt: Date?

    init(day: DayKey, kind: DayMarkKind, key: String, time: Date = Date()) {
        let now = Date()
        self.uuid = UUID()
        self.day = day.rawValue
        self.time = time
        self.kind = kind.rawValue
        self.key = key
        self.createdAt = now
        self.modifiedAt = now
    }
}

/// A progress photo (front, side or back), taken or picked in Nina. The image and its thumbnail
/// are JPEG files kept outside the database (CloudKit assets), synced only to the person's own
/// iCloud. Not part of the watch's store (Persistence.models).
@Model
final class ProgressPhoto {
    var uuid: UUID = UUID()
    var day: String = ""
    var time: Date = Date()
    /// "front" | "side" | "back" | "other" (PhotoPose)
    var pose: String = "front"
    /// JPEG, at most 2048 px on the long side, without location or camera metadata.
    @Attribute(.externalStorage) var image: Data?
    /// JPEG, about 360 px on the long side (the Body card and lists).
    @Attribute(.externalStorage) var thumbnail: Data?
    var note: String = ""
    /// The BodyMeasurement (uuid text) of the same session, "" = none.
    var measurementID: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var deletedAt: Date?

    init(day: DayKey, time: Date, pose: PhotoPose) {
        let now = Date()
        self.uuid = UUID()
        self.day = day.rawValue
        self.time = time
        self.pose = pose.rawValue
        self.createdAt = now
        self.modifiedAt = now
    }
}

extension LogEntry: SoftDeletable {}
extension Food: SoftDeletable {}
extension Recipe: SoftDeletable {}
extension WaterLog: SoftDeletable {}
extension WeightEntry: SoftDeletable {}
extension PlanRule: SoftDeletable {}
extension BodyMeasurement: SoftDeletable {}
extension DayMark: SoftDeletable {}
extension ProgressPhoto: SoftDeletable {}
