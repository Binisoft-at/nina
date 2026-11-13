import SwiftUI
import SwiftData
import NinaCore

/// Log on the wrist: dictate or scribble a whole meal, or pick a favourite, a recent food or a
/// saved meal and set the amount with the Digital Crown.
struct WatchLogView: View {
    @Environment(WatchModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Recipe> { $0.deletedAt == nil && $0.kind == "meal" }, sort: \Recipe.name) private var meals: [Recipe]
    @State private var meal = ""
    @State private var spoken: String?

    var body: some View {
        List {
            Section {
                TextFieldLink(prompt: Text("\u{201C}2 eggs and a toast\u{201D}")) {
                    Label("Say or Write It", systemImage: "mic.fill")
                        .foregroundStyle(Color.accentColor)
                } onSubmit: { text in
                    spoken = text
                }
                Picker("Meal", selection: $meal) {
                    ForEach(model.settings.meals) { slot in Text("\(slot.emoji) \(slot.name)").tag(slot.id) }
                }
            }
            if !meals.isEmpty {
                Section("Your meals") {
                    ForEach(meals) { recipe in
                        Button {
                            model.logRecipe(recipe, meal: meal)
                            dismiss()
                        } label: {
                            HStack {
                                Text(recipe.symbol)
                                Text(recipe.displayName).lineLimit(1)
                                Spacer()
                                Text(Fmt.energy(recipe.totals.energy, unit: model.settings.energyUnit, showUnit: false))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            let favorites = model.library.favorites.filter { $0.ref.kind != .recipe }
            if !favorites.isEmpty {
                Section("Favorites") {
                    ForEach(favorites.prefix(15)) { record in foodLink(record) }
                }
            }
            let recents = model.library.recents(limit: 20).filter { !$0.isFavorite && $0.ref.kind != .recipe }
            if !recents.isEmpty {
                Section("Recent") {
                    ForEach(recents) { record in foodLink(record) }
                }
            }
        }
        .navigationTitle("Log")
        .onAppear { if meal.isEmpty { meal = model.settings.suggestedMeal().id } }
        .sheet(item: Binding(get: { spoken.map(SpokenText.init) }, set: { spoken = $0?.text })) { item in
            WatchQuickConfirmView(text: item.text, meal: meal) {
                spoken = nil
                dismiss()
            }
        }
    }

    private func foodLink(_ record: FoodRecord) -> some View {
        NavigationLink {
            WatchAmountView(record: record, meal: meal)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(record.displayName(model.settings.language)).lineLimit(2)
                Text("\(Fmt.energy(record.nutrients(forAmount: record.defaultAmount).energy, unit: model.settings.energyUnit)) · \(record.category.emoji)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SpokenText: Identifiable {
    let text: String
    var id: String { text }
}

/// What the dictated text was understood as; one tap logs it all.
struct WatchQuickConfirmView: View {
    let text: String
    let meal: String
    let onDone: () -> Void

    @Environment(WatchModel.self) private var model

    var body: some View {
        let matches = model.library.quickMatches(text)
        let resolved = matches.filter(\.isResolved)
        let energy = resolved.map(\.nutrients.energy).reduce(0, +)
        List {
            ForEach(matches) { match in
                VStack(alignment: .leading, spacing: 1) {
                    Text(match.food?.displayName(model.settings.language) ?? (match.item.isEnergyOnly ? "Quick entry" : "\u{201C}\(match.item.query)\u{201D} not found"))
                        .foregroundStyle(match.isResolved ? Color.primary : Color.secondary)
                    if let amount = match.amountText {
                        Text("\(Fmt.amount(amount)) · \(Fmt.energy(match.nutrients.energy, unit: model.settings.energyUnit))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                model.logMatches(resolved, meal: meal)
                onDone()
            } label: {
                Label("Add · \(Fmt.energy(energy, unit: model.settings.energyUnit))", systemImage: "checkmark")
            }
            .disabled(resolved.isEmpty)
            .tint(Color.accentColor)
        }
        .navigationTitle("Understood")
    }
}

/// The Digital Crown sets the amount: portions in halves, grams in steps of 5.
struct WatchAmountView: View {
    let record: FoodRecord
    let meal: String

    @Environment(WatchModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var value = 1.0
    @State private var usePortion = true

    private var portion: Serving? { record.servings.first }
    private var amount: AmountText {
        if usePortion, let portion {
            return AmountText(quantity: value, unitLabel: portion.label(model.settings.language), unitAmount: portion.amount, baseUnit: record.unit)
        }
        return AmountText(quantity: value, unitLabel: record.unit.symbol, unitAmount: 1, baseUnit: record.unit)
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(record.displayName(model.settings.language))
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(Fmt.amount(amount))
                .font(.system(.title3, design: .rounded, weight: .semibold).monospacedDigit())
                .focusable()
                .digitalCrownRotation($value, from: usePortion ? 0.5 : 5, through: usePortion ? 12 : 2000,
                                      by: usePortion ? 0.5 : 5, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
            Text(Fmt.energy(record.nutrients(forAmount: amount.total).energy, unit: model.settings.energyUnit))
                .foregroundStyle(Color.accentColor)
            if portion != nil {
                Button(usePortion ? "Use \(record.unit.symbol)" : "Use portions") {
                    let total = amount.total
                    usePortion.toggle()
                    if usePortion, let portion {
                        value = max(0.5, (total / portion.amount * 2).rounded() / 2)
                    } else {
                        value = max(5, (total / 5).rounded() * 5)
                    }
                }
                .font(.caption2)
                .buttonStyle(.borderless)
            }
            Button {
                model.log(record, amount: amount, meal: meal)
                dismiss()
            } label: {
                Label("Add", systemImage: "plus")
            }
            .tint(Color.accentColor)
        }
        .padding(.horizontal, 4)
        .onAppear {
            if record.usualAmount > 0, let portion, abs(record.usualAmount / portion.amount - (record.usualAmount / portion.amount).rounded()) < 0.05 {
                value = max(0.5, (record.usualAmount / portion.amount).rounded())
            } else if record.usualAmount > 0 || portion == nil {
                usePortion = false
                value = record.usualAmount > 0 ? record.usualAmount.rounded() : record.unit.basis
            }
        }
    }
}

/// Dial a number of calories with the crown.
struct WatchQuickCaloriesView: View {
    @Environment(WatchModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var kilocalories = 300.0

    var body: some View {
        VStack(spacing: 8) {
            Text("\(Int(kilocalories))")
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                .focusable()
                .digitalCrownRotation($kilocalories, from: 10, through: 3000, by: 10, sensitivity: .medium,
                                      isContinuous: false, isHapticFeedbackEnabled: true)
            Text("kcal").foregroundStyle(.secondary)
            Button {
                model.quick(kilocalories, meal: model.settings.suggestedMeal().id)
                dismiss()
            } label: {
                Label("Add to \(model.settings.suggestedMeal().name)", systemImage: "bolt.fill")
            }
            .tint(.orange)
        }
        .navigationTitle("Quick")
    }
}
