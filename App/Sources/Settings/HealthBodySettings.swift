import SwiftUI
import BinisoftKit
import NinaCore

#if os(iOS)
/// Settings → Apple Health → Body: what Nina reads of the body from Health (switches on this
/// device only, permission asked when one is first switched on), which method each app's body fat
/// counts as, and which day types a workout suggests. Nothing read here is ever stored.
struct HealthBodySettingsSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Section {
            ForEach(HealthBodyReader.Option.allCases) { option in
                optionToggle(option)
            }
        } header: {
            Text("Body")
                .info(SettingsInfo.bodyData.title, SettingsInfo.bodyData.text)
        } footer: {
            Text("Read live from Apple Health and never stored in Nina or its iCloud. Body fat and waist show as series of their own in Progress → Body, next to what you measure in Nina, and your height from Health as a hint in Goals & Plan. A workout only suggests the day type on Today – nothing changes until you tap.")
        }
        if app.health.bodyData.isOn(.bodyFat) {
            HealthBodySourcesSection()
        }
        if app.health.bodyData.isOn(.workouts) {
            HealthBodyWorkoutTypesSection()
        }
    }

    /// A switch; "Workouts suggest the day type" carries its own ⓘ (the header's covers the body data).
    @ViewBuilder
    private func optionToggle(_ option: HealthBodyReader.Option) -> some View {
        if option == .workouts {
            Toggle(isOn: binding(option)) {
                Text(option.title)
                    .info(SettingsInfo.workouts.title, SettingsInfo.workouts.text)
            }
        } else {
            Toggle(option.title, isOn: binding(option))
        }
    }

    private func binding(_ option: HealthBodyReader.Option) -> Binding<Bool> {
        let reader = app.health.bodyData
        return Binding<Bool>(
            get: { reader.options.contains(option) },
            set: { (on: Bool) in
                Task { await reader.set(option, on) }
            }
        )
    }
}

/// The apps that wrote body fat to Health, each with the method it counts as (device-only).
private struct HealthBodySourcesSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let sources = app.health.bodyData.sources
        Section {
            if sources.isEmpty {
                Text("No body-fat values from Apple Health yet. If Nina may not read them, allow it in the Health app: your picture → Apps → Nina.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sources) { source in
                    Picker(selection: methodBinding(source.id)) {
                        ForEach(HealthBody.methods) { (method: BodyMethod) in
                            Text(method.title).tag(method)
                        }
                    } label: {
                        HealthBodySourceLabel(source: source)
                    }
                }
            }
        } header: {
            Text("Body fat from")
        } footer: {
            Text("Each app is its own series, never mixed with your own values. Tell Nina how an app measures – a smart scale, a DEXA scan, a body scanner – so its values get the right error band. On this iPhone only.")
        }
    }

    private func methodBinding(_ source: String) -> Binding<BodyMethod> {
        let reader = app.health.bodyData
        return Binding<BodyMethod>(
            get: { reader.method(for: source) },
            set: { (method: BodyMethod) in reader.relabel(source, as: method) }
        )
    }
}

/// "Body Scale" over "8 values · latest 3 Jan".
private struct HealthBodySourceLabel: View {
    let source: HealthBodySource

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(source.name)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var detail: String {
        let values = source.count == 1 ? "1 value" : "\(source.count) values"
        return "\(values) · latest \(Fmt.shortDay(DayKey(date: source.latest)))"
    }
}

/// The day types whose workouts suggest them ("🎾 Tennis  tennis").
private struct HealthBodyWorkoutTypesSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let types = HealthWorkouts.mappedTypes(in: app.settings.plan)
        Section {
            if types.isEmpty {
                Text("None of your day types lists a workout yet. Add one in My Plan: tap a day type, then Apple Health Workouts.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(types) { (type: CoachPlan.DayType) in
                    LabeledContent(title(of: type), value: type.workouts.joined(separator: ", "))
                }
            }
        } header: {
            Text("Workouts that suggest a day type")
        } footer: {
            Text("When today follows your schedule's default day and Apple Health has a finished workout of one of these kinds, Today asks whether to switch. Only your tap changes the day.")
        }
    }

    private func title(of type: CoachPlan.DayType) -> String {
        let emoji = type.todayCoachEmoji
        return emoji.isEmpty ? type.name : "\(emoji) \(type.name)"
    }
}
#endif
