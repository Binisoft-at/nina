import Foundation
import SwiftData
import BinisoftKit
import NinaCore

// Progress photos in the store and the actions with an Undo toast. App only: the watch's store has
// no photos (Persistence.models). Every write goes through NinaStore; deleting is soft (30 days).

extension ProgressPhoto {
    var dayKey: DayKey { DayKey(day) ?? DayKey(date: time) }
    var photoPose: PhotoPose { PhotoPose(stored: pose) }
    /// The photo as the NinaCore logic sees it (no image data).
    var record: PhotoRecord { PhotoRecord(id: uuid, day: dayKey, time: time, pose: photoPose) }
}

/// A photo ready to save: the processed JPEG and its thumbnail (BodyPhotoImages).
struct BodyPhotoDraft: Identifiable {
    let id = UUID()
    var pose: PhotoPose
    var image: Data
    var thumbnail: Data
    /// When the picked photo was taken (its EXIF date); nil for the camera.
    var capturedAt: Date?
}

extension NinaStore {
    /// Every live progress photo, oldest first.
    func progressPhotos() -> [ProgressPhoto] {
        let descriptor = FetchDescriptor<ProgressPhoto>(
            predicate: #Predicate<ProgressPhoto> { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.day), SortDescriptor(\.time)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// The photos in the trash, the newest deletion first.
    func trashedPhotos() -> [ProgressPhoto] {
        let descriptor = FetchDescriptor<ProgressPhoto>(
            predicate: #Predicate<ProgressPhoto> { $0.deletedAt != nil },
            sortBy: [SortDescriptor(\.deletedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func progressPhoto(_ id: UUID) -> ProgressPhoto? {
        let descriptor = FetchDescriptor<ProgressPhoto>(predicate: #Predicate<ProgressPhoto> { $0.uuid == id })
        return try? context.fetch(descriptor).first
    }

    /// Adds a session's photos with one day, time and note, linked to the measurement taken with
    /// them (Undo: `trash(photos)`). In pose order a second apart, so the newest of a day is clear.
    @discardableResult
    func addPhotos(_ drafts: [BodyPhotoDraft], day: DayKey, time: Date, note: String, measurementID: UUID? = nil) -> [ProgressPhoto] {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let ordered = drafts.sorted { $0.pose.order < $1.pose.order }
        var added: [ProgressPhoto] = []
        for (index, draft) in ordered.enumerated() {
            let photo = ProgressPhoto(day: day, time: time.addingTimeInterval(Double(index)), pose: draft.pose)
            photo.image = draft.image
            photo.thumbnail = draft.thumbnail
            photo.note = text
            photo.measurementID = measurementID?.uuidString ?? ""
            context.insert(photo)
            added.append(photo)
        }
        guard !added.isEmpty else { return [] }
        save()
        return added
    }

    /// Changes a photo's pose and note; returns the values before (Undo: the same call with them).
    @discardableResult
    func updatePhoto(_ photo: ProgressPhoto, pose: PhotoPose, note: String) -> (pose: PhotoPose, note: String) {
        let previous = (pose: photo.photoPose, note: photo.note)
        photo.pose = pose.rawValue
        photo.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        photo.touch()
        save()
        return previous
    }
}

extension AppModel {
    /// Saves a session's photos with an Undo toast ("3 photos saved").
    @discardableResult
    func savePhotos(_ drafts: [BodyPhotoDraft], day: DayKey, time: Date, note: String, measurementID: UUID? = nil) -> [ProgressPhoto] {
        let added = store.addPhotos(drafts, day: day, time: time, note: note, measurementID: measurementID)
        guard !added.isEmpty else { return [] }
        let message = added.count == 1 ? "Photo saved" : "\(added.count) photos saved"
        toasts.show(message, symbol: "camera.fill") { [weak self] in
            _ = self?.store.trash(added)
        }
        return added
    }

    /// Deletes a photo (30-day trash) with Undo.
    func trashPhoto(_ photo: ProgressPhoto) {
        let trashed = store.trash([photo])
        toasts.show("Photo deleted", symbol: "trash.fill") { [weak self] in
            self?.store.restore(trashed)
        }
    }

    /// A new pose or note with Undo.
    func updatePhoto(_ photo: ProgressPhoto, pose: PhotoPose, note: String) {
        let previous = store.updatePhoto(photo, pose: pose, note: note)
        let message = previous.pose != pose ? "Moved to \(pose.title)" : "Note saved"
        toasts.show(message, symbol: "checkmark.circle.fill") { [weak self] in
            _ = self?.store.updatePhoto(photo, pose: previous.pose, note: previous.note)
        }
    }
}
