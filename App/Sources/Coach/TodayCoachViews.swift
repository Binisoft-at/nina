import SwiftUI
import BinisoftKit
import NinaCore

// MARK: - Day type

/// The day-type choices of a day, for the chip's menu and the week strip's touch-and-hold menu:
/// every type with the day's kcal if picked (and the flexible count), and "Back to Schedule" when
/// the day was set by hand. Picking writes a day-type mark with an Undo toast.
struct TodayCoachDayTypeMenu: View {
    let chip: CoachBoard.Chip
    let day: DayKey

    @Environment(AppModel.self) private var app

    var body: some View {
        ForEach(chip.options) { option in
            Button {
                pick(option)
            } label: {
                optionLabel(option)
            }
        }
        if chip.isManual {
            Divider()
            Button("Back to Schedule", systemImage: "calendar.badge.clock") {
                _ = app.setDayType(nil, on: day)
            }
        }
    }

    @ViewBuilder
    private func optionLabel(_ option: CoachBoard.ChipOption) -> some View {
        let title = [option.emoji, option.name].filter { !$0.isEmpty }.joined(separator: " ")
        let detail = optionDetail(option)
        #if os(iOS)
        if option.isSelected {
            Label {
                Text(title)
                Text(detail)
            } icon: {
                Image(systemName: "checkmark")
            }
        } else {
            Text(title)
            Text(detail)
        }
        #else
        if option.isSelected {
            Label("\(title) · \(detail)", systemImage: "checkmark")
        } else {
            Text("\(title) · \(detail)")
        }
        #endif
    }

    /// "2,600 kcal · 1 of 2 this week"
    private func optionDetail(_ option: CoachBoard.ChipOption) -> String {
        let parts: [String?] = [Fmt.energy(option.energy, unit: app.energyUnit), option.quotaText]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private func pick(_ option: CoachBoard.ChipOption) {
        guard !option.isSelected else { return }
        _ = app.setDayType(option.id, on: day)
    }
}

/// The day type at the top of the summary card: "🏋️ Gym day" or "🎾 Tennis · 1 of 2 this week".
/// Filled when picked by hand, outlined when it comes from the schedule; a tap opens the
/// day-type menu.
struct TodayCoachChip: View {
    let chip: CoachBoard.Chip
    let day: DayKey

    var body: some View {
        Menu {
            TodayCoachDayTypeMenu(chip: chip, day: day)
        } label: {
            chipFace
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Choose the day type")
    }

    private var text: String {
        let name = chip.quotaText ?? chip.title
        return chip.emoji.isEmpty ? name : "\(chip.emoji) \(name)"
    }

    private var accessibilityText: String {
        let source = chip.isManual ? "picked by hand" : "from your schedule"
        return "Day type: \(chip.quotaText ?? chip.title), \(source)"
    }

    @ViewBuilder
    private var chipFace: some View {
        let face = HStack(spacing: 5) {
            Text(text)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(.capsule)
        // Content on the summary card: tinted capsules (glass is for floating controls).
        if chip.isManual {
            face
                .foregroundStyle(Color.white)
                .background(Brand.accent, in: .capsule)
        } else {
            face
                .foregroundStyle(Brand.accent)
                .background(Brand.accent.opacity(0.1), in: .capsule)
                .overlay {
                    Capsule().strokeBorder(Brand.accent.opacity(0.5), lineWidth: 1)
                }
        }
    }
}

// MARK: - Checks strip

/// The checks strip under the summary card: the weigh-in, due measurements and the plan's daily
/// checks as tinted pills, shown only while something is open. A tap acts (a sheet, or a tick with
/// Undo); touch and hold a check for "Not Today". Right after a weigh-in the weigh-in pill shows
/// the weight and the 7-day average for 2 seconds, then the strip moves on or collapses. An ⓘ
/// after the last pill says what the strip is.
struct TodayCoachStrip: View {
    let day: DayKey
    let input: TodayCoachStripInput

    @State private var shown: [CoachBoard.StripItem]
    /// The weigh-in pill's text while it shows the saved weight.
    @State private var flash: String? = nil
    /// The pills to show once the flash is over.
    @State private var pending: [CoachBoard.StripItem]? = nil

    init(day: DayKey, input: TodayCoachStripInput) {
        self.day = day
        self.input = input
        _shown = State(initialValue: input.items)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !shown.isEmpty {
                pills
                    .padding(.top, 10)
                    .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: input) { old, new in
            update(from: old, to: new)
        }
    }

    private var pills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(shown) { item in
                    TodayCoachPill(item: item, day: day, flash: item.kind == .weighIn ? flash : nil)
                        .transition(AnyTransition.scale(scale: 0.8).combined(with: .opacity))
                }
                InfoButton(TodayInfo.checks.title, TodayInfo.checks.text)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        // No grey edge band behind the pills, and pills aren't cut off at the row's edges.
        .scrollEdgeEffectHidden(true, for: .horizontal)
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Checks")
    }

    private var spring: Animation { .spring(duration: 0.45, bounce: 0.2) }

    private func update(from old: TodayCoachStripInput, to new: TodayCoachStripInput) {
        if flash != nil {
            pending = new.items
            return
        }
        guard old.isLoaded else {
            shown = new.items
            return
        }
        let hadOpenWeighIn = shown.contains { $0.kind == .weighIn && $0.state == .open }
        let weighInGone = !new.items.contains { $0.kind == .weighIn }
        if hadOpenWeighIn, weighInGone, old.weighIn == nil, let weighIn = new.weighIn {
            showSaved(weighIn.text, then: new.items)
        } else {
            withAnimation(spring) {
                shown = new.items
            }
        }
    }

    /// The weigh-in pill reads "74.2 · avg 74.6" for 2 seconds, then the strip catches up.
    private func showSaved(_ text: String, then next: [CoachBoard.StripItem]) {
        pending = next
        withAnimation(.snappy) {
            flash = text
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(spring) {
                shown = pending ?? shown
                pending = nil
                flash = nil
            }
        }
    }
}

/// One pill of the checks strip. Open: icon, title and "overdue 3 days"; done: a check mark;
/// skipped ("Not Today"): a dash.
private struct TodayCoachPill: View {
    let item: CoachBoard.StripItem
    let day: DayKey
    let flash: String?

