import SwiftUI
import BinisoftKit
import NinaCore

// The pages of the measure pager (a new tape session in `MeasureSheet`, one site per page): the
// site page with its outline drawing, the big first reading with ±0.1 buttons, more readings when
// they're wanted, and the live tape estimate on the last page. The sheet itself (state, the start
// page, Next/Skip/Done and saving) is in BodySheets+Measure.swift.

/// One site of a new tape session: where the tape goes (a small outline drawing and the
/// landmark), the first reading as one big number that shows last time's value until a reading
/// is typed, the change since then, and the 2nd and 3rd readings when they're wanted.
struct BodySheetSitePage: View {
    let state: BodySheetSiteState
    let title: String
    let hint: String
    let sites: [BodySite]
    let measured: Set<BodySite>
    /// "Morning, Before eating"
    let conditions: String
    /// The tape estimate (last page only).
    let estimate: BodySheetEstimateLine?
    @Binding var texts: [String]
    @Binding var formula: String
    var focus: FocusState<BodySheetMeasureFocus?>.Binding
    /// Opens the start page (conditions, time, note).
    let showStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                heading
                BodySheetFigure(site: state.site)
                    .frame(height: 150)
                readingCard
                if let estimate {
                    BodySheetEstimateCard(line: estimate, formula: $formula)
                }
            }
            .padding()
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .background(Color.groupedBackground)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            if sites.count > 1 {
                Text(positionText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                BodySheetPagerDots(sites: sites, current: state.site, measured: measured)
            }
            Spacer(minLength: 8)
            Button(action: showStart) {
                Label(conditions, systemImage: "checklist")
                    .font(.caption)
                    .lineLimit(1)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Conditions: \(conditions)")
            .accessibilityHint("Shows the measuring guide, conditions, time and note.")
        }
    }

    /// "2 of 6"
    private var positionText: String {
        let index = (sites.firstIndex(of: state.site) ?? 0) + 1
        return "\(index) of \(sites.count)"
    }

    private var heading: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.title2.weight(.bold))
            Text(hint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Readings

    private var readingCard: some View {
        VStack(spacing: 12) {
            BodySheetBigReading(text: field(0), site: state.site, title: title, previous: state.previous?.value,
                                focus: focus)
            changeRow
            if state.fieldCount > 1 {
                extraReadings
            }
            if let message = state.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(state.isInvalid ? Color.red : Color.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    /// "Last 84.2 cm · 7 Jan" (with "Same as Last Time" while empty), then "−0.3 cm since 7 Jan".
    private var changeRow: some View {
        HStack(spacing: 12) {
            Text(state.previousText ?? "No earlier value yet.")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            if let previous = state.previous, BodySheetReadings.isEmpty(texts, at: 0) {
                Button("Same as Last Time") {
                    setText(BodySheetNumber.cm(previous.value), at: 0)
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
            }
        }
    }

    private var extraReadings: some View {
        HStack(spacing: 12) {
            ForEach(1..<state.fieldCount, id: \.self) { index in
                BodySheetExtraReading(text: field(index), index: index, site: state.site, title: title,
                                      fallback: state.values.first ?? state.previous?.value, focus: focus,
                                      about: index == 1 ? readingsInfo : nil)
            }
        }
    }

    /// Why there is more than one reading: a full set's two, or the weekly re-check.
    private var readingsInfo: BodyPageInfo {
        BodyPageInfo.readings(twoReadings: state.base >= 2)
    }

    private func field(_ index: Int) -> Binding<String> {
        Binding(
            get: { index < texts.count ? texts[index] : "" },
            set: { value in setText(value, at: index) }
        )
    }

    private func setText(_ value: String, at index: Int) {
        var list = texts
        while list.count <= index { list.append("") }
        list[index] = value
        texts = list
    }
}

/// The first reading of a site as one big number with −/+ 0.1 cm buttons (they repeat when
/// held, and VoiceOver adjusts it in 0.1 cm steps). Empty, it shows last time's value in grey;
/// the buttons then step from it.
struct BodySheetBigReading: View {
    @Binding var text: String
    let site: BodySite
    let title: String
    let previous: Double?
    var focus: FocusState<BodySheetMeasureFocus?>.Binding

    var body: some View {
        HStack(spacing: 12) {
            stepButton(-0.1, symbol: "minus", label: "Minus 0.1 centimeters")
            number
                .frame(maxWidth: .infinity)
            stepButton(0.1, symbol: "plus", label: "Plus 0.1 centimeters")
        }
    }

    private var number: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            TextField(title, text: $text, prompt: Text(placeholder))
                .focused(focus, equals: BodySheetMeasureFocus(site: site, index: 0))
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.system(size: 54, weight: .semibold, design: .rounded).monospacedDigit())
                .multilineTextAlignment(.center)
                .fixedSize()
                .accessibilityLabel("\(title) in centimeters")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: step(0.1)
                    case .decrement: step(-0.1)
                    default: break
                    }
                }
            Text("cm")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    /// Last time's value, else zero with the decimal separator people type here ("0.0", "0,0").
    private var placeholder: String {
        guard let previous else { return BodySheetNumber.text(0) }
        return BodySheetNumber.cm(previous)
    }

    private func stepButton(_ amount: Double, symbol: String, label: String) -> some View {
        Button {
            step(amount)
        } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Color.secondary.opacity(0.14), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.borderless)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }

    private func step(_ amount: Double) {
        text = BodySheetNumber.stepped(text, by: amount, fallback: previous, range: site.plausibleRange)
    }
}

