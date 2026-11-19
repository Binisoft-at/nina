import SwiftUI
import BinisoftKit
import NinaCore

/// The Progress tab on iPhone and iPad (`AppTab.insights`): Body | Nutrition (`app.progressPage`),
/// with Body first once a plan is set up. Nutrition is the insights page. Shown inside the tab's
/// NavigationStack.
struct ProgressHome: View {
    @Environment(AppModel.self) private var app

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
    }

    /// Body first once a plan is set up, else Nutrition first.
    private var pages: [ProgressPage] {
        app.settings.plan.isSetUp ? [.body, .nutrition] : [.nutrition, .body]
    }
}