    @Environment(AppModel.self) private var app

    /// The check's id (daily checks only).
    private var checkID: String? {
        if case .check(let id) = item.action { return id }
        return nil
    }

    var body: some View {
        if checkID != nil {
            button
                .contextMenu { checkMenu }
        } else {
            button
        }
    }

    private var button: some View {
        Button {
            // While it shows the saved weight the pill only reports (no dimmed "disabled" look).
            guard flash == nil else { return }
            app.perform(item.action, on: day)
        } label: {
            face
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: item.state)
        .accessibilityLabel(labelText)
        .accessibilityHint(hintText)
    }

    @ViewBuilder
    private var face: some View {
        if let flash {
            savedFace(flash)
        } else if item.state == .done {
            compactFace(symbol: "checkmark", tint: Brand.accent)
        } else if item.state == .skipped {
            compactFace(symbol: "minus", tint: nil)
        } else {
            openFace
        }
    }

    private var openFace: some View {
        HStack(spacing: 6) {
            icon
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                if let detail = item.detail {
                    Text(detail)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.orange)
                }
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minHeight: 36)
        .background(Brand.accent.opacity(0.1), in: .capsule)
        .contentShape(.capsule)
    }

    @ViewBuilder
    private var icon: some View {
        if !item.emoji.isEmpty {
            Text(item.emoji)
        } else {
            Image(systemName: item.symbol.isEmpty ? "circle" : item.symbol)
                .foregroundStyle(Brand.accent)
        }
    }

    /// A 36 pt circle with a 44 pt tap area.
    private func compactFace(symbol: String, tint: Color?) -> some View {
        let fill: Color = tint ?? Color.secondary.opacity(0.15)
        return Image(systemName: symbol)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(tint == nil ? Color.secondary : Color.white)
            .frame(width: 36, height: 36)
            .background(fill, in: .circle)
            .frame(width: 44, height: 44)
            .contentShape(.rect)
    }

    private func savedFace(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.subheadline.weight(.bold))
            Text(text)
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .lineLimit(1)
        .foregroundStyle(Color.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minHeight: 36)
        .background(Brand.accent, in: .capsule)
    }

    @ViewBuilder
    private var checkMenu: some View {
        if let id = checkID {
            if item.state != .done {
                Button("Done", systemImage: "checkmark.circle") { _ = app.setCheck(id, on: day, state: .done) }
            }
            if item.state != .skipped {
                Button("Not Today", systemImage: "minus.circle") { _ = app.setCheck(id, on: day, state: .skipped) }
            }
            if item.state != .open {
                Button("Open Again", systemImage: "circle") { _ = app.setCheck(id, on: day, state: nil) }
            }
            Divider()
            Button("Edit in My Plan…", systemImage: "pencil") { app.perform(.editPlan, on: day) }
        }
    }

    private var labelText: String {
        if let flash { return "Weight saved: \(flash)" }
        switch item.state {
        case .done: return "\(item.title), done"
        case .skipped: return "\(item.title), not today"
        case .open:
            guard let detail = item.detail else { return item.title }
            return "\(item.title), \(detail)"
        }
    }

    private var hintText: String {
        switch item.kind {
        case .weighIn: return "Opens the weigh-in"
        case .body: return "Opens the measurements"
        case .check: return item.state == .done ? "Marks it open again" : "Marks it done"
        }
    }
}

