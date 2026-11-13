import SwiftUI
import NinaCore

// Shared by the iPhone/iPad/Mac app, the watch app and the widgets (no BinisoftKit here, so the
// widget extensions can compile it too).

/// One colour per nutrient, the same everywhere (rings, bars, charts, watch).
enum NutrientStyle {
    static func color(_ nutrient: Nutrient) -> Color {
        switch nutrient {
        case .energy: Color.accentColor
        case .protein: Color(red: 0.36, green: 0.55, blue: 1.0)
        case .carbs: Color(red: 1.0, green: 0.72, blue: 0.22)
        case .fat: Color(red: 1.0, green: 0.42, blue: 0.42)
        case .fiber: Color(red: 0.20, green: 0.75, blue: 0.55)
        case .sugar: Color(red: 1.0, green: 0.55, blue: 0.78)
        case .saturatedFat, .transFat: Color(red: 0.78, green: 0.49, blue: 1.0)
        case .sodium: Color(red: 0.56, green: 0.56, blue: 0.60)
        case .water: Color(red: 0.23, green: 0.71, blue: 0.95)
        case .alcohol: Color(red: 0.62, green: 0.35, blue: 0.75)
        case .caffeine: Color(red: 0.55, green: 0.38, blue: 0.25)
        default: Color.teal
        }
    }

    static var water: Color { color(.water) }
}

/// The calorie ring: eaten / budget, with a second lap in orange when over.
struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 14
    var tint: Color = Color.accentColor
    var planned: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.16), lineWidth: lineWidth)
            if planned > progress {
                Circle()
                    .trim(from: 0, to: min(planned, 1))
                    .stroke(tint.opacity(0.35), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [2, lineWidth / 1.6]))
                    .rotationEffect(.degrees(-90))
            }
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.75), tint], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * min(max(progress, 0.01), 1))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            if progress > 1 {
                Circle()
                    .trim(from: 0, to: min(progress - 1, 1))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(.smooth(duration: 0.5), value: progress)
        .animation(.smooth(duration: 0.5), value: planned)
    }
}
