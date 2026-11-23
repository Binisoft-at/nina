import SwiftUI
import BinisoftKit
import NinaCore

// The ⓘ pieces of the body page, the body sheets, the photos and Nutrition: `InfoButton` and
// `.info` with a `BodyPageInfo` text (BodyPageInfo.swift), and a card and a stat tile with an ⓘ
// after their title (the same look as `CardSection` and `StatTile`).

extension InfoButton {
    /// The ⓘ with a body-page text.
    init(_ about: BodyPageInfo) {
        self.init(about.title, about.text)
    }
}

extension View {
    /// This view with an ⓘ right after it, from a body-page text.
    func info(_ about: BodyPageInfo) -> some View {
        info(about.title, about.text)
    }
}

/// `CardSection` with an ⓘ right after the title: symbol, title ⓘ, the trailing text, the content.
struct BodyPageInfoSection<Content: View>: View {
    let title: String
    var symbol: String?
    var trailing: String?
    let about: BodyPageInfo
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var header: some View {
        HStack {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(Brand.accent)
            }
            Text(title)
                .font(.headline)
                .info(about)
            Spacer()
            if let trailing {
                Text(trailing).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

/// `StatTile` with an ⓘ right after its title ("7-day average ⓘ").
struct BodyPageInfoStat: View {
    let title: String
    let value: String
    var detail: String?
    var tint: Color = .primary
    let about: BodyPageInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .info(about)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
