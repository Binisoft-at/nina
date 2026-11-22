import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import BinisoftKit
import NinaCore

/// A photo session (`AppSheet.photos(.session)`): a first page with the consistency guide, then
/// pose by pose (front, side, back) – take it with the camera (iPhone, iPad; the last photo of
/// the pose shows over the picture), pick it from Photos, or skip it – then the review with the
/// time and a note, which saves them all with one Undo. After a full set it starts with "Add
/// progress photos?" and links the photos to that measurement. Owns its NavigationStack.
struct BodyPhotoSessionSheet: View {
    let start: BodyPhotoStart

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(filter: BodyPhotoQuery.live, sort: BodyPhotoQuery.order) private var photos: [ProgressPhoto]
    @State private var step: PhotoSession.Step
    @State private var drafts: [PhotoPose: BodyPhotoDraft] = [:]
    /// The last photo of each pose, decoded for the camera's ghost.
    @State private var ghosts: [PhotoPose: BodyPhotoBitmap] = [:]
    @State private var time = Date()
    @State private var timeEdited = false
    @State private var note = ""
    @State private var working: PhotoPose?
    @State private var problem: String?
    @State private var pickerItem: PhotosPickerItem?
    @State private var cameraPose: PhotoPose?
    @State private var showsFiles = false
    @State private var confirmDiscard = false
    /// "Offer after every full set" (the measure sheet's "Then add progress photos").
    @AppStorage(BodyPhotoKeys.afterFullSet) private var offerAfterFullSet = true

    init(start: BodyPhotoStart) {
        self.start = start
        _step = State(initialValue: BodyPhotoSessionSheet.session(for: start).first)
    }

    /// The guide page for a whole session and after measuring; one pose (an empty tile) starts there.
    private static func session(for start: BodyPhotoStart) -> PhotoSession {
        PhotoSession(poses: start.poses, showsIntro: start.poses.count > 1 || start.afterMeasuring)
    }

    private var session: PhotoSession { BodyPhotoSessionSheet.session(for: start) }
    private var lock: BodyPhotoLock { BodyPhotoLock.shared }

