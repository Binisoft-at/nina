import SwiftUI
import NinaCore

/// Settings → Thalia, in German (the owner's choice; the rest of Nina is English): the switch "An
/// Thalia liefern" – one setting for all devices –, when this device last wrote the day values, and
/// the hint. Off empties the values once on every device; on writes them all again at once
/// (docs/THALIA.md). `ThaliaDelivery` (App/Sources/Services/ThaliaExchange.swift) does the work.
struct ThaliaSettingsSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let thalia = app.thalia
        Section {
            Toggle(isOn: Binding(get: { thalia.isOn }, set: { thalia.setDeliver($0) })) {
                Label("An Thalia liefern", systemImage: "arrow.up.forward.app")
            }
            Text(thalia.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } header: {
            Text("Thalia")
        } footer: {
            Text("Thalia übernimmt die Werte, sobald Thalia auf diesem Gerät geöffnet wird.")
        }
        // Switched on another device: shows (and empties or writes) right away.
        .onAppear { thalia.checkSwitch() }
    }
}
