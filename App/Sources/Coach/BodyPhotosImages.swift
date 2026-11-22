import SwiftUI
import SwiftData
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import NinaCore

// Progress photo images with ImageIO (the same code on iPhone, iPad and Mac): a picked or taken
// photo is turned upright, downscaled to 2048 px on the long side and saved as JPEG (quality 0.8)
// with a 360 px thumbnail. Writing a new image leaves the location, camera and other metadata
// behind. Reading files and stored photos, encoding and decoding run off the main thread.

/// A decoded image (a class, so NSCache can hold it and tasks can hand it over).
final class BodyPhotoBitmap: @unchecked Sendable {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}

enum BodyPhotoImages {
    /// What a photo session keeps until Save.
    struct Processed: Sendable {
        let image: Data
        let thumbnail: Data
        /// When the photo was taken (EXIF), if it says.
        let capturedAt: Date?
    }

    /// Decoded images by key ("<uuid>-thumb", "<uuid>-full-<pixels>"), at most about 150 MB (a
    /// 2048 px photo takes about 12 MB decoded, a thumbnail about half a MB); the system empties it
    /// when memory is short.
    static let cache: NSCache<NSString, BodyPhotoBitmap> = {
        let cache = NSCache<NSString, BodyPhotoBitmap>()
        cache.countLimit = 120
        cache.totalCostLimit = 150 * 1024 * 1024
        return cache
    }()

    /// The memory a decoded image takes (what the cache counts).
    static func cost(_ bitmap: BodyPhotoBitmap) -> Int {
        bitmap.image.bytesPerRow * bitmap.image.height
    }

    // MARK: Reading

    /// A chosen file (the Mac's "Choose File…"), read off the main thread.
    static func read(_ url: URL) async -> Data? {
        let task = Task.detached(priority: .userInitiated) { () -> Data? in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            return try? Data(contentsOf: url)
        }
        return await task.value
    }

    /// A stored photo's JPEG (external storage, up to about 1 MB), read off the main thread in a
    /// context of its own; nil when it isn't there (not saved yet, or no image).
    static func storedImage(of id: UUID, in container: ModelContainer) async -> Data? {
        let task = Task.detached(priority: .userInitiated) { () -> Data? in
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<ProgressPhoto>(predicate: #Predicate<ProgressPhoto> { $0.uuid == id })
            descriptor.fetchLimit = 1
            return (try? context.fetch(descriptor))?.first?.image
        }
        return await task.value
    }

    // MARK: Saving

    /// A picked or taken photo (JPEG, HEIC, PNG …) ready to save; nil when it isn't an image.
    static func process(_ data: Data) async -> Processed? {
        let task = Task.detached(priority: .userInitiated) { () -> Processed? in
            processNow(data)
        }
        return await task.value
    }

    static func processNow(_ data: Data) -> Processed? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let full = downscaled(source, maxPixels: ProgressPhotos.fullPixels),
              let image = jpeg(full, quality: ProgressPhotos.fullQuality),
              let small = CGImageSourceCreateWithData(image as CFData, nil),
              let thumb = downscaled(small, maxPixels: ProgressPhotos.thumbnailPixels),
              let thumbnail = jpeg(thumb, quality: ProgressPhotos.thumbnailQuality) else { return nil }
        return Processed(image: image, thumbnail: thumbnail, capturedAt: captureDate(source))
    }