// MARK: - Coach card

/// The one coach card above the meals (phase start or end, review, weekly check-in, baseline,
/// welcome back): title, one sentence, the calories before and after a phase start, its buttons,
/// more choices, "Pause Coaching" and "Later" (hides it on this device until tomorrow).
struct TodayCoachCard: View {
    let card: CoachBoard.Card
    let day: DayKey
    /// A phase card's calories a day now and after Start (empty for other cards).
    let targets: [CoachBoard.TargetChange]

    @Environment(AppModel.self) private var app
    /// The reason picked in "Pause Coaching"; the dialog then asks for how long.
    @State private var pauseReason: CoachPlan.PauseReason? = nil

    init(card: CoachBoard.Card, day: DayKey, targets: [CoachBoard.TargetChange] = []) {
        self.card = card
        self.day = day
        self.targets = targets
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleRow
            Text(card.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !targets.isEmpty {
                TodayCoachTargetList(rows: targets, unit: app.energyUnit)
            }
            buttons
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, cornerRadius: 22)
        .accessibilityElement(children: .contain)
        .confirmationDialog("Pause coaching?", isPresented: pauseBinding, titleVisibility: .visible,
                            presenting: pauseReason) { (reason: CoachPlan.PauseReason) in
            pauseActions(reason)
        } message: { (reason: CoachPlan.PauseReason) in
            Text(TodayCoachCard.pauseMessage(reason))
        }
    }

    /// The title with the card kind's ⓘ.
    private var titleRow: some View {
        let note: TodayInfo.Note = TodayInfo.card(card.kind)
        return Label {
            Text(card.title)
                .font(.headline)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Brand.accent)
        }
        .info(note.title, note.text)
    }

    /// The dialog's text for the picked reason (from the presented value, so it stays put while
    /// the dialog closes).
    private static func pauseMessage(_ reason: CoachPlan.PauseReason) -> String {
        let details = "no check pills, check-ins or coach reminders, and paused days stay out of your pace, check-ins and adherence. Meal reminders keep going."
        switch reason {
        case .holiday: return "For your holiday: " + details
        case .sick: return "While you're ill: " + details
        case .other: return "While paused: " + details
        }
    }

    /// The buttons in one row, or stacked when they don't fit (large text).
    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                choiceButtons
                Spacer(minLength: 0)
                trailingButtons
            }
            VStack(alignment: .leading, spacing: 8) {
                choiceButtons
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    trailingButtons
                }
            }
        }
    }

    @ViewBuilder
    private var choiceButtons: some View {
        Button(card.primary.title) { act(card.primary) }
            .primaryActionStyle()
            .lineLimit(1)
        if let secondary = card.secondary {
            Button(secondary.title) { act(secondary) }
                .buttonStyle(.bordered)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var trailingButtons: some View {
        if showsLaterButton {
            Button("Later") { app.dismissCard(card.key) }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityHint("Hides this card for now")
        }
        // "Still on a break?" comes while paused: nothing more to offer than Resume and Later.
        if card.kind != .pauseCheck {
            moreMenu
        }
    }

    /// A plain "Later" next to the ⋯ menu while the card has room for it (one button, no more
    /// choices); otherwise "Later" sits in the menu.
    private var showsLaterButton: Bool {
        !closesItself && card.secondary == nil && card.more.isEmpty
    }

    /// The ⋯ menu: the card's other choices, "Pause Coaching" and "Later".
    private var moreMenu: some View {
        Menu {
            moreItems
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(Brand.accent)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More")
    }

    @ViewBuilder
    private var moreItems: some View {
        ForEach(Array(card.more.enumerated()), id: \.offset) { _, choice in
            Button(choice.title) { act(choice) }
        }
        if !card.more.isEmpty {
            Divider()
        }
        Menu {
            ForEach(CoachPlan.PauseReason.allCases) { (reason: CoachPlan.PauseReason) in
                Button(PlanEditorData.reasonTitle(reason)) { pauseReason = reason }
            }
        } label: {
            Label("Pause Coaching", systemImage: "pause.circle")
        }
        if !closesItself && !showsLaterButton {
            Divider()
            Button("Later", systemImage: "clock") { app.dismissCard(card.key) }
        }
    }

    // MARK: Pause

    private var pauseBinding: Binding<Bool> {
        Binding<Bool>(
            get: { pauseReason != nil },
            set: { (isShown: Bool) in
                if !isShown { pauseReason = nil }
            }
        )
    }

    @ViewBuilder
    private func pauseActions(_ reason: CoachPlan.PauseReason) -> some View {
        Button("For a Week") { pause(reason, forAWeek: true) }
        Button("Until I Resume") { pause(reason, forAWeek: false) }
        Button("Cancel", role: .cancel) { pauseReason = nil }
    }

    /// From today for 7 days (until 6 days from now), or until resumed in My Plan; the toast's
    /// Undo puts the plan back.
    private func pause(_ reason: CoachPlan.PauseReason, forAWeek: Bool) {
        let until: DayKey? = forAWeek ? app.today.adding(days: 6) : nil
        pauseReason = nil
        PlanEditorData.pause(until: until, reason: reason, app: app)
    }

    /// The card has its own "Got it" (closing it is one of its buttons).
    private var closesItself: Bool {
        card.primary.action == .dismiss || card.secondary?.action == .dismiss
    }

    private var symbol: String {
        switch card.kind {
        case .phaseStart: "flag.fill"
        case .phaseEnd: "flag.checkered"
        case .review: "magnifyingglass"
        case .checkIn: "checklist"
        case .baseline: "ruler"
        case .welcomeBack: "hand.wave.fill"
        case .pauseCheck: "pause.circle"
        }
    }

    private func act(_ choice: CoachBoard.Card.Choice) {
        // "Resume coaching" on "Still on a break?" resumes right here (its action opens My Plan
        // wherever else it is offered).
        if card.kind == .pauseCheck, choice == card.primary {
            PlanEditorData.resume(app: app)
            return
        }
        app.perform(choice.action, on: day, card: card)
    }
}

/// The phase card's calories a day before and after Start: "🏋️ Gym   2,450 → 2,150 kcal".
private struct TodayCoachTargetList: View {
    let rows: [CoachBoard.TargetChange]
    let unit: EnergyUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Calories a day")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            ForEach(rows) { (row: CoachBoard.TargetChange) in
                rowView(row)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.accent.opacity(0.08), in: .rect(cornerRadius: 12, style: .continuous))
    }

    private func rowView(_ row: CoachBoard.TargetChange) -> some View {
        HStack(spacing: 8) {
            Text(row.title)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(row.todayCoachText(unit: unit))
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.todayCoachAccessibility(unit: unit))
    }
}

