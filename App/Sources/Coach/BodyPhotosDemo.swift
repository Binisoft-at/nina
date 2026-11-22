import Foundation
import CoreGraphics
import CoreText
import SwiftData
import NinaCore

/// Made-up placeholder photos for the demo (`-Demo`, the screenshots): a plain figure drawn on a
/// soft gradient and labelled "SAMPLE" – never a real photo. Front, side and back on the demo's
/// two full sets (42 and 21 days ago) and a front photo a week ago; the shoulders broaden a little
/// from one to the next (the demo is a lean gain). Written to the demo's in-memory store only.
enum BodyPhotosDemo {
    @MainActor
    static func seed(_ context: ModelContext, today: DayKey) {
        let existing = (try? context.fetchCount(FetchDescriptor<ProgressPhoto>())) ?? 0
        guard existing == 0 else { return }
        let sessions: [(offset: Int, poses: [PhotoPose])] = [(42, PhotoPose.session), (21, PhotoPose.session), (7, [.front])]
        for (step, session) in sessions.enumerated() {
            let day = today.adding(days: -session.offset)
            for (index, pose) in session.poses.enumerated() {
                guard let drawn = image(pose: pose, step: step, day: day),
                      let data = BodyPhotoImages.jpeg(drawn, quality: 0.9),
                      let processed = BodyPhotoImages.processNow(data) else { continue }
                let photo = ProgressPhoto(day: day, time: day.date(minutes: 440 + index), pose: pose)
                photo.image = processed.image
                photo.thumbnail = processed.thumbnail
                photo.note = step == 0 && index == 0 ? "Sample photo for the demo" : ""
                context.insert(photo)
            }
        }
        try? context.save()
    }

    /// 600 × 800: a gradient, a floor, the figure for the pose, "SAMPLE · <day>".
    static func image(pose: PhotoPose, step: Int, day: DayKey) -> CGImage? {
        let width = 600, height = 800
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let top = CGColor(red: 0.93, green: 0.95, blue: 0.97, alpha: 1)
        let bottom = CGColor(red: 0.78, green: 0.84, blue: 0.89, alpha: 1)
        if let gradient = CGGradient(colorsSpace: space, colors: [bottom, top] as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: CGFloat(height)), options: [])
        }
        context.setFillColor(CGColor(red: 0.70, green: 0.74, blue: 0.79, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: 110))
        let shade = pose == .back ? 0.30 : 0.38
        context.setFillColor(CGColor(red: shade, green: shade + 0.06, blue: shade + 0.14, alpha: 1))
        figure(in: context, pose: pose, change: CGFloat(step), centre: CGFloat(width) / 2)
        label("SAMPLE · \(day.rawValue)", in: context, at: CGPoint(x: 24, y: 30))
        return context.makeImage()
    }

    /// A simple figure (origin bottom left): head, neck, torso narrowing to the waist, arms, legs.
    private static func figure(in context: CGContext, pose: PhotoPose, change: CGFloat, centre: CGFloat) {
        let side = pose == .side
        let shoulder: CGFloat = side ? 44 : 80 + change * 2
        let waist: CGFloat = side ? 38 : 58
        let hip: CGFloat = side ? 48 : 70
        // Head and neck.
        context.fillEllipse(in: CGRect(x: centre - 40, y: 600, width: 80, height: 96))
        context.fill(CGRect(x: centre - 16, y: 556, width: 32, height: 52))
        // Torso.
        let torso = CGMutablePath()
        torso.move(to: CGPoint(x: centre - shoulder, y: 566))
        torso.addQuadCurve(to: CGPoint(x: centre - waist, y: 430), control: CGPoint(x: centre - shoulder + 4, y: 480))
        torso.addQuadCurve(to: CGPoint(x: centre - hip, y: 330), control: CGPoint(x: centre - waist - 4, y: 380))
        torso.addLine(to: CGPoint(x: centre + hip, y: 330))
        torso.addQuadCurve(to: CGPoint(x: centre + waist, y: 430), control: CGPoint(x: centre + waist + 4, y: 380))
        torso.addQuadCurve(to: CGPoint(x: centre + shoulder, y: 566), control: CGPoint(x: centre + shoulder - 4, y: 480))
        torso.closeSubpath()
        context.addPath(torso)
        context.fillPath()
        // Arms and legs.
        var limbs: [CGRect] = []
        if side {
            limbs.append(CGRect(x: centre - 13, y: 350, width: 26, height: 210))
            limbs.append(CGRect(x: centre - 30, y: 120, width: 60, height: 225))
        } else {
            limbs.append(CGRect(x: centre - shoulder - 30, y: 345, width: 26, height: 215))
            limbs.append(CGRect(x: centre + shoulder + 4, y: 345, width: 26, height: 215))
            limbs.append(CGRect(x: centre - hip + 6, y: 120, width: hip - 12, height: 225))
            limbs.append(CGRect(x: centre + 6, y: 120, width: hip - 12, height: 225))
        }
        for limb in limbs {
            context.addPath(CGPath(roundedRect: limb, cornerWidth: 12, cornerHeight: 12, transform: nil))
        }
        context.fillPath()
    }

    private static func label(_ text: String, in context: CGContext, at point: CGPoint) {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 26, nil)
        let colour = CGColor(red: 0.20, green: 0.25, blue: 0.32, alpha: 0.75)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): colour,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes) as CFAttributedString)
        context.textPosition = point
        CTLineDraw(line, context)
    }
}
