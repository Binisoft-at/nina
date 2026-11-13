import SwiftUI
import SwiftData
import TipKit
import BinisoftKit
import NinaCore

/// The interactive tour: the real diary on a throwaway practice day, with the coach card on top.
/// Each step watches the page and ticks itself off once you've done what it describes.
struct TourView: View {
    let steps: [TourStep<NinaTourSnapshot>]
    /// The real app's model: its menu commands are pointed at the practice page meanwhile.
    let host: AppModel
    let onFinish: () -> Void

    @State private var sandbox: AppModel?

    var body: some View {
        Group {
            if let sandbox {
                PracticePage(steps: steps, startAt: host.launch.tourStep, onFinish: onFinish)
                    .environment(sandbox)
                    .modelContainer(sandbox.container)
                    .modifier(AppChrome(app: sandbox))
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard sandbox == nil else { return }
            let model = AppModel(container: Persistence.practiceStore(), mode: .demo, isSandbox: true)
            sandbox = model
            host.tourModel = model
        }
        .onDisappear { host.tourModel = nil }
    }
}

private struct PracticePage: View {
    let steps: [TourStep<NinaTourSnapshot>]
    let startAt: String?
    let onFinish: () -> Void

    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<LogEntry> { $0.deletedAt == nil }) private var entries: [LogEntry]
    @Query(filter: #Predicate<LogEntry> { $0.deletedAt != nil }) private var trashed: [LogEntry]
    @Query(filter: #Predicate<WaterLog> { $0.deletedAt == nil }) private var water: [WaterLog]

    var body: some View {
        NavigationStack {
            // Inside the stack, so the coach sits below the navigation bar and the + stays reachable.
            DayView(day: app.today)
                .tourCoach(steps: steps, snapshot: snapshot, startAt: startAt, onClose: onFinish)
        }
    }

    private var snapshot: NinaTourSnapshot {
        var snapshot = NinaTourSnapshot()
        snapshot.eatenCount = entries.filter(\.isEaten).count
        snapshot.plannedCount = entries.filter(\.isPlanned).count
        snapshot.trashedCount = trashed.count
        snapshot.mealLayout = Dictionary(grouping: entries, by: \.meal)
            .map { "\($0.key):\($0.value.count)" }
            .sorted()
            .joined(separator: "|")
        snapshot.water = water.map(\.amount).reduce(0, +)
        switch app.sheet {
        case .create?: snapshot.isCreateOpen = true
        case .addFood?: snapshot.isAddOpen = true
        default: break
        }
        return snapshot
    }
}

/// Contextual hints (TipKit). Each shows once until dismissed; Settings → Show Hints Again.
enum NinaTips {
    struct LogTip: Tip {
        var title: Text { Text("Log anything here") }
        var message: Text? { Text("Search about 1,000 foods, scan a barcode, or type \u{201C}2 eggs and a toast\u{201D}.") }
        var image: Image? { Image(systemName: "plus.circle.fill") }
    }

    struct TypeItTip: Tip {
        var title: Text { Text("Type it like a message") }
        var message: Text? { Text("Write everything you ate in one line – \u{201C}200 g Skyr, 1 Banane, Kaffee mit Milch\u{201D} – and log it at once. Swipe left on the ring to see yesterday.") }
        var image: Image? { Image(systemName: "text.bubble") }
    }
}