// MARK: - Phase line

/// Today's running phase above the summary card: "Lean gain · week 3 of 16", a thin progress
/// capsule and the status pill. A tap opens Progress → Body. While coaching is paused the pill
/// says so ("Paused · until 12 Feb") and Resume sits next to it. The ⓘ at the end explains the
/// status words.
struct TodayCoachPhaseLineView: View {
    let line: TodayCoachPhaseLine

    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 8) {
            Button {
                app.showProgress(.body)
            } label: {
                content
            }
            .buttonStyle(.plain)
            .accessibilityLabel(line.accessibilityText)
            .accessibilityHint("Opens your body progress")
            if line.isPaused {
                Button("Resume") { PlanEditorData.resume(app: app) }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .accessibilityHint("Starts coaching again from today")
            }
            InfoButton(note.title, note.text)
        }
    }

    /// What the status words mean and what to do.
    private var note: TodayInfo.Note {
        TodayInfo.phase(status: line.status, tone: line.tone, isPaused: line.isPaused, hasPace: line.hasPace)
    }

    /// The title and the status side by side, or the status under the title when they don't fit
    /// ("New targets since Tue · first look Mon 21 Jan" is long, and Resume takes room too).
    private var content: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                titleRow
                Spacer(minLength: 4)
                statusChip
            }
            VStack(alignment: .leading, spacing: 6) {
                titleRow
                statusChip
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .contentShape(.rect)
    }

    /// "Lean gain · week 3 of 16" and the thin progress capsule.
    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(line.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if let progress = line.progress {
                BodyPageCapsule(progress: progress)
                    .frame(width: 44)
            }
        }
    }

    private var statusChip: some View {
        Chip(text: line.status, tint: BodyPageStyle.color(line.tone), isSelected: line.tone == .alert)
    }
}

// MARK: - Protein pill

/// Protein of one meal against the plan's minimum in the meal header: "32 / 35 g", outlined
/// below the minimum, filled from it on; dimmed while planned food is part of it.
struct TodayCoachProteinPill: View {
    let meal: ProteinMeals.Meal

    private var tint: Color { NutrientStyle.color(.protein) }

    var body: some View {
        Text(meal.todayCoachText)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(meal.todayCoachIsReached ? Color.white : tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background { pillBackground }
            .opacity(meal.planned > 0 ? 0.65 : 1)
            .textCase(nil)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var pillBackground: some View {
        if meal.todayCoachIsReached {
            Capsule().fill(tint.gradient)
        } else {
            Capsule().strokeBorder(tint, lineWidth: 1.2)
        }
    }

    private var accessibilityText: String {
        let state = meal.todayCoachIsReached ? "reached" : "below the minimum"
        let planned = meal.planned > 0 ? ", planned food included" : ""
        return "Protein \(meal.todayCoachText.replacingOccurrences(of: " / ", with: " of ")), \(state)\(planned)"
    }
}
