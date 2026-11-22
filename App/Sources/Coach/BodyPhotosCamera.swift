#if os(iOS)
import SwiftUI
import UIKit
import AVFoundation
import BinisoftKit
import NinaCore

// The camera for one pose (iPhone, iPad; full screen): the live picture in a 3:4 frame with the
// last photo of the pose over it at 30 % (the "ghost") to stand the same way again, a 3 or 10
// second timer, and the back or front camera. AVFoundation draws the picture in exactly the frame
// the ghost uses, so lining up with the ghost lines up the photos (the system camera picker places
// its picture differently from one iPhone to the next). Portrait photos; the front camera's
// picture is mirrored like a mirror, the saved photo is not, and the ghost follows the picture.

enum BodyPhotoCamera {
    /// The device has a camera (looked up once).
    static let isAvailable: Bool = AVCaptureDevice.default(for: .video) != nil
}

/// Owns the capture session (configured and run on its own queue).
final class BodyPhotoCapture: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "at.binisoft.nina.photos.camera")
    private var input: AVCaptureDeviceInput?
    private var pending: CheckedContinuation<Data?, Never>?

    /// Starts the camera on `position`; false when there is none.
    func start(_ position: AVCaptureDevice.Position) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            queue.async {
                let ready = self.configure(position)
                if ready, !self.session.isRunning { self.session.startRunning() }
                continuation.resume(returning: ready)
            }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    /// A photo (HEIC or JPEG with its orientation); nil when it failed.
    func capture() async -> Data? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            queue.async {
                guard self.session.isRunning, self.pending == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                self.pending = continuation
                if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        queue.async {
            self.pending?.resume(returning: data)
            self.pending = nil
        }
    }

    /// The camera at `position` (front or back) with the photo output; on the session queue.
    private func configure(_ position: AVCaptureDevice.Position) -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
                ?? AVCaptureDevice.default(for: .video),
              let newInput = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
        if let input { session.removeInput(input) }
        guard session.canAddInput(newInput) else {
            if let input, session.canAddInput(input) { session.addInput(input) }
            return false
        }
        session.addInput(newInput)
        input = newInput
        if !session.outputs.contains(where: { $0 === output }), session.canAddOutput(output) {
            session.addOutput(output)
        }
        return true
    }
}

/// The live picture (portrait, fitted into its frame like the ghost).
private struct BodyPhotoCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> BodyPhotoPreviewView {
        let view = BodyPhotoPreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: BodyPhotoPreviewView, context: Context) {
        view.setNeedsLayout()
    }
}

private final class BodyPhotoPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // layerClass makes the layer a preview layer.
        layer as! AVCaptureVideoPreviewLayer // swiftlint:disable:this force_cast
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}

