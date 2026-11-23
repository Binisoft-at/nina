import SwiftUI
import SwiftData
import NinaCore

/// My Plan → Earlier Versions: the plan as it was before each change. The store keeps one as a
/// `DayMark` of kind "planVersion" whenever the plan changes (key = the time, note = the plan's
/// text, meta "reason=…"; at most one per 10 minutes, the newest 30), synced like every mark –
/// no schema change. Restore puts one back through `app.updatePlan`, whose toast's Undo returns to
/// the plan before.
struct PlanEditorHistoryView: View {
    @Environment(AppModel.self) private var app
    @Query private var marks: [DayMark]
    @State private var restoring: PlanEditorVersion?

    init() {
        let kind = PlanEditorVersion.kind
        _marks = Query(filter: #Predicate<DayMark> { $0.kind == kind && $0.deletedAt == nil },
                       sort: [SortDescriptor(\DayMark.time, order: .reverse)])
    }

    private var versions: [PlanEditorVersion] {
        marks.compactMap { PlanEditorVersion($0) }
    }

    var body: some View {
        Form {
            if versions.isEmpty {
                Section {
                    Text("No earlier versions yet. Nina keeps one each time your plan changes.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(versions) { (version: PlanEditorVersion) in
                        row(version)
                    }
                } footer: {
                    Text("Each version is your plan just before a change. Restoring one replaces the plan you have now – the message that follows can undo it.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Earlier Versions")
        .inlineNavigationTitle()
        .confirmationDialog("Restore this version?", isPresented: restoreBinding, titleVisibility: .visible,
                            presenting: restoring) { (version: PlanEditorVersion) in
            Button("Restore") { restore(version) }
            Button("Cancel", role: .cancel) {}
        } message: { (version: PlanEditorVersion) in
            Text("Your plan goes back to how it was before \(version.whenText).")
        }
    }

    private func row(_ version: PlanEditorVersion) -> some View {
        let isCurrent = version.plan == app.settings.plan
        return Button {
            restoring = version
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("Before \(version.whenText)")
                    .foregroundStyle(.primary)
                Text(isCurrent ? "Same as your plan now" : version.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
    }

    private var restoreBinding: Binding<Bool> {
        Binding<Bool>(get: { restoring != nil }, set: { (shown: Bool) in if !shown { restoring = nil } })
    }

    private func restore(_ version: PlanEditorVersion) {
        guard version.plan != PlanEditorData.storedPlan(app) else { return }
        app.updatePlan(version.plan, message: "Plan from \(version.whenText) restored", symbol: "clock.arrow.circlepath")
    }
}

/// One saved plan version.
struct PlanEditorVersion: Identifiable {
    /// `DayMark.kind` of the versions (the store's `DayMarkKind.planVersion`).
    static let kind = "planVersion"

    let id: UUID
    let time: Date
    let plan: CoachPlan
    /// What changed the plan next: "checkIn", "editor", "import" (meta "reason").
    let reason: String

    init?(_ mark: DayMark) {
        let text = mark.note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        id = mark.uuid
        time = mark.time
        plan = CoachPlan(encoded: text)
        reason = mark.metaText["reason"] ?? ""
    }

    /// "3 Mar, 14:20".
    var whenText: String {
        "\(Fmt.shortDay(DayKey(date: time))), \(Fmt.time(time))"
    }

    /// "Check-in · 2 phases · 3 day types".
    var detail: String {
        var parts: [String] = []
        if let source = PlanEditorVersion.sourceTitle(reason) { parts.append(source) }
        if plan.isEmpty {
            parts.append("No plan")
        } else {
            let phases = plan.phases.count, types = plan.dayTypes.count
            parts.append(phases == 1 ? "1 phase" : "\(phases) phases")
            parts.append(types == 1 ? "1 day type" : "\(types) day types")
        }
        return parts.joined(separator: " · ")
    }

    /// The change that followed this version, in words.
    static func sourceTitle(_ reason: String) -> String? {
        switch reason {
        case "checkIn": "Then changed by a check-in"
        case "editor": "Then edited"
        case "import": "Then imported"
        case "": nil
        default: "Then changed"
        }
    }
}
