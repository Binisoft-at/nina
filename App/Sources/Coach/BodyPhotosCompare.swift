import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// How Compare shows the two photos.
enum BodyPhotoCompareStyle: String, CaseIterable, Identifiable {
    case sideBySide, fade, wipe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sideBySide: "Side by Side"
        case .fade: "Fade"
        case .wipe: "Slider"
        }
    }
}

/// Compare (`AppSheet.photos(.compare)`): two days of one pose side by side, or one over the other
/// (fade, or a slider that wipes from one to the other), with the time between and the 7-day
/// average weight and the waist at each day and their change. Opens on the first and the latest
/// day of the front photos. Owns its NavigationStack.
struct BodyPhotoCompareSheet: View {
    let initialPose: PhotoPose?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(filter: BodyPhotoQuery.live, sort: BodyPhotoQuery.order) private var photos: [ProgressPhoto]
    @State private var pose: PhotoPose?
    @State private var pair: ProgressPhotos.Pair?
    @State private var style: BodyPhotoCompareStyle = .sideBySide
    @State private var amount = 0.5
    @State private var context: CoachContext?
    @State private var viewing: BodyPhotoViewerItem?

    private var lock: BodyPhotoLock { BodyPhotoLock.shared }
    private var records: [PhotoRecord] { photos.map(\.record) }
    private var comparable: [PhotoPose] { ProgressPhotos.comparablePoses(records) }

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding()
                    .readableWidth(920)
            }
            .background(Color.groupedBackground)
            .navigationTitle("Compare")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // Read-only: Esc closes it on the Mac.
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .task(id: app.dataVersion) {
            context = CoachContext.load(app: app, day: app.today)
        }
        .task {
            setUp()
            if lock.isLocked { await lock.unlock() }
        }
        .onChange(of: pose) { _, newPose in poseChanged(newPose) }
        .onChange(of: photos.count) { _, _ in revalidate() }
        .bodyPhotoViewer(item: $viewing)
        // Fits a laptop screen on the Mac (the content scrolls).
        .sheetFrame(minWidth: 720, minHeight: 560)
    }

    @ViewBuilder
    private var content: some View {
        if let pose, let pair {
            VStack(spacing: 16) {
                controls(pose: pose, pair: pair)
                pictures(pose: pose, pair: pair)
                facts(pair)
            }
        } else {
            ContentUnavailableView {
                Label("Nothing to compare yet", systemImage: "square.split.2x1")
            } description: {
                Text("Take photos of the same pose on two different days.")
            } actions: {
                Button(BodyPhotoText.takeTitle) { app.present(.photos(.session(BodyPhotoStart()))) }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: Controls

    private func controls(pose: PhotoPose, pair: ProgressPhotos.Pair) -> some View {
        VStack(spacing: 12) {
            if comparable.count > 1 {
                Picker("Pose", selection: $pose) {
                    ForEach(comparable) { item in
                        Text(item.title).tag(Optional(item))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            HStack(alignment: .top, spacing: 12) {
                dayPicker("Before", selection: binding(asBefore: true), days: days(pose), excluding: pair.after)
                dayPicker("After", selection: binding(asBefore: false), days: days(pose), excluding: pair.before)
            }
            HStack(spacing: 8) {
                stylePicker
                InfoButton(BodyPageInfo.compare)
            }
        }
        .card()
    }

    private var stylePicker: some View {
        Picker("Show", selection: $style) {
            ForEach(BodyPhotoCompareStyle.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func dayPicker(_ title: String, selection: Binding<DayKey>, days: [DayKey], excluding: DayKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(Array(days.filter { $0 != excluding }.reversed())) { day in
                    Text(Fmt.dayTitle(day, today: app.today)).tag(day)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func binding(asBefore: Bool) -> Binding<DayKey> {
        Binding(get: {
            guard let pair else { return app.today }
            return asBefore ? pair.before : pair.after
        }, set: { day in
            guard let pair, let pose else { return }
            self.pair = ProgressPhotos.pair(pair, picking: day, asBefore: asBefore, days: days(pose))
        })
    }

    // MARK: Pictures

    @ViewBuilder
    private func pictures(pose: PhotoPose, pair: ProgressPhotos.Pair) -> some View {
        switch style {
        case .sideBySide:
            HStack(alignment: .top, spacing: 10) {
                pictureFrame(photo(pose, on: pair.before), title: "Before", day: pair.before)
                pictureFrame(photo(pose, on: pair.after), title: "After", day: pair.after)
            }
        case .fade, .wipe:
            VStack(spacing: 10) {
                overlayFrame(before: photo(pose, on: pair.before), after: photo(pose, on: pair.after))
                HStack(spacing: 10) {
                    Text(Fmt.shortDay(pair.before))
                    Slider(value: $amount, in: 0...1)
                    Text(Fmt.shortDay(pair.after))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(maxWidth: 560)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func pictureFrame(_ photo: ProgressPhoto?, title: String, day: DayKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title) · \(Fmt.dayTitle(day, today: app.today))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Color.black
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay { photoImage(photo) }
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                .contentShape(.rect)
                .onTapGesture { open(photo) }
        }
        .frame(maxWidth: .infinity)
    }

    private func overlayFrame(before: ProgressPhoto?, after: ProgressPhoto?) -> some View {
        Color.black
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay { photoImage(before) }
            .overlay { afterLayer(after) }
            .clipShape(.rect(cornerRadius: 16, style: .continuous))
            .frame(maxWidth: 560)
    }

    @ViewBuilder
    private func afterLayer(_ after: ProgressPhoto?) -> some View {
        if style == .fade {
            photoImage(after)
                .opacity(amount)
        } else {
            GeometryReader { proxy in
                photoImage(after)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: proxy.size.width * amount)
                    }
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 2)
                            .offset(x: max(0, proxy.size.width * amount - 1))
                    }
            }
        }
    }

    @ViewBuilder
    private func photoImage(_ photo: ProgressPhoto?) -> some View {
        if let photo {
            BodyPhotoImageView(photo: photo, size: .full(1600), contentMode: .fit)
                .id(photo.uuid)
                .bodyPhotoLocked(lock.isLocked, compact: false)
        }
    }

    @ViewBuilder
    private func facts(_ pair: ProgressPhotos.Pair) -> some View {
        if let context {
            BodyPhotoCompareFacts(comparison: PhotoComparison(pair: pair, signal: context.signal, tape: context.tapeRecords))
        }
    }

    // MARK: Data

    private func days(_ pose: PhotoPose) -> [DayKey] {
        ProgressPhotos.days(of: pose, in: records)
    }

    private func photo(_ pose: PhotoPose, on day: DayKey) -> ProgressPhoto? {
        guard let record = ProgressPhotos.photo(of: pose, on: day, in: records) else { return nil }
        return photos.first { $0.uuid == record.id }
    }

    private func isValid(_ pair: ProgressPhotos.Pair, for pose: PhotoPose) -> Bool {
        let available = days(pose)
        return pair.before != pair.after && available.contains(pair.before) && available.contains(pair.after)
    }

    /// Another pose: its first and latest day (unless the days picked have photos of it too).
    private func poseChanged(_ newPose: PhotoPose?) {
        guard let newPose else { return }
        if let pair, isValid(pair, for: newPose) { return }
        pair = ProgressPhotos.defaultPair(for: newPose, in: records)
    }

    private func setUp() {
        guard pose == nil else { return }
        let records = self.records
        guard let chosen = ProgressPhotos.comparePose(records, preferred: initialPose ?? PhotoPose.front) else { return }
        pair = ProgressPhotos.defaultPair(for: chosen, in: records)
        pose = chosen
    }

    /// After a delete (or a sync): a pose and days that still have photos.
    private func revalidate() {
        let records = self.records
        guard let current = pose, comparable.contains(current) else {
            pose = nil
            pair = nil
            setUp()
            return
        }
        if let pair, isValid(pair, for: current) { return }
        pair = ProgressPhotos.defaultPair(for: current, in: records)
    }

    private func open(_ photo: ProgressPhoto?) {
        guard let photo else { return }
        let id = photo.uuid
        Task {
            guard await lock.unlock() else { return }
            viewing = BodyPhotoViewerItem(id: id)
        }
    }
}

/// The time between the two days, the 7-day average weight and the waist at each and the change.
private struct BodyPhotoCompareFacts: View {
    let comparison: PhotoComparison

    var body: some View {
        CardSection(title: "Between These Days", symbol: "calendar") {
            row("Time", value: ProgressPhotos.spanText(days: comparison.days), detail: nil)
            Divider()
            row("Weight, 7-day average", value: weightText, detail: weightChange)
            Divider()
            row(comparison.waistSite.title, value: waistText, detail: waistChange)
            Text("Weight and tape from the days around each photo (up to a week apart). Nothing here is saved with the photos.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ title: String, value: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.subheadline.monospacedDigit())
                if let detail {
                    Text(detail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// "66.8 kg (15 Oct) → 67.1 kg": the 7-day average nearest each photo day, with its day when
    /// it isn't the photo day; "No weigh-ins yet" without any.
    private var weightText: String {
        let before = comparison.before, after = comparison.after
        guard before.weight != nil || after.weight != nil else { return "No weigh-ins yet" }
        return "\(weight(before)) → \(weight(after))"
    }

    private func weight(_ side: PhotoComparison.Side) -> String {
        guard let value = side.weight else { return "–" }
        guard let day = side.weightDay, day != side.day else { return Fmt.kilograms(value) }
        return "\(Fmt.kilograms(value)) (\(Fmt.shortDay(day)))"
    }

    /// The change, else which photo day has no average near it.
    private var weightChange: String? {
        if let change = comparison.weightChange { return BodyPhotoCompareFacts.signed(change, unit: "kg") }
        let missing = [comparison.before, comparison.after].filter { $0.weight == nil }
        guard missing.count == 1, let side = missing.first else { return nil }
        return "No weigh-ins around \(Fmt.shortDay(side.day))"
    }

    private var waistText: String {
        "\(centimeters(comparison.before.waist)) → \(centimeters(comparison.after.waist))"
    }

    private var waistChange: String? {
        comparison.waistChange.map { BodyPhotoCompareFacts.signed($0, unit: "cm") }
    }

    private func centimeters(_ value: Double?) -> String {
        value.map { Fmt.number($0, decimals: 1) + " cm" } ?? "–"
    }

    /// "+1.5 kg", "−0.8 cm", "±0 cm".
    static func signed(_ value: Double, unit: String) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == 0 { return "±0 \(unit)" }
        let sign = rounded > 0 ? "+" : "−"
        return "\(sign)\(Fmt.number(abs(rounded), decimals: 1)) \(unit)"
    }
}
