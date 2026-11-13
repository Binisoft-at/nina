import SwiftUI
import BinisoftKit
import NinaCore

/// How much: a number and a unit (the food's portions, g or ml, servings), with quick chips.
/// Switching the unit keeps the amount the same where it can (150 g → 5 × slice of 30 g).
struct AmountPicker: View {
    let record: FoodRecord
    let language: FoodLanguage
    @Binding var amount: AmountText

    @State private var text = ""
    @FocusState private var focused: Bool

    struct UnitOption: Hashable, Identifiable {
        let label: String
        let amount: Double
        var id: String { label + "|" + NumberText.plain(amount) }
    }

    private var options: [UnitOption] {
        var result = record.servings.map { UnitOption(label: $0.label(language), amount: $0.amount) }
        switch record.unit {
        case .gram: result.append(UnitOption(label: "g", amount: 1))
        case .milliliter:
            result.append(UnitOption(label: "ml", amount: 1))
            result.append(UnitOption(label: "g", amount: 1 / max(record.density, 0.1)))
        case .serving: result.append(UnitOption(label: BaseUnit.serving.symbol, amount: 1))
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.label).inserted }
    }

    private var selectedOption: UnitOption {
        options.first { $0.label == amount.unitLabel && abs($0.amount - amount.unitAmount) < 0.0001 }
            ?? options.first { $0.label == amount.unitLabel }
            ?? UnitOption(label: amount.unitLabel, amount: amount.unitAmount)
    }

    private var quickValues: [Double] {
        if selectedOption.amount == 1, ["g", "ml"].contains(selectedOption.label) {
            return record.unit == .milliliter ? [100, 200, 250, 330, 500] : [25, 50, 100, 150, 200, 250]
        }
        return [0.5, 1, 1.5, 2, 3]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Amount", text: $text)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .focused($focused)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .frame(minWidth: 70, maxWidth: 120)
                    .onChange(of: text) { _, newValue in
                        if let value = NumberText.parse(newValue), value > 0, value != amount.quantity {
                            amount.quantity = value
                        }
                    }
                Picker("Unit", selection: Binding(get: { selectedOption }, set: { change(to: $0) })) {
                    ForEach(options) { option in
                        Text(optionTitle(option)).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                Spacer(minLength: 0)
                Stepper("Adjust", onIncrement: { step(+1) }, onDecrement: { step(-1) })
                    .labelsHidden()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(quickValues, id: \.self) { value in
                        Button {
                            amount.quantity = value
                            text = AmountText.quantity(value)
                        } label: {
                            Chip(text: AmountText.quantity(value), tint: Brand.accent, isSelected: abs(amount.quantity - value) < 0.0001)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear { text = AmountText.quantity(amount.quantity) }
        .onChange(of: amount.quantity) { _, newValue in
            if NumberText.parse(text) != newValue { text = AmountText.quantity(newValue) }
        }
        .sensoryFeedback(.selection, trigger: amount.quantity)
    }

    private func optionTitle(_ option: UnitOption) -> String {
        if option.amount == 1, ["g", "ml", BaseUnit.serving.symbol].contains(option.label) { return option.label }
        let base = record.unit == .serving ? "" : " (\(Fmt.number(option.amount, decimals: option.amount < 10 ? 1 : 0)) \(record.unit.symbol))"
        return option.label + base
    }

    private func change(to option: UnitOption) {
        let total = amount.total
        var quantity = option.amount > 0 ? total / option.amount : 1
        if option.amount > 1 || option.label == BaseUnit.serving.symbol {
            quantity = max(0.25, (quantity * 4).rounded() / 4)
        } else {
            quantity = max(1, quantity.rounded())
        }
        amount = AmountText(quantity: quantity, unitLabel: option.label, unitAmount: option.amount, baseUnit: record.unit)
        text = AmountText.quantity(quantity)
    }

    private func step(_ direction: Double) {
        let isBase = selectedOption.amount == 1 && ["g", "ml"].contains(selectedOption.label)
        let increment = isBase ? (amount.quantity >= 100 ? 10 : 5) : 0.5
        let next = max(isBase ? 1 : 0.25, amount.quantity + direction * increment)
        amount.quantity = next
        text = AmountText.quantity(next)
    }
}

/// Energy and macros of an amount, with the share of the day's targets.
struct NutritionPreview: View {
    let values: NutrientValues
    let targets: DailyTargets
    let unit: EnergyUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.energy(values.energy, unit: unit))
                    .font(.title.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText(value: values.energy))
                Spacer()
                if targets.energy > 0 {
                    Text("\(Fmt.percent(values.energy / targets.energy)) of your day")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                ForEach(Nutrient.macros, id: \.self) { nutrient in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(nutrient.shortTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(Fmt.nutrient(values[nutrient], nutrient))
                            .font(.headline.monospacedDigit())
                        if let target = targets.target(for: nutrient), target > 0 {
                            ProgressView(value: min(values.value(nutrient) / target, 1))
                                .tint(NutrientStyle.color(nutrient))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .animation(.smooth, value: values.energy)
    }
}