    var body: some View {
        content
            .interactiveDismissDisabled(!drafts.isEmpty)
            .onChange(of: pickerItem) { _, item in picked(item) }
            .fileImporter(isPresented: $showsFiles, allowedContentTypes: [.image]) { result in
                if case .success(let url) = result { loadFile(url) }
            }
            .confirmationDialog("Discard these photos?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard Photos", role: .destructive, action: discard)
                Button("Keep Them", role: .cancel) {}
            }
            .modifier(BodyPhotoCameraPresenter(pose: $cameraPose, ghosts: lock.isLocked ? [:] : ghosts, session: session) { data, pose in
                Task { await use(data, for: pose, picked: false) }
            })
            .sheetFrame(minWidth: 520, minHeight: 720)
    }

    private var content: some View {
        NavigationStack {
            VStack(spacing: 0) {
                page
                bottomBar
            }
            .background(Color.groupedBackground)
            .navigationTitle(title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
            }
        }
    }

    private var title: String {
        switch step {
        case .intro: start.afterMeasuring ? "Add Progress Photos?" : "Progress Photos"
        case .pose(let pose): "\(pose.title) Photo"
        case .review: "Review"
        }
    }

    // MARK: Pages

    @ViewBuilder
    private var page: some View {
        switch step {
        case .intro:
            introPage
        case .pose(let pose):
            posePage(pose)
        case .review:
            reviewPage
        }
    }

    private var introPage: some View {
        Form {
            Section {
                ForEach(Array(ProgressPhotos.guide.enumerated()), id: \.offset) { item in
                    Label(item.element, systemImage: BodyPhotoSessionText.guideSymbol(item.offset))
                }
            } header: {
                Text("The same every time")
            } footer: {
                Text(introFooter)
            }
            if let last = photos.last {
                Section {
                    LabeledContent("Last photos", value: Fmt.dayTitle(last.dayKey, today: app.today))
                }
            }
            if start.afterMeasuring {
                Section {
                    Toggle("Offer after every full set", isOn: $offerAfterFullSet)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var introFooter: String {
        if start.afterMeasuring {
            return "Right after a full measurement is the best moment: the same morning, the same conditions."
        }
        return "Front, side and back – about a minute. The photos sync only to your iCloud."
    }

    private func posePage(_ pose: PhotoPose) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Text(session.position(of: pose) ?? pose.title)
                        .font(.headline)
                    Text(pose.hint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                BodyPhotoSessionFrame(pose: pose, draft: drafts[pose], last: latest(pose), today: app.today,
                                      isLocked: lock.isLocked, isWorking: working == pose) {
                    Task { await lock.unlock() }
                }
                .frame(maxWidth: 420)
                poseButtons(pose)
                if let problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .task(id: pose) { await loadGhost(pose) }
    }

    private func poseButtons(_ pose: PhotoPose) -> some View {
        HStack(spacing: 10) {
            if BodyPhotoCameraSupport.isAvailable {
                Button(BodyPhotoSessionText.takeTitle(has: drafts[pose] != nil), systemImage: "camera") { openCamera(pose) }
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(BodyPhotoSessionText.chooseTitle(has: drafts[pose] != nil), systemImage: "photo.on.rectangle")
            }
            if PlatformInfo.isMac {
                Button("Choose File…", systemImage: "folder") { showsFiles = true }
            }
        }
        .buttonStyle(.bordered)
        .disabled(working != nil)
    }

    private var reviewPage: some View {
        Form {
            Section {
                if takenPoses.isEmpty {
                    Text("No photos in this session.")
                        .foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(takenPoses) { pose in
                            reviewTile(pose)
                        }
                    }
                }
            } footer: {
                if !takenPoses.isEmpty {
                    Text("Tap a photo to take it again.")
                }
            }
            Section {
                DatePicker("When", selection: timeBinding)
                TextField("Note", text: $note, prompt: Text("Note"), axis: .vertical)
            } footer: {
                Text("Saved to your iCloud only – location and camera details are left out.")
            }
        }
        .formStyle(.grouped)
    }

    private func reviewTile(_ pose: PhotoPose) -> some View {
        Button {
            step = .pose(pose)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Color.clear
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay { draftPicture(pose) }
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
                Text(pose.title)
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: 140)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func draftPicture(_ pose: PhotoPose) -> some View {
        if let draft = drafts[pose] {
            BodyPhotoDraftImage(draft: draft, contentMode: .fill)
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            leadingButton
            Spacer(minLength: 8)
            Button(action: next) {
                Text(nextTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
            }
            .primaryActionStyle()
            .disabled(nextDisabled)
            #if os(macOS)
            .keyboardShortcut(.defaultAction)
            #endif
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var leadingButton: some View {
        switch step {
        case .intro:
            if start.afterMeasuring {
                Button("Not Now", action: finish)
                    .buttonStyle(.glass)
            }
        case .pose(let pose):
            if drafts[pose] == nil {
                Button("Skip") { skip(pose) }
                    .buttonStyle(.glass)
                    .disabled(working != nil)
            } else {
                Button("Remove", role: .destructive) { drafts[pose] = nil }
                    .buttonStyle(.glass)
            }
        case .review:
            if let last = session.poses.last {
                Button("Back") { step = .pose(last) }
                    .buttonStyle(.glass)
            }
        }
    }

    private var nextTitle: String {
        guard step == .review else { return session.nextTitle(after: step) }
        switch takenPoses.count {
        case 0: return "Done"
        case 1: return "Save Photo"
        default: return "Save \(takenPoses.count) Photos"
        }
    }

    private var nextDisabled: Bool {
        if working != nil { return true }
        if case .pose(let pose) = step { return drafts[pose] == nil }
        return false
    }

    private var takenPoses: [PhotoPose] {
        session.poses.filter { drafts[$0] != nil }
    }

    private var timeBinding: Binding<Date> {
        Binding(get: { time }, set: { newValue in
            time = newValue
            timeEdited = true
        })
    }

    // MARK: Actions

    private func latest(_ pose: PhotoPose) -> ProgressPhoto? {
        photos.last { $0.photoPose == pose }
    }

    private func next() {
        if step == .review {
            save()
        } else if let following = session.next(after: step) {
            withAnimation { step = following }
        }
    }

    private func skip(_ pose: PhotoPose) {
        drafts[pose] = nil
        problem = nil
        if let following = session.next(after: .pose(pose)) {
            withAnimation { step = following }
        }
    }

    private func openCamera(_ pose: PhotoPose) {
        problem = nil
        cameraPose = pose
    }

    private func picked(_ item: PhotosPickerItem?) {
        guard let item, case .pose(let pose) = step else { return }
        pickerItem = nil
        working = pose
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            await use(data, for: pose, picked: true)
        }
    }

    /// The Mac's "Choose File…".
    private func loadFile(_ url: URL) {
        guard case .pose(let pose) = step else { return }
        let access = url.startAccessingSecurityScopedResource()
        let data = try? Data(contentsOf: url)
        if access { url.stopAccessingSecurityScopedResource() }
        Task { await use(data, for: pose, picked: true) }
    }

    /// Downscales and encodes a photo (off the main thread) and keeps it for this pose.
    private func use(_ data: Data?, for pose: PhotoPose, picked: Bool) async {
        working = pose
        problem = nil
        let processed: BodyPhotoImages.Processed?
        if let data {
            processed = await BodyPhotoImages.process(data)
        } else {
            processed = nil
        }
        working = nil
        guard let processed else {
            problem = "That photo couldn't be read. Try another one."
            return
        }
        drafts[pose] = BodyPhotoDraft(pose: pose, image: processed.image, thumbnail: processed.thumbnail,
                                      capturedAt: picked ? processed.capturedAt : nil)
        updateTime()
    }

    /// Photos picked from the library keep the day they were taken (until the time is changed);
    /// with a camera photo it is now.
    private func updateTime() {
        guard !timeEdited else { return }
        let list = Array(drafts.values)
        let taken = list.compactMap(\.capturedAt)
        if taken.count == list.count, let first = taken.min() {
            time = first
        } else {
            time = Date()
        }
    }

    private func loadGhost(_ pose: PhotoPose) async {
        guard ghosts[pose] == nil, let last = latest(pose), let data = last.image ?? last.thumbnail else { return }
        let key = last.uuid.uuidString + "-full-1200"
        if let bitmap = await BodyPhotoImages.bitmap(data, key: key, maxPixels: 1200) {
            ghosts[pose] = bitmap
        }
    }

    private func save() {
        let list = takenPoses.compactMap { drafts[$0] }
        if !list.isEmpty {
            let day = DayKey(date: time, dayStartHour: app.settings.dayStartHour)
            app.savePhotos(list, day: day, time: time, note: note, measurementID: start.measurementID)
        }
        drafts = [:]
        finish()
    }

    private func cancel() {
        if drafts.isEmpty {
            finish()
        } else {
            confirmDiscard = true
        }
    }

    private func discard() {
        drafts = [:]
        finish()
    }

    /// Closes, or goes on to the body-fat sheet when it follows.
    private func finish() {
        if start.thenAssessment {
            app.present(.assessment(nil))
        } else {
            dismiss()
        }
    }
}

/// The pose's frame: the new photo, else the last one of the pose (to stand the same way), else
/// an empty frame.
private struct BodyPhotoSessionFrame: View {
    let pose: PhotoPose
    let draft: BodyPhotoDraft?
    let last: ProgressPhoto?
    let today: DayKey
    let isLocked: Bool
    let isWorking: Bool
    let unlock: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay { picture }
                .overlay { progress }
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var picture: some View {
        if let draft {
            BodyPhotoDraftImage(draft: draft, contentMode: .fit)
        } else if let last {
            BodyPhotoImageView(photo: last, size: .full(1200), contentMode: .fit)
                .opacity(0.85)
                .bodyPhotoLocked(isLocked, compact: false)
                .onTapGesture {
                    if isLocked { unlock() }
                }
        } else {
            BodyPhotoEmptyFrame(pose: pose)
        }
    }

    @ViewBuilder
    private var progress: some View {
        if isWorking {
            ProgressView()
                .controlSize(.large)
        }
    }

    private var caption: String {
        if draft != nil { return "New photo" }
        if let last { return "Last time · \(Fmt.dayTitle(last.dayKey, today: today)) – stand the same way" }
        return "Your first \(pose.title.lowercased()) photo"
    }
}

/// The camera as a full-screen cover (iPhone, iPad); nothing on the Mac.
private struct BodyPhotoCameraPresenter: ViewModifier {
    @Binding var pose: PhotoPose?
    let ghosts: [PhotoPose: BodyPhotoBitmap]
    let session: PhotoSession
    let onPhoto: (Data, PhotoPose) -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(item: $pose) { current in
            BodyPhotoCameraView(title: session.position(of: current) ?? current.title, ghost: ghosts[current],
                                onPhoto: { data in
                                    pose = nil
                                    onPhoto(data, current)
                                },
                                onCancel: { pose = nil })
        }
        #else
        content
        #endif
    }
}

enum BodyPhotoSessionText {
    static func guideSymbol(_ index: Int) -> String {
        let symbols = ["lightbulb", "ruler", "sunrise", "tshirt"]
        return index < symbols.count ? symbols[index] : "checkmark.circle"
    }

    static func takeTitle(has photo: Bool) -> String { photo ? "Retake" : "Take Photo" }
    static func chooseTitle(has photo: Bool) -> String { photo ? "Choose Another" : "Choose Photo" }
}
