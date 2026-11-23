import SwiftUI
import BinisoftKit
import NinaCore

/// The body page: Progress → Body on iPhone and iPad, the Body sidebar item on the Mac. Shown
/// inside a NavigationStack. Top to bottom: what's due today, the phase and its status, the
/// weight card and chart, the body goal, the tape tiles, body composition, the phases timeline,
/// the check-ins, the check adherence and the full histories. On a wide screen (iPad, Mac) the
/// cards under the weight chart sit in two columns.
struct BodyPageView: View {
    @Environment(AppModel.self) private var app
    @State private var data: BodyPageData?
    @State private var latest: BodyPageLatestWeighIn?
    @State private var isWide = false
    /// The tape formula picked for sex "Prefer not to say" (device-only): the page reloads when it changes.
    @AppStorage(BodyPageKeys.navyFormula) private var navyFormula = ""

    var body: some View {
        ScrollView {
            content
                .padding()
                .readableWidth(1100)
        }
        .background(Color.groupedBackground)
        .navigationTitle("Body")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                BodyPageAddMenu()
            }
        }
        .task(id: loadKey) {
            data = BodyPageData.load(app: app)
            latest = BodyPageLatestWeighIn.load(app: app)
        }
    }

    /// Reload on every data change, when the day changes, when Apple Health weigh-ins or body data
    /// arrive (read live, never stored) and when a tape formula is picked.
    private var loadKey: String {
        "\(app.dataVersion)-\(app.today.rawValue)-\(app.health.weightSamples.count)-\(app.health.bodyData.version)-\(navyFormula)"
    }

    @ViewBuilder
    private var content: some View {
        if let data {
            BodyPageLayout(data: data, latest: latest, isWide: isWide)
                .onGeometryChange(for: Bool.self) { proxy in
                    proxy.size.width >= 700
                } action: { newValue in
                    isWide = newValue
                }
        } else {
            ProgressView()
                .padding(40)
                .frame(maxWidth: .infinity)
        }
    }
}

/// The newest weigh-in (typed, or read live from Apple Health) for the weight card's header:
/// "Today 67.3 kg". Display only, never stored.
struct BodyPageLatestWeighIn: Equatable {
    let day: DayKey
    let kilograms: Double

    @MainActor
    static func load(app: AppModel) -> BodyPageLatestWeighIn? {
        let readings = app.store.weights().map(\.reading) + app.healthWeightReadings
        let plausible = readings.filter { WeightSignal.plausibleRange.contains($0.kilograms) }
        guard let newest = plausible.max(by: { $0.time < $1.time }) else { return nil }
        return BodyPageLatestWeighIn(day: newest.day, kilograms: newest.kilograms)
    }

    /// "Today 67.3 kg", "Yesterday 67.1 kg"; nil when older.
    func text(today: DayKey) -> String? {
        if day == today { return "Today \(Fmt.kilograms(kilograms))" }
        if day == today.adding(days: -1) { return "Yesterday \(Fmt.kilograms(kilograms))" }
        return nil
    }
}

/// The "+" menu: weigh-in, measurements, body fat, photos, check-in, plan.
private struct BodyPageAddMenu: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Menu {
            Button("Log Weight…", systemImage: "scalemass") { app.sheet = .weight(nil) }
            Button("Log Measurements…", systemImage: "ruler") { app.measureNow() }
            Button("Log Body Fat…", systemImage: "percent") { app.sheet = .assessment(nil) }
            Button(photosTitle, systemImage: "camera") {
                app.sheet = .photos(.session(BodyPhotoStart(poses: PhotoPose.session)))
            }
            if app.settings.plan.isSetUp {
                Button("Weekly Check-in…", systemImage: "checklist") { app.sheet = .checkIn(app.currentCheckInWeek) }
            }
            Divider()
            Button("My Plan…", systemImage: "list.bullet.clipboard") { app.sheet = .plan }
        } label: {
            Label("Add", systemImage: "plus")
        }
    }

    /// The photo session as the Photos card starts it (front, side, back).
    private var photosTitle: String {
        #if os(macOS)
        "Add Progress Photos…"
        #else
        "Take Progress Photos…"
        #endif
    }
}

/// The cards in order; two columns under the weight card when wide.
private struct BodyPageLayout: View {
    let data: BodyPageData
    let latest: BodyPageLatestWeighIn?
    let isWide: Bool

    var body: some View {
        VStack(spacing: 16) {
            top
            if isWide {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        goal
                        composition
                        checkIns
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    VStack(spacing: 16) {
                        tiles
                        timeline
                        history
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            } else {
                goal
                tiles
                composition
                timeline
                checkIns
                history
            }
        }
    }

    @ViewBuilder
    private var top: some View {
        if !data.isSetUp {
            BodyPageSetupCard()
        }
        if !data.due.isEmpty {
            BodyPageDueCard(items: data.due, today: data.today)
        }
        if let header = data.header {
            BodyPagePhaseCard(header: header)
        }
        BodyPageWeightCard(weight: data.weight, latest: latest?.text(today: data.today))
    }

    @ViewBuilder
    private var goal: some View {
        if let goal = data.goal {
            BodyPageGoalCard(goal: goal)
        } else if data.isSetUp {
            BodyPageGoalHint()
        }
    }

    private var tiles: some View {
        BodyPageTilesCard(tiles: data.tiles, since: data.phaseStart, baseline: data.baseline, gainLine: data.gainLine)
    }

    @ViewBuilder
    private var composition: some View {
        if !data.composition.isEmpty {
            BodyPageCompositionCard(composition: data.composition, today: data.today)
        }
        BodyPhotosCard()
    }

    @ViewBuilder
    private var timeline: some View {
        if let timeline = data.timeline {
            BodyPageTimelineCard(timeline: timeline)
        }
    }

    @ViewBuilder
    private var checkIns: some View {
        if data.isSetUp {
            BodyPageCheckInsCard(checkIns: data.checkIns)
        }
        if let checks = data.checks {
            BodyPageChecksCard(checks: checks)
        }
    }

    private var history: some View {
        BodyPageHistoryCard(measurementCount: data.measurementCount)
    }
}

// MARK: - Style

/// Colours of the body page: status tones and phase goals (gain warm, maintain neutral, lose cool).
enum BodyPageStyle {
    /// A check that moves the scale started (creatine) on the weight chart.
    static let event: Color = Color.indigo.opacity(0.8)

    static func color(_ tone: BodyPageTone) -> Color {
        switch tone {
        case .good: .green
        case .watch: .orange
        case .alert: .red
        case .neutral: .secondary
        }
    }

    static func color(_ goal: WeightGoal) -> Color {
        switch goal {
        case .gain: .orange
        case .maintain: .gray
        case .lose: .teal
        }
    }
}

/// A thin progress capsule.
struct BodyPageCapsule: View {
    let progress: Double
    var tint: Color = Brand.accent

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.16))
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(6, proxy.size.width * CGFloat(min(max(progress, 0), 1))))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// A row that pushes or opens something: icon, title, detail, chevron.
struct BodyPageLinkRow: View {
    let title: String
    var detail: String?
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Brand.accent)
                .frame(width: 30, height: 30)
                .background(Brand.accent.opacity(0.13), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }
}