    /// An upright image at most `maxPixels` on the long side (the EXIF orientation applied).
    static func downscaled(_ source: CGImageSource, maxPixels: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// JPEG without metadata.
    static func jpeg(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// The EXIF capture time ("2030:01:07 07:12:30"), else the TIFF date.
    static func captureDate(_ source: CGImageSource) -> Date? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let original = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
        let text = original ?? (tiff?[kCGImagePropertyTIFFDateTime] as? String)
        guard let text else { return nil }
        return ProgressPhotos.exifDate(text)
    }

    // MARK: Showing

    /// A stored JPEG decoded for display (at most `maxPixels` on the long side when given).
    static func decode(_ data: Data, maxPixels: Int? = nil) async -> BodyPhotoBitmap? {
        let task = Task.detached(priority: .userInitiated) { () -> BodyPhotoBitmap? in
            decodeNow(data, maxPixels: maxPixels)
        }
        return await task.value
    }

    static func decodeNow(_ data: Data, maxPixels: Int? = nil) -> BodyPhotoBitmap? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        if let maxPixels {
            return downscaled(source, maxPixels: maxPixels).map { BodyPhotoBitmap($0) }
        }
        let options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary).map { BodyPhotoBitmap($0) }
    }

    /// From the cache, else decoded and cached.
    static func bitmap(_ data: Data, key: String, maxPixels: Int? = nil) async -> BodyPhotoBitmap? {
        if let cached = cache.object(forKey: key as NSString) { return cached }
        guard let decoded = await decode(data, maxPixels: maxPixels) else { return nil }
        cache.setObject(decoded, forKey: key as NSString, cost: cost(decoded))
        return decoded
    }
}

/// Which image of a stored photo to show.
enum BodyPhotoSize {
    /// The 360 px thumbnail.
    case thumbnail
    /// The stored photo, decoded at most this many pixels on the long side.
    case full(Int)
}

/// A stored photo's image, read and decoded off the main thread (a soft tile until then).
struct BodyPhotoImageView: View {
    let photo: ProgressPhoto
    var size: BodyPhotoSize = .thumbnail
    var contentMode: ContentMode = .fill
    @Environment(\.modelContext) private var modelContext
    @State private var bitmap: BodyPhotoBitmap?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
            if let bitmap {
                Image(decorative: bitmap.image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }
        }
        .task(id: key) { await load() }
        .accessibilityLabel("\(photo.photoPose.title) photo, \(Fmt.shortDay(photo.dayKey))")
    }

    private var key: String {
        switch size {
        case .thumbnail: photo.uuid.uuidString + "-thumb"
        case .full(let pixels): photo.uuid.uuidString + "-full-\(pixels)"
        }
    }

    private func load() async {
        let key = self.key
        if let cached = BodyPhotoImages.cache.object(forKey: key as NSString) {
            bitmap = cached
            return
        }
        switch size {
        case .thumbnail:
            // The small thumbnail is read here; the photo itself only when there is none.
            if let thumb = photo.thumbnail {
                bitmap = await BodyPhotoImages.bitmap(thumb, key: key, maxPixels: ProgressPhotos.thumbnailPixels)
            } else if let data = await storedImage() {
                bitmap = await BodyPhotoImages.bitmap(data, key: key, maxPixels: ProgressPhotos.thumbnailPixels)
            }
        case .full(let pixels):
            // The thumbnail first, so the photo shows at once.
            if bitmap == nil, let thumb = photo.thumbnail {
                bitmap = await BodyPhotoImages.bitmap(thumb, key: photo.uuid.uuidString + "-thumb",
                                                      maxPixels: ProgressPhotos.thumbnailPixels)
            }
            guard let data = await storedImage() else { return }
            if let full = await BodyPhotoImages.bitmap(data, key: key, maxPixels: pixels) { bitmap = full }
        }
    }

    /// The photo's JPEG, read off the main thread; here only when that finds nothing (not saved yet).
    private func storedImage() async -> Data? {
        if let data = await BodyPhotoImages.storedImage(of: photo.uuid, in: modelContext.container) { return data }
        return photo.image
    }
}

/// A photo of the running session (not saved yet), from its processed JPEG.
struct BodyPhotoDraftImage: View {
    let draft: BodyPhotoDraft
    var contentMode: ContentMode = .fit
    @State private var bitmap: BodyPhotoBitmap?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
            if let bitmap {
                Image(decorative: bitmap.image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }
        }
        .task(id: draft.id) {
            bitmap = await BodyPhotoImages.decode(draft.image, maxPixels: 1400)
        }
    }
}
