import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore
#if os(iOS)
import VisionKit
#endif

/// Scan (iPhone) or type a barcode: your own food with that barcode, else Open Food Facts,
/// else create the food yourself. Nothing is saved before you check the values.
struct BarcodeLookupView: View {
    let day: DayKey
    let meal: String?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var state: LookupState = .idle
    @State private var path: [FoodRecord] = []
    @State private var chosenMeal = ""

    enum LookupState: Equatable {
        case idle, searching
        case found(FoodDraft)
        case notFound(String)
        case problem(String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                #if os(iOS)
                if DataScannerViewController.isSupported, state == .idle {
                    Section {
                        BarcodeScanner { payload in
                            code = payload
                            Task { await lookup(payload) }
                        }
                        .frame(height: 260)
                        .clipShape(.rect(cornerRadius: 18, style: .continuous))
                        .listRowInsets(EdgeInsets())
                        .overlay {
                            if !DataScannerViewController.isAvailable {
                                Text("Allow camera access in Settings to scan.")
                                    .font(.callout)
                                    .padding()
                                    .background(.thinMaterial, in: .rect(cornerRadius: 12))
                            }
                        }
                    } footer: {
                        Text("Hold the barcode inside the frame.")
                    }
                }
                #endif
                Section {
                    HStack {
                        TextField("Barcode (EAN)", text: $code)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .onSubmit { Task { await lookup(code) } }
                        Button("Look Up") { Task { await lookup(code) } }
                            .disabled(code.filter(\.isNumber).count < 6 || state == .searching)
                    }
                } footer: {
                    Text("Products come from Open Food Facts, a free database anyone can improve (data under the ODbL licence).")
                }
                resultSection
            }
            .formStyle(.grouped)
            .navigationTitle("Barcode")
            .inlineNavigationTitle()
            .navigationDestination(for: FoodRecord.self) { record in
                PortionView(record: record, mode: .log(day: day, meal: chosenMeal), day: day, meal: $chosenMeal) { _ in
                    dismiss()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .onAppear { chosenMeal = meal ?? app.settings.suggestedMeal().id }
        }
        .sheetFrame(minWidth: 520, minHeight: 620)
    }

    @ViewBuilder
    private var resultSection: some View {
        switch state {
        case .idle:
            EmptyView()
        case .searching:
            Section { HStack { ProgressView(); Text("Looking up \(code)…").foregroundStyle(.secondary) } }
        case .found(let draft):
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(draft.name).font(.headline)
                    if !draft.brand.isEmpty { Text(draft.brand).font(.subheadline).foregroundStyle(.secondary) }
                    Text("Per 100 \(draft.unit.symbol): \(Fmt.energy(draft.nutrients.energy, unit: app.energyUnit)) · P \(Fmt.nutrient(draft.nutrients[.protein], .protein)) · C \(Fmt.nutrient(draft.nutrients[.carbs], .carbs)) · F \(Fmt.nutrient(draft.nutrients[.fat], .fat))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Save and Log", systemImage: "checkmark.circle.fill") { save(draft, thenLog: true) }
                Button("Check and Edit First", systemImage: "square.and.pencil") { app.present(.newFood(draft)) }
            } header: {
                Text("Found")
            } footer: {
                Text("Values come from the community and can be wrong – a quick look at the package helps.")
            }
        case .notFound(let message), .problem(let message):
            Section {
                Text(message)
                Button("Create It from the Label", systemImage: "square.and.pencil") {
                    var draft = FoodDraft(name: "", nutrients: .zero)
                    draft.barcode = code.filter(\.isNumber)
                    app.present(.newFood(draft))
                }
            }
        }
    }

    private func lookup(_ raw: String) async {
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 6 else { return }
        if let own = app.library.records.first(where: { $0.barcode == digits }) {
            path = [own]
            return
        }
        state = .searching
        state = await BarcodeService.lookup(digits)
        AppLog.info("Barcode lookup: \(stateName)", category: "barcode")
    }

    private var stateName: String {
        switch state {
        case .found: "found"
        case .notFound: "not found"
        case .problem: "problem"
        default: "–"
        }
    }

    private func save(_ draft: FoodDraft, thenLog: Bool) {
        let food = app.store.saveFood(draft, source: .barcode)
        app.refresh()
        if thenLog { path = [food.record] }
    }
}

/// Open Food Facts requests (one product at a time, on request only).
enum BarcodeService {
    static func lookup(_ barcode: String) async -> BarcodeLookupView.LookupState {
        guard let url = OpenFoodFacts.productURL(barcode: barcode) else { return .notFound("That doesn't look like a barcode.") }
        var request = URLRequest(url: url, timeoutInterval: 15)
        let version = AppVersion.main.marketing
        #if os(iOS)
        let platform = "iOS"
        #else
        let platform = "macOS"
        #endif
        request.setValue(OpenFoodFacts.userAgent(appName: AppInfo.name, version: version, platform: platform), forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                return .notFound("Open Food Facts doesn't know \(barcode) yet.")
            }
            switch OpenFoodFacts.parse(data, barcode: barcode) {
            case .success(let draft): return .found(draft)
            case .failure(.notFound): return .notFound("Open Food Facts doesn't know \(barcode) yet.")
            case .failure(.noNutrition(let name)): return .notFound("\u{201C}\(name)\u{201D} is known, but without nutrition values.")
            case .failure(.unreadable): return .problem("The answer from Open Food Facts couldn't be read.")
            }
        } catch {
            return .problem("No connection to Open Food Facts: \(error.localizedDescription)")
        }
    }
}

#if os(iOS)
/// VisionKit's live barcode scanner.
struct BarcodeScanner: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        if !controller.isScanning, DataScannerViewController.isAvailable, !context.coordinator.done {
            try? controller.startScanning()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void
        var done = false

        init(onFound: @escaping (String) -> Void) {
            self.onFound = onFound
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    done = true
                    dataScanner.stopScanning()
                    onFound(payload)
                    return
                }
            }
        }
    }
}
#endif
