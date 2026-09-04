import SwiftUI
import Combine
@preconcurrency import AVFoundation
import UIKit

@MainActor
final class FormCameraController: NSObject, ObservableObject {
    enum Status { case idle, configuring, running, denied, unavailable, failed }
    @Published var status: Status = .idle
    @Published var usingFront = true

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "forge.camera.session")
    private var captureContinuation: CheckedContinuation<UIImage?, Never>?

    func start() {
        #if targetEnvironment(simulator)
        status = .unavailable
        return
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted { self.configure() } else { self.status = .denied }
                }
            }
        default: status = .denied
        }
        #endif
    }

    func stop() {
        queue.async { [session] in if session.isRunning { session.stopRunning() } }
    }

    func flip() {
        usingFront.toggle()
        let usingFront = usingFront
        let session = session
        queue.async {
            Self.reconfigureInput(for: session, usingFront: usingFront)
        }
    }

    private func configure() {
        status = .configuring
        let session = session
        let photoOutput = photoOutput
        let usingFront = usingFront
        queue.async { [weak self] in
            session.beginConfiguration()
            session.sessionPreset = .high
            Self.reconfigureInput(for: session, usingFront: usingFront)
            if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
            session.commitConfiguration()
            session.startRunning()
            Task { @MainActor in self?.status = session.isRunning ? .running : .failed }
        }
    }

    private nonisolated static func reconfigureInput(for session: AVCaptureSession, usingFront: Bool) {
        for input in session.inputs { session.removeInput(input) }
        let position: AVCaptureDevice.Position = usingFront ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return
        }
        session.addInput(input)
    }

    /// Captures one still and returns it as a UIImage.
    func capture() async -> UIImage? {
        guard status == .running else { return nil }
        let queue = queue
        let photoOutput = photoOutput

        return await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            self.captureContinuation = cont
            let settings = AVCapturePhotoSettings()
            queue.async { [weak self] in
                guard let self else { cont.resume(returning: nil); return }
                photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }
}

extension FormCameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        Task { @MainActor in
            self.captureContinuation?.resume(returning: image)
            self.captureContinuation = nil
        }
    }
}

/// Live preview backed by AVCaptureVideoPreviewLayer.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
