#if os(iOS)
import WidgetKit
import SwiftUI
import AppIntents

// Controls for Control Center, the Lock Screen and the Action button (iOS 18 and later). Each one
// runs an intent from WidgetBridge.swift that opens Nina at the right place: Log Food for the
// meal that fits the time, the weigh-in sheet, or a glass of water added with Undo. The intents
// are compiled into the app and this extension; the app runs them.

/// "Log Food": opens Nina at Log Food.
struct NinaLogFoodControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "NinaControl.logFood") {
            ControlWidgetButton(action: NinaOpenLogFoodIntent()) {
                Label("Log Food", systemImage: "fork.knife")
            }
        }
        .displayName("Log Food")
        .description("Opens Nina at Log Food for the meal that fits the time.")
    }
}

/// "Weigh In": opens Nina at the weigh-in sheet.
struct NinaWeighInControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "NinaControl.weighIn") {
            ControlWidgetButton(action: NinaOpenWeighInIntent()) {
                Label("Weigh In", systemImage: "scalemass.fill")
            }
        }
        .displayName("Weigh In")
        .description("Opens Nina at the weigh-in.")
    }
}

/// "Add Water": opens Nina and adds a glass of water (Undo in the message).
struct NinaAddWaterControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "NinaControl.addWater") {
            ControlWidgetButton(action: NinaOpenAddWaterIntent()) {
                Label("Add Water", systemImage: "drop.fill")
            }
        }
        .displayName("Add Water")
        .description("Opens Nina and adds a glass of water – your glass size from Settings.")
    }
}
#endif
