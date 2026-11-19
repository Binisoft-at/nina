import SwiftUI
import BinisoftKit
import NinaCore

/// The Progress tab on iPhone and iPad (`AppTab.insights`): Body | Nutrition (`app.progressPage`),
/// with Body first once a plan is set up. Nutrition is the insights page. Shown inside the tab's
/// NavigationStack. When a plan appears (set up, imported, or synced from another device) the
/// page switches to Body once, also when that happened while this tab was never opened; a later
/// choice of Nutrition stays.
struct ProgressHome: View {
    @Environment(AppModel.self) private var app
    /// Whether the plan was set up the last time this page looked (device-only, never synced).
    @AppStorage("nina.progress.planSeen") private var planSeen = false

    var body: some View {
        @Bindable var app = app
        Group {
            switch app.progressPage {
            case .body: BodyPageView()
            case .nutrition: InsightsView()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Show", selection: $app.progressPage) {
                ForEach(pages) { page in
                    Text(page.title).tag(page)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.bottom, 6)
        }
        .onAppear { followPlan() }
        .onChange(of: app.settings.plan.isSetUp) { _, _ in followPlan() }
    }

    /// Body once when a plan appears (false → true); nothing else changes the chosen page. Not in
    /// the tour's practice data or demo screenshots, which pick their page themselves.
    private func followPlan() {
        guard !app.isSandbox, !app.launch.isDemo else { return }
        let isSetUp: Bool = app.settings.plan.isSetUp
        guard isSetUp != planSeen else { return }
        planSeen = isSetUp
        if isSetUp { app.progressPage = .body }
    }

    /// Body first once a plan is set up, else Nutrition first.
    private var pages: [ProgressPage] {
        app.settings.plan.isSetUp ? [.body, .nutrition] : [.nutrition, .body]
    }
}