/// The camera screen for one pose.
struct BodyPhotoCameraView: View {
    let title: String
    /// The last photo of the pose.
    let ghost: BodyPhotoBitmap?
    let onPhoto: (Data) -> Void
    let onCancel: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var capture = BodyPhotoCapture()
    @State private var state: BodyPhotoCameraState = .starting
    @State private var position: AVCaptureDevice.Position = .back
    @State private var showsGhost = true
    @State private var timerSeconds = 0
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    @State private var isTaking = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                topBar
                Spacer(minLength: 0)
                viewfinder
                Spacer(minLength: 0)
                bottomBar
            }
            .padding(.vertical, 8)
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .task { await start() }
        .onDisappear {
            countdownTask?.cancel()
            capture.stop()
        }
    }

    // MARK: Parts

    private var topBar: some View {
        HStack(spacing: 10) {
            Button("Cancel", systemImage: "xmark", action: cancel)
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
            Spacer(minLength: 4)
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 4)
            if ghost != nil {
                Button(ghostTitle, systemImage: showsGhost ? "person.fill.viewfinder" : "person.crop.rectangle") {
                    showsGhost.toggle()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
            }
            Button(action: cycleTimer) {
                Label(timerTitle, systemImage: "timer")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.glass)
            .accessibilityLabel(timerLabel)
        }
        .padding(.horizontal)
    }

    private var ghostTitle: String { showsGhost ? "Hide last photo" : "Show last photo" }
    private var timerTitle: String { timerSeconds == 0 ? "Off" : "\(timerSeconds) s" }
    private var timerLabel: String { timerSeconds == 0 ? "Timer off" : "Timer \(timerSeconds) seconds" }
    private var shutterLabel: String { countdown == nil ? "Take photo" : "Stop timer" }

    private var viewfinder: some View {
        Color.black
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay { picture }
            .overlay { ghostLayer }
            .overlay { guides }
            .overlay { countdownLabel }
            .clipped()
    }

    @ViewBuilder
    private var picture: some View {
        switch state {
        case .running:
            BodyPhotoCameraPreview(session: capture.session)
        case .starting:
            ProgressView()
                .tint(.white)
        case .denied:
            message("Nina may not use the camera. Allow it in Settings → Nina → Camera.", button: "Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        case .unavailable:
            message("No camera is available.", button: nil, action: nil)
        }
    }

    @ViewBuilder
    private var ghostLayer: some View {
        if showsGhost, state == .running, let ghost {
            Image(decorative: ghost.image, scale: 1)
                .resizable()
                .scaledToFit()
                .scaleEffect(x: position == .front ? -1 : 1, y: 1)
                .opacity(ProgressPhotos.ghostOpacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// A centre line and a line at a third from the top (eyes) to stand the same way.
    private var guides: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: proxy.size.width / 2, y: 0))
                path.addLine(to: CGPoint(x: proxy.size.width / 2, y: proxy.size.height))
                path.move(to: CGPoint(x: 0, y: proxy.size.height / 3))
                path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height / 3))
            }
            .stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .opacity(state == .running ? 1 : 0)
    }

    @ViewBuilder
    private var countdownLabel: some View {
        if let countdown {
            Text("\(countdown)")
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(radius: 8)
                .contentTransition(.numericText())
        }
    }

    private var bottomBar: some View {
        HStack {
            Button("Switch Camera", systemImage: "arrow.triangle.2.circlepath.camera", action: flip)
                .labelStyle(.iconOnly)
                .font(.title3)
                .buttonStyle(.glass)
                .disabled(state != .running || countdown != nil)
                .frame(maxWidth: .infinity)
            shutter
                .frame(maxWidth: .infinity)
            Color.clear
                .frame(width: 44, height: 44)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
    }

    private var shutter: some View {
        Button(action: shutterTapped) {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 4)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(countdown == nil ? Color.white : Color.red)
                    .frame(width: 62, height: 62)
            }
        }
        .buttonStyle(.plain)
        .disabled(state != .running || isTaking)
        .accessibilityLabel(shutterLabel)
    }

    private func message(_ text: String, button: String?, action: (() -> Void)?) -> some View {
        VStack(spacing: 14) {
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            if let button, let action {
                Button(button, action: action)
                    .buttonStyle(.glass)
            }
        }
        .padding(28)
    }

    // MARK: Actions

    private func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                state = .denied
                return
            }
        default:
            state = .denied
            return
        }
        state = await capture.start(position) ? .running : .unavailable
    }

    private func flip() {
        let next: AVCaptureDevice.Position = position == .back ? .front : .back
        Task {
            if await capture.start(next) { position = next }
        }
    }

    private func cycleTimer() {
        switch timerSeconds {
        case 0: timerSeconds = 3
        case 3: timerSeconds = 10
        default: timerSeconds = 0
        }
    }

    private func shutterTapped() {
        if countdown != nil {
            countdownTask?.cancel()
            countdownTask = nil
            countdown = nil
            return
        }
        guard timerSeconds > 0 else {
            take()
            return
        }
        let seconds = timerSeconds
        countdownTask = Task {
            for remaining in stride(from: seconds, to: 0, by: -1) {
                withAnimation { countdown = remaining }
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            countdown = nil
            take()
        }
    }

    private func take() {
        guard !isTaking else { return }
        isTaking = true
        Task {
            let data = await capture.capture()
            isTaking = false
            if let data { onPhoto(data) }
        }
    }

    private func cancel() {
        countdownTask?.cancel()
        onCancel()
    }
}

private enum BodyPhotoCameraState: Equatable {
    case starting, running, denied, unavailable
}
#endif
