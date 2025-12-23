#if os(macOS)
import Foundation
import AVFoundation
import AppKit
import CoreImage

class MacCaptureSender: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let displayId: CGDirectDisplayID = CGMainDisplayID()
    private let onFrame: (Data) -> Void
    private let minInterval: TimeInterval
    private var lastSent: TimeInterval = 0

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let ciContext = CIContext()
    private let queue = DispatchQueue(label: "CaptureSender.VideoOutput")

    init(interval: TimeInterval = 0.2, onFrame: @escaping (Data) -> Void) {
        self.minInterval = interval
        self.onFrame = onFrame
        super.init()
        configureSession()
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        if let input = AVCaptureScreenInput(displayID: displayId) {
            input.capturesCursor = true
            input.capturesMouseClicks = true
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } else {
            NSLog("CaptureSender: failed to create AVCaptureScreenInput for display\(displayId)")
        }

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        output.setSampleBufferDelegate(self, queue: queue)
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        session.commitConfiguration()
    }

    func start() {
        if !session.isRunning {
            session.startRunning()
        }
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date().timeIntervalSince1970
        if now - lastSent < minInterval { return }
        lastSent = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent
        guard let cgImage = ciContext.createCGImage(ciImage, from: extent) else { return }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let properties: [NSBitmapImageRep.PropertyKey: Any] = [.compressionFactor: 0.6]
        if let data = bitmap.representation(using: .jpeg, properties: properties) {
            onFrame(data)
        }
    }
}
#endif
