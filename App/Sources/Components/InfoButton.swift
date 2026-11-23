import SwiftUI

// InfoButton – the small ⓘ that explains something in one or two plain sentences.
//
// Usage:
//     InfoButton("7-day average", "Your morning weights of the last 7 days, averaged. One salty dinner barely moves it.")
//     Text("Rate").info("Rate", "How fast your 7-day average moves, per week.")
//     Section { … } header: { Text("Day Types").info("Day types", "Kinds of days with their own targets, like Gym or Rest.") }
//
// - Title: a few words naming the thing. Text: one or two short, friendly sentences – what it means
//   or what to do. No jargon, no medical verdicts. Only where someone might not know; not on
//   obvious things.
// - A tap shows a popover (iPad and Mac; on iPhone too, where it fits). VoiceOver reads
//   "More about <title>"; on the Mac the text is also the hover tooltip.
// - `.info(_:_:)` puts the button right after a label (a row, a header, a number).
// - In a row that is itself a button or a NavigationLink, put the InfoButton next to that control,
//   not inside its label, so the row's tap doesn't swallow it.
// - SwiftUI only (iPhone, iPad and Mac targets); no state outside the button.

/// A small ⓘ button that shows `title` and `text` in a popover.
struct InfoButton: View {
    let title: String
    let text: String

    @State private var isShown = false

    init(_ title: String, _ text: String) {
        self.title = title
        self.text = text
    }

    var body: some View {
        Button {
            isShown = true
        } label: {
            // A 44×44 tap area that takes only the icon's room in the layout (headers stay low).
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .padding(-12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More about \(title)")
        #if os(macOS)
        .help(text)
        #endif
        .popover(isPresented: $isShown) {
            InfoButtonPopover(title: title, text: text)
        }
    }
}

/// The popover: the title and the explanation, wrapped to a readable width.
private struct InfoButtonPopover: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 280, alignment: .leading)
        .padding()
        .accessibilityElement(children: .combine)
        .presentationCompactAdaptation(.popover)
    }
}

extension View {
    /// This view with an `InfoButton` right after it, e.g. `Text("Rate").info("Rate", "…")`.
    func info(_ title: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            self
            InfoButton(title, text)
        }
    }
}