/// The 2nd or 3rd reading of a site. VoiceOver adjusts it in 0.1 cm steps (from the first
/// reading while it is empty).
struct BodySheetExtraReading: View {
    @Binding var text: String
    let index: Int
    let site: BodySite
    let title: String
    let fallback: Double?
    var focus: FocusState<BodySheetMeasureFocus?>.Binding
    /// The ⓘ next to the title (on the 2nd reading only).
    var about: BodyPageInfo?

    var body: some View {
        VStack(spacing: 4) {
            caption
            field
        }
    }

    @ViewBuilder
    private var caption: some View {
        let heading = Text(BodySheetReadings.readingTitle(index))
            .font(.caption)
            .foregroundStyle(.secondary)
        if let about {
            heading.info(about)
        } else {
            heading
        }
    }

    private var field: some View {
        TextField(BodySheetReadings.readingTitle(index), text: $text, prompt: Text("cm"))
            .focused(focus, equals: BodySheetMeasureFocus(site: site, index: index))
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
            .labelsHidden()
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.title2.monospacedDigit())
            .accessibilityLabel("\(title), reading \(index + 1)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(0.1)
                case .decrement: step(-0.1)
                default: break
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 10, style: .continuous))
    }

    private func step(_ amount: Double) {
        text = BodySheetNumber.stepped(text, by: amount, fallback: fallback, range: site.plausibleRange)
    }
}

/// One dot per site: filled once it has a value, the current one a little larger.
struct BodySheetPagerDots: View {
    let sites: [BodySite]
    let current: BodySite
    let measured: Set<BodySite>

    var body: some View {
        HStack(spacing: 5) {
            ForEach(sites) { site in
                Circle()
                    .fill(color(for: site))
                    .frame(width: size(for: site), height: size(for: site))
            }
        }
        .accessibilityHidden(true)
    }

    private func size(for site: BodySite) -> CGFloat {
        site == current ? 8 : 6
    }

    private func color(for site: BodySite) -> Color {
        if measured.contains(site) { return Brand.accent }
        return site == current ? Color.primary.opacity(0.45) : Color.secondary.opacity(0.3)
    }
}

