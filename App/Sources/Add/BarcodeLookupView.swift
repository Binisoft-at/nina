import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore
#if os(iOS)
import UIKit
import VisionKit
#endif

/// Scan (iPhone) or type a barcode: your own food with that barcode, else Open Food Facts,
/// else create the food yourself. Nothing is saved before you check the values, and creating the
/// food leads straight to its amount page in this sheet.
struct BarcodeLookupView: View {
    let day: DayKey
    let meal: String?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var code = ""
    @State private var state: LookupState = .idle
    @State private var path: [BarcodeRoute] = []
    @State private var chosenMeal = ""
    /// A new value gives a fresh camera (Scan Again, back from the amount page).
    @State private var scanID = UUID()
    /// Counts scanned codes, for the success tap.
    @State private var scans = 0

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
                    scannerSection
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
            .navigationDestination(for: BarcodeRoute.self) { route in
                destination(route)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .onAppear {
                if chosenMeal.isEmpty { chosenMeal = meal ?? app.settings.suggestedMeal().id }
            }
            .onChange(of: path) { _, newPath in
                // Back from the amount page: the camera starts again.
                if newPath.isEmpty { scanID = UUID() }
            }
            .sensoryFeedback(.success, trigger: scans)
        }
        .sheetFrame(minWidth: 520, minHeight: 560)
    }

    #if os(iOS)
    private var scannerSection: some View {
        Section {
            BarcodeScanner { payload in
                code = payload
                scans += 1
                Task { await lookup(payload) }
            }
            .id(scanID)
            .frame(height: 260)
            .clipShape(.rect(cornerRadius: 18, style: .continuous))
            .listRowInsets(EdgeInsets())
            .overlay {
                if !DataScannerViewController.isAvailable {
                    cameraDenied
                }
            }
        } footer: {
            Text("Hold the barcode inside the frame.")
        }
    }

    private var cameraDenied: some View {
        VStack(spacing: 8) {
            Text("Allow camera access in Settings to scan.")
                .font(.callout)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .font(.callout.weight(.semibold))
        }
        .padding()
        .background(.thinMaterial, in: .rect(cornerRadius: 12))
    }
    #endif

    @ViewBuilder
    private func destination(_ route: BarcodeRoute) -> some View {
        switch route {
        case .portion(let record):
            PortionView(record: record, mode: .log(day: day, meal: chosenMeal), day: day, meal: $chosenMeal) { _ in
                dismiss()
            }
        case .newFood(let request):
            FoodEditor(food: nil, draft: request.draft) { record in
                path = [.portion(record)]
            }
        }
    }

    /// Back to the camera for the next product (iPhone).
    @ViewBuilder
    private var scanAgainButton: some View {
        #if os(iOS)
        if DataScannerViewController.isSupported {
            Button("Scan Again", systemImage: "barcode.viewfinder") {
                state = .idle
                code = ""
                scanID = UUID()
            }
        }
        #endif
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
                Button("Check and Edit First", systemImage: "square.and.pencil") {
                    path.append(.newFood(LogNewFoodRequest(draft: draft)))
                }
                scanAgainButton
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
                    path.append(.newFood(LogNewFoodRequest(draft: draft)))
                }
                scanAgainButton
            }
        }
    }

    private func lookup(_ raw: String) async {
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 6 else { return }
        if let own = app.library.records.first(where: { $0.barcode == digits }) {
            path = [.portion(own)]
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
        if thenLog { path = [.portion(food.record)] }
    }
}

/// Where the barcode sheet goes: the amount page, or a new food from the label (then its amount page).
private enum BarcodeRoute: Hashable {
    case portion(FoodRecord)
    case newFood(LogNewFoodRequest)
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
