import SwiftUI
import UniformTypeIdentifiers
import BinisoftKit
import NinaCore

// The weight & body history import and export in the app: the preview lines of Import & Export,
// and the Import & Export menu of Progress → Body → All measurements (save, share or copy the CSV,
// or import one). The reading, matching and writing are in BodyHistoryCSV (NinaCore) and
// NinaStore+History.

extension ImportPreview {
    /// One line per record the import adds ("Weigh-in · 78.4 kg", "Tape · 6 sites", "Body fat
    /// 19.8 % · DEXA scan"), after a line for what is already saved.
    @MainActor
    static func historyLines(_ plan: BodyHistoryPlan, today: DayKey) -> [Line] {
        var lines: [Line] = []
        if plan.duplicates > 0 {
            let count = plan.duplicates
            lines.append(Line(title: "Already saved", detail: count == 1 ? "1 value is in Nina already" : "\(count) values are in Nina already",
                              action: "skip"))
        }
        for record in plan.records {
            lines.append(Line(title: BodyHistoryText.title(record), detail: BodyHistoryText.detail(record, today: today), action: "new"))
        }
        return lines
    }
}

/// Text for a history record in the import preview.
enum BodyHistoryText {
    /// "Weigh-in · 78.4 kg · 20.5 % body fat", "Waist 84.5 cm", "Tape · 6 sites", "Body fat 19.8 % · DEXA scan".
    static func title(_ record: BodyHistoryRecord) -> String {
        switch record.kind {
        case .weight:
            var text = "Weigh-in · " + Fmt.kilograms(record.kilograms, decimals: 1)
            if record.bodyFat > 0 { text += " · " + percent(record.bodyFat) + " body fat" }
            return text
        case .tape:
            let sites = BodyDetailsText.siteOrder.filter { record.values[$0] != nil }
            if sites.count == 1, let site = sites.first, let value = record.values[site] {
                return "\(site.title) \(Fmt.number(value, decimals: 1)) cm"
            }
            return "Tape · \(sites.count) sites"
        case .assessment:
            let method = (record.method ?? .estimate).title
            if let bodyFat = record.values.bodyFat { return "Body fat \(percent(bodyFat)) · \(method)" }
            return "Lean and fat mass · \(method)"
        }
    }

    /// "Mon, 7 Jan · 07:10", with the device or "not standard" when it applies.
    static func detail(_ record: BodyHistoryRecord, today: DayKey) -> String {
        var parts = [Fmt.dayTitle(record.day, today: today), Fmt.clock(record.minutes)]
        if record.kind == .assessment, !record.device.isEmpty { parts.append(record.device) }
        if record.kind == .tape, !BodyProtocol.isStandard(record.conditions) { parts.append("not standard") }
        return parts.joined(separator: " · ")
    }

    static func percent(_ value: Double) -> String {
        Fmt.number(value, decimals: 1) + " %"
    }
}

// MARK: - Export from All measurements

/// The Import & Export menu of All measurements: save the weight & body history as a CSV file,
/// share it, copy it, or import one. Only Nina's own weigh-ins and measurements, never Apple Health
/// values.
struct BodyHistoryExportMenu: ViewModifier {
    @Environment(AppModel.self) private var app
    @State private var file: CSVFile?
    /// The CSV for the share sheet, made again when the data changes.
    @State private var csv = ""

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) { menu }
            }
            .fileExporter(isPresented: isSaving, document: file, contentType: .commaSeparatedText, defaultFilename: fileName) { result in
                if case .failure(let error) = result {
                    app.toasts.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
                }
            }
            .task(id: app.dataVersion) { csv = app.store.bodyHistoryExport() }
    }

    private var menu: some View {
        Menu {
            Button("Save as CSV File…", systemImage: "doc") {
                file = CSVFile(text: app.store.bodyHistoryExport())
            }
            ShareLink(item: BodyHistoryShareFile(text: csv), preview: SharePreview("Weight & Body (CSV)")) {
                Label("Share as CSV…", systemImage: "square.and.arrow.up")
            }
            Button("Copy as CSV", systemImage: "doc.on.doc") {
                Clipboard.copy(app.store.bodyHistoryExport())
                app.toasts.show("Weigh-ins and measurements copied", symbol: "doc.on.doc.fill")
            }
            Divider()
            Button("Import History…", systemImage: "square.and.arrow.down") {
                app.sheet = .importData(.measurements)
            }
        } label: {
            Label("Import & Export", systemImage: "square.and.arrow.up.on.square")
        }
    }

    private var isSaving: Binding<Bool> {
        Binding(get: { file != nil }, set: { if !$0 { file = nil } })
    }

    private var fileName: String {
        "\(AppInfo.name) \(ImportKind.measurements.title) \(app.today.rawValue)"
    }
}

/// The weight & body history as a CSV file for the share sheet.
struct BodyHistoryShareFile: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { (file: BodyHistoryShareFile) in
            ImportExports.fileData(file.text)
        }
        .suggestedFileName("Weight and Body.csv")
    }
}

extension View {
    /// Adds the weight & body history Import & Export menu (All measurements).
    func bodyHistoryExportMenu() -> some View {
        modifier(BodyHistoryExportMenu())
    }
}
