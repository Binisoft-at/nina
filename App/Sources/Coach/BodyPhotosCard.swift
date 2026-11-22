import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

// Progress photos on the body page: the Photos card (the latest front, side and back photos with
// their dates, Take Photos, Compare, all photos), the sheets (`AppSheet.photos`) and the viewer.
// Photos sync through Nina's private iCloud only; Face ID can lock them on a device.

/// Where a photo session starts.
struct BodyPhotoStart: Hashable {
    /// The poses to take, in order (front, side, back; one pose from an empty tile).
    var poses: [PhotoPose] = PhotoPose.session
    /// The full set just saved: the photos link to it.
    var measurementID: UUID?
    /// The body-fat sheet follows (a full set with an assessment due).
    var thenAssessment = false

    /// Offered after a full set: the first page asks "Add progress photos?".
    var afterMeasuring: Bool { measurementID != nil }
}

/// Device-only settings of the photos (UserDefaults).
enum BodyPhotoKeys {
    /// The measure sheet offers the photo session after a new full set (on by default).
    static let afterFullSet = "nina.photos.afterFullSet"
}

/// The photo sheets (`AppSheet.photos`), routed by `BodyPhotoSheetContent`.
enum BodyPhotoSheet: Identifiable {
    /// Take or pick photos pose by pose.
    case session(BodyPhotoStart)
    /// Two days of one pose (nil: front, else the first pose with two days).
    case compare(PhotoPose?)

    var id: String {
        switch self {
        case .session(let start):
            "session-" + start.poses.map(\.rawValue).joined(separator: ",") + "-" + (start.measurementID?.uuidString ?? "new")
        case .compare(let pose):
            "compare-" + (pose?.rawValue ?? "any")
        }
    }
}

/// `AppSheet.photos` in RootView's sheet router. Each sheet owns its NavigationStack and `.sheetFrame`.
struct BodyPhotoSheetContent: View {
    let sheet: BodyPhotoSheet

    var body: some View {
        switch sheet {
        case .session(let start):
            BodyPhotoSessionSheet(start: start)
        case .compare(let pose):
            BodyPhotoCompareSheet(initialPose: pose)
        }
    }
}

/// The live photos, oldest first, for `@Query`.
enum BodyPhotoQuery {
    static let live = #Predicate<ProgressPhoto> { $0.deletedAt == nil }
    static let trashed = #Predicate<ProgressPhoto> { $0.deletedAt != nil }
    static let order = [SortDescriptor(\ProgressPhoto.day), SortDescriptor(\ProgressPhoto.time)]
}

// MARK: - The card

/// "Photos" on the body page: the latest front, side and back thumbnails (a tap opens the photo,
/// an empty one takes that pose), Take Photos, Compare and the link to all photos.
struct BodyPhotosCard: View {
    @Environment(AppModel.self) private var app
    @Query(filter: BodyPhotoQuery.live, sort: BodyPhotoQuery.order) private var photos: [ProgressPhoto]
    @State private var viewing: BodyPhotoViewerItem?

    private var lock: BodyPhotoLock { BodyPhotoLock.shared }

    var body: some View {
        CardSection(title: "Photos", symbol: "camera", trailing: trailing) {
            if photos.isEmpty {
                emptyContent
            } else {
                tiles
                buttons
                allPhotosLink
            }
        }
        .bodyPhotoViewer(item: $viewing)
    }

