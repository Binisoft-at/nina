import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// One photo full screen (a large sheet on the Mac): the pose, day and time, the note, the older
/// and newer photos of the same pose (arrows, or a swipe), a new pose, the note, and Delete with
/// Undo. Asks for Face ID first when the photo lock is on.
struct BodyPhotoViewer: View {
    let startID: UUID

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(filter: BodyPhotoQuery.live, sort: BodyPhotoQuery.order) private var photos: [ProgressPhoto]
    @State private var currentID: UUID
    @State private var editingNote = false
    @State private var noteText = ""

    init(startID: UUID) {
        self.startID = startID
        _currentID = State(initialValue: startID)
    }

    private var lock: BodyPhotoLock { BodyPhotoLock.shared }

    private var current: ProgressPhoto? {
        photos.first { $0.uuid == currentID }
    }

    /// The photos of the current pose, oldest first.
    private var timeline: [ProgressPhoto] {
        guard let current else { return [] }
        let pose = current.photoPose
        return photos.filter { $0.photoPose == pose }
    }

    private var index: Int? {
        timeline.firstIndex { $0.uuid == currentID }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()
                stage
            }
            .navigationTitle(current.map { $0.photoPose.title } ?? "Photo")
            .inlineNavigationTitle()
            .toolbar { toolbar }
        }
        .environment(\.colorScheme, .dark)
        .sheetToasts(app.toasts)
        .alert("Note", isPresented: $editingNote) {
            TextField("Note", text: $noteText)
            Button("Save", action: saveNote)
            Button("Cancel", role: .cancel) {}
        }
        .task {
            if lock.isLocked { await lock.unlock() }
        }
        // Fits a laptop screen on the Mac (the photo scales to fit).
        .sheetFrame(minWidth: 640, minHeight: 560)
    }

    // MARK: Parts

    @ViewBuilder
    private var stage: some View {
        if let current {
            VStack(spacing: 12) {
                picture(current)
                caption(current)
                stepper
            }
            .padding(.bottom, 8)
        } else {
            ContentUnavailableView("Photo deleted", systemImage: "photo",
                                   description: Text("Deleted photos stay on the photos page for 30 days."))
        }
    }

    private func picture(_ photo: ProgressPhoto) -> some View {
        BodyPhotoImageView(photo: photo, size: .full(ProgressPhotos.fullPixels), contentMode: .fit)
            .background(Color.black)
            .bodyPhotoLocked(lock.isLocked, compact: false)
            .id(photo.uuid)
            .contentShape(.rect)
            .onTapGesture {
                if lock.isLocked { Task { await lock.unlock() } }
            }
            .gesture(swipe)
    }

    private func caption(_ photo: ProgressPhoto) -> some View {
        VStack(spacing: 4) {
            Text(dateLine(photo))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            if !photo.note.isEmpty, !lock.isLocked {
                Text(photo.note)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal)
    }

    private var stepper: some View {
        HStack(spacing: 18) {
            Button("Older", systemImage: "chevron.left") { show(offset: -1) }
                .disabled(!canShow(-1))
                .keyboardShortcut(.leftArrow, modifiers: [])
            Text(positionText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
                .frame(minWidth: 60)
            Button("Newer", systemImage: "chevron.right") { show(offset: 1) }
                .disabled(!canShow(1))
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
            menu
        }
    }

    private var menu: some View {
        Menu {
            if let current {
                Picker("Pose", selection: poseBinding(current)) {
                    ForEach(PhotoPose.allCases) { pose in
                        Text(pose.title).tag(pose)
                    }
                }
                .pickerStyle(.menu)
                Button("Edit Note…", systemImage: "square.and.pencil") {
                    noteText = current.note
                    editingNote = true
                }
                Divider()
                Button("Delete Photo", systemImage: "trash", role: .destructive) { delete(current) }
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .disabled(current == nil || lock.isLocked)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                if value.translation.width < -60 {
                    show(offset: 1)
                } else if value.translation.width > 60 {
                    show(offset: -1)
                }
            }
    }

    // MARK: Values

    /// "Front · Mon, 7 Jan 2030 · 07:15"
    private func dateLine(_ photo: ProgressPhoto) -> String {
        let day = photo.dayKey.date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
        return "\(photo.photoPose.title) · \(day) · \(Fmt.time(photo.time))"
    }

    private var positionText: String {
        guard let index else { return "" }
        return "\(index + 1) of \(timeline.count)"
    }

    private func canShow(_ offset: Int) -> Bool {
        guard let index else { return false }
        let target = index + offset
        return target >= 0 && target < timeline.count
    }

    private func show(offset: Int) {
        guard let index, canShow(offset) else { return }
        let target = timeline[index + offset].uuid
        withAnimation(.easeInOut(duration: 0.2)) { currentID = target }
    }

    private func poseBinding(_ photo: ProgressPhoto) -> Binding<PhotoPose> {
        Binding(get: { photo.photoPose }, set: { pose in
            guard pose != photo.photoPose else { return }
            app.updatePhoto(photo, pose: pose, note: photo.note)
        })
    }

    private func saveNote() {
        guard let current else { return }
        app.updatePhoto(current, pose: current.photoPose, note: noteText)
    }

    /// Into the trash with Undo; the viewer shows the next photo of the pose, or closes.
    private func delete(_ photo: ProgressPhoto) {
        let list = timeline
        let position = list.firstIndex { $0.uuid == photo.uuid } ?? 0
        var neighbour: ProgressPhoto?
        if position + 1 < list.count {
            neighbour = list[position + 1]
        } else if position > 0 {
            neighbour = list[position - 1]
        }
        app.trashPhoto(photo)
        if let neighbour {
            currentID = neighbour.uuid
        } else {
            dismiss()
        }
    }
}

// MARK: - All photos

/// All progress photos by day, newest first (pushed from the Photos card): a tap opens the viewer.
/// Take Photos, Compare, the photo lock, and the photos deleted in the last 30 days.
struct BodyPhotosGallery: View {
    @Environment(AppModel.self) private var app
    @Query(filter: BodyPhotoQuery.live, sort: BodyPhotoQuery.order) private var photos: [ProgressPhoto]
    @Query(filter: BodyPhotoQuery.trashed, sort: [SortDescriptor(\ProgressPhoto.time, order: .reverse)])
    private var trashed: [ProgressPhoto]
    @State private var viewing: BodyPhotoViewerItem?

    private var lock: BodyPhotoLock { BodyPhotoLock.shared }

    /// Photo days, newest first.
    private var days: [DayKey] {
        Array(Set(photos.map(\.dayKey))).sorted(by: >)
    }

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 180), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if photos.isEmpty {
                    empty
                }
                ForEach(days) { day in
                    daySection(day)
                }
                if !trashed.isEmpty {
                    trashSection
                }
                privacySection
            }
            .padding()
            .readableWidth(920)
        }
        .background(Color.groupedBackground)
        .navigationTitle("Progress Photos")
        .toolbar { toolbar }
        .bodyPhotoViewer(item: $viewing)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(BodyPhotoText.takeTitle, systemImage: "camera") {
                app.sheet = .photos(.session(BodyPhotoStart()))
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Compare", systemImage: "square.split.2x1") {
                app.sheet = .photos(.compare(nil))
            }
            .disabled(ProgressPhotos.comparablePoses(photos.map(\.record)).isEmpty)
        }
    }

    private var empty: some View {
        ContentUnavailableView("No photos yet", systemImage: "camera",
                               description: Text("Front, side and back every few weeks – ideally the morning of a full measurement."))
    }

    private func daySection(_ day: DayKey) -> some View {
        let list = photos.filter { $0.dayKey == day }.sorted { $0.photoPose.order < $1.photoPose.order }
        return CardSection(title: Fmt.dayTitle(day, today: app.today), trailing: list.count == 1 ? "1 photo" : "\(list.count) photos") {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(list) { photo in
                    Button {
                        open(photo)
                    } label: {
                        BodyPhotoGridCell(photo: photo, isLocked: lock.isLocked)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var trashSection: some View {
        CardSection(title: "Recently Deleted", symbol: "trash") {
            ForEach(trashed) { photo in
                BodyPhotoTrashRow(photo: photo, today: app.today, isLocked: lock.isLocked) {
                    app.store.restore([photo])
                } purge: {
                    app.store.purge([photo])
                }
            }
        }
    }

    private var privacySection: some View {
        CardSection(title: "Privacy", symbol: "lock") {
            BodyPhotoLockToggle()
            Text(privacyText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var privacyText: String {
        let lockLine = BodyPhotoLock.isAvailable
            ? "With the lock on, this device asks for \(BodyPhotoLock.methodName) before it shows them."
            : "Set a passcode on this device to lock them."
        return "Your photos sync only through your private iCloud, to your own devices. " + lockLine
    }

    private func open(_ photo: ProgressPhoto) {
        let id = photo.uuid
        Task {
            guard await lock.unlock() else { return }
            viewing = BodyPhotoViewerItem(id: id)
        }
    }
}

/// A photo in the grid: the thumbnail (3:4) and its pose.
private struct BodyPhotoGridCell: View {
    let photo: ProgressPhoto
    let isLocked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay {
                    BodyPhotoImageView(photo: photo)
                        .bodyPhotoLocked(isLocked)
                }
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
            Text(photo.photoPose.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .contentShape(.rect)
    }
}

/// A deleted photo: Restore, or delete it for good.
private struct BodyPhotoTrashRow: View {
    let photo: ProgressPhoto
    let today: DayKey
    let isLocked: Bool
    let restore: () -> Void
    let purge: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            BodyPhotoImageView(photo: photo)
                .bodyPhotoLocked(isLocked)
                .frame(width: 42, height: 56)
                .clipShape(.rect(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(BodyPhotoText.title(photo, today: today))
                    .font(.subheadline)
                Text(daysLeftText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Restore", action: restore)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Menu {
                Button("Delete Now", systemImage: "trash", role: .destructive, action: purge)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("More")
            }
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var daysLeftText: String {
        let days = photo.deletedAt.map { TrashPolicy(keepDays: 30).daysLeft(deletedAt: $0) } ?? 30
        return days == 1 ? "1 day left" : "\(days) days left"
    }
}