/// The live tape estimate of body fat on the last page (worked out, never saved).
struct BodySheetEstimateCard: View {
    let line: BodySheetEstimateLine
    @Binding var formula: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tape estimate")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .info(BodyPageInfo.tapeEstimate)
            content
            Text(line.footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private var content: some View {
        switch line {
        case .value(let bodyFat):
            Text(verbatim: "\(Fmt.number(bodyFat, decimals: 1)) % body fat")
                .font(.title3.weight(.semibold).monospacedDigit())
        case .needsHeight:
            Text("Add your height in Goals & Plan to see a body-fat estimate from your tape values.")
        case .needsFormula:
            Picker("Formula", selection: $formula) {
                Text("Choose").tag("")
                ForEach(NavyBodyFat.Formula.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
        case .needsSites(let missing):
            Text(BodySheetEstimateLine.sitesText(missing))
        case .implausible:
            Text("These values don't give a plausible estimate – a typo?")
        }
    }
}

// MARK: - Outline drawing

/// A simple front outline of a person with the spot of a site highlighted. It is drawn as in the
/// mirror you measure in: the right arm, thigh and calf are on the right.
struct BodySheetFigure: View {
    let site: BodySite

    var body: some View {
        ZStack {
            BodySheetOutline()
                .stroke(Color.secondary.opacity(0.6),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            BodySheetSpot(site: site)
                .stroke(Brand.accent.opacity(0.25), style: StrokeStyle(lineWidth: 10, lineCap: .round))
            BodySheetSpot(site: site)
                .stroke(Brand.accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        }
        .aspectRatio(0.5, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Maps points of a 100 × 200 drawing into a rect.
struct BodySheetFigureScale {
    let rect: CGRect

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + x / 100 * rect.width, y: rect.minY + y / 200 * rect.height)
    }

    func box(_ x: CGFloat, _ y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(origin: point(x, y), size: CGSize(width: width / 100 * rect.width, height: height / 200 * rect.height))
    }
}

/// The outline: head, torso and legs in one line, and the two arms.
struct BodySheetOutline: Shape {
    func path(in rect: CGRect) -> Path {
        BodySheetFigureDrawing.outline(in: rect)
    }
}

/// The highlighted spot of a site: a line across the outline at its height.
struct BodySheetSpot: Shape {
    let site: BodySite

    func path(in rect: CGRect) -> Path {
        BodySheetFigureDrawing.spot(site, in: rect)
    }
}

/// The paths of the outline drawing (plain functions, no view).
enum BodySheetFigureDrawing {
    static func outline(in rect: CGRect) -> Path {
        let scale = BodySheetFigureScale(rect: rect)
        var path = Path()
        path.addEllipse(in: scale.box(40, 2, width: 20, height: 20))
        addBody(to: &path, scale)
        addArm(to: &path, scale, mirrored: false)
        addArm(to: &path, scale, mirrored: true)
        return path
    }

    static func spot(_ site: BodySite, in rect: CGRect) -> Path {
        let scale = BodySheetFigureScale(rect: rect)
        let spot = line(for: site)
        var path = Path()
        path.move(to: scale.point(spot.from, spot.y))
        path.addLine(to: scale.point(spot.to, spot.y))
        return path
    }

    /// Where the line goes in the 100 × 200 drawing: its height and its left and right end.
    static func line(for site: BodySite) -> (y: CGFloat, from: CGFloat, to: CGFloat) {
        switch site {
        case .neck: return (27, 43, 57)
        case .chest: return (50, 27, 73)
        case .waistNarrow: return (63, 31, 69)
        case .waist: return (72, 32, 68)
        case .hip: return (93, 28, 72)
        case .arm: return (58, 70, 82)
        case .armLeft: return (58, 18, 30)
        case .armFlexed: return (54, 70, 82)
        case .thigh: return (122, 51, 69)
        case .thighLeft: return (122, 31, 49)
        case .calf: return (160, 51, 65)
        case .calfLeft: return (160, 35, 49)
        }
    }

    /// Down the right side from the neck to the right foot, up the inside legs, down to the left
    /// foot and up the left side to the neck.
    private static func addBody(to path: inout Path, _ scale: BodySheetFigureScale) {
        path.move(to: scale.point(55, 22))
        path.addLine(to: scale.point(55, 29))
        path.addQuadCurve(to: scale.point(72, 37), control: scale.point(70, 30))
        path.addLine(to: scale.point(71, 52))
        path.addQuadCurve(to: scale.point(66, 70), control: scale.point(66, 60))
        path.addQuadCurve(to: scale.point(70, 94), control: scale.point(71, 82))
        path.addLine(to: scale.point(66, 138))
        path.addLine(to: scale.point(61, 188))
        path.addLine(to: scale.point(64, 194))
        path.addLine(to: scale.point(52, 194))
        path.addLine(to: scale.point(52, 138))
        path.addLine(to: scale.point(50, 106))
        path.addLine(to: scale.point(48, 138))
        path.addLine(to: scale.point(48, 194))
        path.addLine(to: scale.point(36, 194))
        path.addLine(to: scale.point(39, 188))
        path.addLine(to: scale.point(34, 138))
        path.addLine(to: scale.point(30, 94))
        path.addQuadCurve(to: scale.point(34, 70), control: scale.point(29, 82))
        path.addQuadCurve(to: scale.point(29, 52), control: scale.point(34, 60))
        path.addLine(to: scale.point(28, 37))
        path.addQuadCurve(to: scale.point(45, 29), control: scale.point(30, 30))
        path.addLine(to: scale.point(45, 22))
    }

    /// An arm hanging from the shoulder (the right one, or mirrored the left one).
    private static func addArm(to path: inout Path, _ scale: BodySheetFigureScale, mirrored: Bool) {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            scale.point(mirrored ? 100 - x : x, y)
        }
        path.move(to: point(73, 38))
        path.addQuadCurve(to: point(83, 100), control: point(81, 62))
        path.addQuadCurve(to: point(77, 100), control: point(80, 104))
        path.addQuadCurve(to: point(71, 52), control: point(76, 70))
    }
}
