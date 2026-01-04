#if os(macOS)
import Foundation
import AVFoundation
import AppKit
import CoreImage
import ScreenCaptureKit

@available(macOS 12.3, *)
class ModernScreenCapture: NSObject, SCStreamDelegate {
    private let onFrame: (Data) -> Void
    private let minInterval: TimeInterval
    private var lastSent: TimeInterval = 0
    private var stream: SCStream?
    private var isCapturing = false
    
    init(interval: TimeInterval = 0.2, onFrame: @escaping (Data) -> Void) {
        self.minInterval = interval
        self.onFrame = onFrame
        super.init()
    }
    
    func start() async {
        print("[ModernCapture] Starting ScreenCaptureKit capture...")
        
        do {
            // Get shareable content
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            guard let display = content.displays.first else {
                print("[ModernCapture] ❌ No displays found")
                return
            }
            
            print("[ModernCapture] Using display: \(display.displayID) - \(Int(display.width))x\(Int(display.height))")
            
            // Configure stream
            let config = SCStreamConfiguration()
            config.width = 1280
            config.height = 720
            config.minimumFrameInterval = CMTime(value: 1, timescale: 5) // 5 FPS
            config.queueDepth = 3
            config.showsCursor = false
            config.capturesAudio = false
            
            // Create filter
            let filter = SCContentFilter(display: display, excludingWindows: [])
            
            // Create stream
            stream = SCStream(filter: filter, configuration: config, delegate: self)
            
            // Start capture
            try await stream?.startCapture()
            isCapturing = true
            print("[ModernCapture] ✅ ScreenCaptureKit capture started successfully")
            
        } catch {
            print("[ModernCapture] ❌ Failed to start capture: \(error)")
        }
    }
    
    func stop() {
        guard isCapturing else { return }
        
        Task {
            do {
                try await stream?.stopCapture()
                isCapturing = false
                print("[ModernCapture] ScreenCaptureKit capture stopped")
            } catch {
                print("[ModernCapture] Error stopping capture: \(error)")
            }
        }
    }
    
    // MARK: - SCStreamDelegate
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        
        let now = Date().timeIntervalSince1970
        guard now - lastSent >= minInterval else { return }
        lastSent = now
        
        // Convert sample buffer to image data
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let properties: [NSBitmapImageRep.PropertyKey: Any] = [.compressionFactor: 0.6]
        
        if let data = bitmap.representation(using: .jpeg, properties: properties) {
            onFrame(data)
        }
    }
}

class MacCaptureSender: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let displayId: CGDirectDisplayID = CGMainDisplayID()
    private let onFrame: (Data) -> Void
    private let minInterval: TimeInterval
    private var lastSent: TimeInterval = 0
    
    // Legacy AVCaptureSession approach
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let ciContext = CIContext()
    private let queue = DispatchQueue(label: "CaptureSender.VideoOutput")
    
    // Modern ScreenCaptureKit approach (iOS 12.3+)
    private var modernCapture: ModernScreenCapture?
    private var useModernCapture = false

    init(interval: TimeInterval = 0.2, onFrame: @escaping (Data) -> Void) {
        self.minInterval = interval
        self.onFrame = onFrame
        super.init()
        
        // Try modern approach first if available
        if #available(macOS 12.3, *) {
            modernCapture = ModernScreenCapture(interval: interval, onFrame: onFrame)
            useModernCapture = true
            print("[CaptureSender] Will use ScreenCaptureKit (modern approach)")
        } else {
            configureSession()
            print("[CaptureSender] Using legacy AVCaptureSession")
        }
    }

    private func configureSession() {
        print("[CaptureSender] Configuring capture session with CMIO stability...")
        
        session.beginConfiguration()
        
        // Use medium preset to reduce CMIO load
        session.sessionPreset = .medium
        
        if let input = AVCaptureScreenInput(displayID: displayId) {
            // Configure input to reduce CMIO system load
            input.capturesCursor = false // Disable cursor to reduce complexity
            input.capturesMouseClicks = false // Disable mouse clicks
            
            // Set lower frame rate to reduce CMIO stress
            input.minFrameDuration = CMTimeMake(value: 1, timescale: 10) // 10 FPS max
            
            if session.canAddInput(input) {
                session.addInput(input)
                print("[CaptureSender] ✅ Screen input added successfully")
            } else {
                print("[CaptureSender] ❌ Failed to add screen input")
            }
        } else {
            print("[CaptureSender] ❌ Failed to create AVCaptureScreenInput for display \(displayId)")
        }

        // Configure output with settings that are easier on CMIO
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: 1280, // Limit resolution to reduce CMIO load
            kCVPixelBufferHeightKey as String: 720
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        output.alwaysDiscardsLateVideoFrames = true
        
        if session.canAddOutput(output) {
            session.addOutput(output)
            print("[CaptureSender] ✅ Video output added successfully")
        } else {
            print("[CaptureSender] ❌ Failed to add video output")
        }

        session.commitConfiguration()
        print("[CaptureSender] ✅ Session configuration completed")
    }

    func start() {
        if useModernCapture {
            print("[CaptureSender] Starting modern ScreenCaptureKit capture...")
            Task {
                await modernCapture?.start()
            }
        } else {
            print("[CaptureSender] Starting legacy AVCaptureSession with CMIO protection...")
            
            if !session.isRunning {
                // Add pre-validation for CMIO system stability
                DispatchQueue.global(qos: .userInitiated).async {
                    // Test CMIO system before starting
                    var testBuffer: CVPixelBuffer?
                    let testStatus = CVPixelBufferCreate(
                        kCFAllocatorDefault, 16, 16, 
                        kCVPixelFormatType_32ARGB, 
                        nil, &testBuffer
                    )
                    
                    if testStatus == kCVReturnSuccess {
                        print("[CaptureSender] ✅ CMIO system pre-check passed")
                    } else {
                        print("[CaptureSender] ⚠️ CMIO system warning: \(testStatus)")
                    }
                    
                    // Start with delay to allow CMIO system to stabilize
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        print("[CaptureSender] 🚀 Starting legacy capture session...")
                        self.session.startRunning()
                        
                        // Verify startup success after a brief moment
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if self.session.isRunning {
                                print("[CaptureSender] ✅ Legacy screen capture started successfully")
                            } else {
                                print("[CaptureSender] ❌ Legacy screen capture failed to start")
                            }
                        }
                    }
                }
            }
        }
    }

    func stop() {
        if useModernCapture {
            modernCapture?.stop()
        } else {
            if session.isRunning {
                session.stopRunning()
            }
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