    /// The latest photo day ("7 Jan").
    private var trailing: String? {
        photos.last.map { Fmt.dayTitle($0.dayKey, today: app.today) }
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Front, side and back photos every few weeks show what the scale and the tape miss. They sync only to your iCloud.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(BodyPhotoText.takeTitle, systemImage: "camera") { startSession(PhotoPose.session) }
                .buttonStyle(.bordered)
        }
    }

    private var tiles: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(PhotoPose.session) { pose in
                BodyPhotoTile(pose: pose, photo: latest(pose), today: app.today, isLocked: lock.isLocked) {
                    open(pose)
                }
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button(BodyPhotoText.takeTitle, systemImage: "camera") { startSession(PhotoPose.session) }
                .buttonStyle(.bordered)
            Button("Compare", systemImage: "square.split.2x1") { app.sheet = .photos(.compare(nil)) }
                .buttonStyle(.bordered)
                .disabled(!canCompare)
            Spacer(minLength: 0)
            Menu {
                BodyPhotoLockToggle()
            } label: {
                Image(systemName: lock.isEnabled ? "lock.fill" : "ellipsis.circle")
                    .accessibilityLabel("Photo options")
            }
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .controlSize(.small)
    }

    private var allPhotosLink: some View {
        NavigationLink {
            BodyPhotosGallery()
        } label: {
            BodyPageLinkRow(title: "All photos", detail: allPhotosDetail, symbol: "photo.on.rectangle")
        }
        .buttonStyle(.plain)
    }

    private var allPhotosDetail: String {
        let days = Set(photos.map(\.day)).count
        let photoText = photos.count == 1 ? "1 photo" : "\(photos.count) photos"
        return days == 1 ? photoText : "\(photoText) · \(days) days"
    }

    private var canCompare: Bool {
        !ProgressPhotos.comparablePoses(photos.map(\.record)).isEmpty
    }

    private func latest(_ pose: PhotoPose) -> ProgressPhoto? {
        photos.last { $0.photoPose == pose }
    }

    /// A photo opens in the viewer (after Face ID when locked); an empty pose takes that pose.
    private func open(_ pose: PhotoPose) {
        guard let photo = latest(pose) else {
            startSession([pose])
            return
        }
        let id = photo.uuid
        Task {
            guard await lock.unlock() else { return }
            viewing = BodyPhotoViewerItem(id: id)
        }
    }

    private func startSession(_ poses: [PhotoPose]) {
        app.sheet = .photos(.session(BodyPhotoStart(poses: poses)))
    }
}

/// One pose on the card: the thumbnail (3:4), the pose and the day.
private struct BodyPhotoTile: View {
    let pose: PhotoPose
    let photo: ProgressPhoto?
    let today: DayKey
    let isLocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                frame
                Text(pose.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(dayText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var label: String {
        photo == nil ? "Take \(pose.title.lowercased()) photo" : "\(pose.title) photo, \(dayText)"
    }

    private var frame: some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay { picture }
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var picture: some View {
        if let photo {
            BodyPhotoImageView(photo: photo)
                .bodyPhotoLocked(isLocked)
        } else {
            BodyPhotoEmptyFrame(pose: pose)
        }
    }

    private var dayText: String {
        guard let photo else { return "Not yet" }
        return Fmt.dayTitle(photo.dayKey, today: today)
    }
}

/// An empty pose: a dashed frame with the figure and a plus.
struct BodyPhotoEmptyFrame: View {
    let pose: PhotoPose

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Brand.accent.opacity(0.06))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Brand.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            VStack(spacing: 6) {
                Image(systemName: BodyPhotoText.symbol(pose))
                    .font(.title2)
                Image(systemName: "plus.circle.fill")
                    .font(.caption)
            }
            .foregroundStyle(Brand.accent)
        }
    }
}

/// Shared labels.
enum BodyPhotoText {
    /// "Take Photos" where there is a camera, else "Add Photos".
    @MainActor
    static var takeTitle: String { BodyPhotoCameraSupport.isAvailable ? "Take Photos" : "Add Photos" }

    static func symbol(_ pose: PhotoPose) -> String {
        switch pose {
        case .front: "figure.stand"
        case .side: "figure.walk"
        case .back: "figure"
        case .other: "person.crop.rectangle"
        }
    }

    /// "Front · Mon, 7 Jan"
    static func title(_ photo: ProgressPhoto, today: DayKey) -> String {
        "\(photo.photoPose.title) · \(Fmt.dayTitle(photo.dayKey, today: today))"
    }
}

/// Whether this device can take photos (iPhone, iPad with a camera).
enum BodyPhotoCameraSupport {
    @MainActor
    static var isAvailable: Bool {
        #if os(iOS)
        BodyPhotoCamera.isAvailable
        #else
        false
        #endif
    }
}

// MARK: - The viewer's presentation

/// The photo the viewer opens on.
struct BodyPhotoViewerItem: Identifiable, Hashable {
    let id: UUID
}

extension View {
    /// The full-screen photo viewer (a large sheet on the Mac).
    func bodyPhotoViewer(item: Binding<BodyPhotoViewerItem?>) -> some View {
        modifier(BodyPhotoViewerPresenter(item: item))
    }
}

private struct BodyPhotoViewerPresenter: ViewModifier {
    @Binding var item: BodyPhotoViewerItem?
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(item: $item) { item in
            viewer(item)
        }
        #else
        content.sheet(item: $item) { item in
            viewer(item)
        }
        #endif
    }

    private func viewer(_ item: BodyPhotoViewerItem) -> some View {
        BodyPhotoViewer(startID: item.id)
            .environment(app)
            .modelContainer(app.container)
            .appearanceFromSettings()
    }
}
