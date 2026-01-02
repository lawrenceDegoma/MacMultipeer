import Foundation
import AVFoundation
import AVKit
import AppKit
import Combine
import Network

class AirPlayManager: NSObject, ObservableObject, NetServiceBrowserDelegate {
    @Published var availableDevices: [AirPlayDevice] = []
    @Published var selectedDevice: AirPlayDevice?
    @Published var isStreaming: Bool = false
    @Published var isDiscovering: Bool = false
    
    private var currentImageData: Data?
    private var netServiceBrowser: NetServiceBrowser?
    private var discoveredServices: Set<NetService> = []
    private let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_airplay._tcp", domain: nil), using: .tcp)
    
    // Streaming components
    private var streamingPlayer: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var routePickerView: AVRoutePickerView?
    private var streamingWindow: NSWindow?
    private var currentItem: AVPlayerItem?
    
    struct AirPlayDevice: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let identifier: String
        let hostName: String?
        let port: Int
        let txtRecords: [String: Data]
        
        var deviceInfo: String {
            var info = [String]()
            if let model = txtRecords["model"], let modelStr = String(data: model, encoding: .utf8) {
                info.append("Model: \(modelStr)")
            }
            if let features = txtRecords["features"], let featuresStr = String(data: features, encoding: .utf8) {
                info.append("Features: \(featuresStr)")
            }
            return info.joined(separator: ", ")
        }
        
        var isAppleTV: Bool {
            if let model = txtRecords["model"], let modelStr = String(data: model, encoding: .utf8) {
                return modelStr.contains("AppleTV") || modelStr.contains("Apple TV")
            }
            return name.lowercased().contains("apple tv")
        }
        
        var isAirPlayCapable: Bool {
            // If it's found via _airplay._tcp service, it's AirPlay capable
            return true
        }
        
        var deviceType: String {
            if isAppleTV {
                return "Apple TV"
            } else if name.lowercased().contains("roku") {
                return "Roku Device"
            } else if name.lowercased().contains("macbook") || name.lowercased().contains("imac") || name.lowercased().contains("mac") {
                return "Mac"
            } else {
                return "AirPlay Device"
            }
        }
    }
    
    override init() {
        super.init()
        setupAirPlay()
        startDiscovery()
    }
    
    private func setupAirPlay() {
        // Initialize AirPlay setup
        print("[AirPlay] Setting up AirPlay manager")
    }
    
    func startDiscovery() {
        guard !isDiscovering else { return }
        
        isDiscovering = true
        print("[AirPlay] Starting Apple TV discovery...")
        
        // Setup Bonjour service browser for AirPlay devices
        netServiceBrowser = NetServiceBrowser()
        netServiceBrowser?.delegate = self
        netServiceBrowser?.searchForServices(ofType: "_airplay._tcp", inDomain: "local.")
        
        // Also use Network framework for modern discovery
        browser.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    print("[AirPlay] Network browser ready")
                case .failed(let error):
                    print("[AirPlay] Network browser failed: \(error)")
                case .cancelled:
                    print("[AirPlay] Network browser cancelled")
                default:
                    break
                }
            }
        }
        
        browser.browseResultsChangedHandler = { [weak self] results, changes in
            DispatchQueue.main.async {
                self?.handleBrowseResults(results: results, changes: changes)
            }
        }
        
        browser.start(queue: .main)
    }
    
    func stopDiscovery() {
        guard isDiscovering else { return }
        
        isDiscovering = false
        print("[AirPlay] Stopping Apple TV discovery...")
        
        netServiceBrowser?.stop()
        browser.cancel()
    }
    
    private func handleBrowseResults(results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                print("[AirPlay] Found device: \(result.endpoint)")
                addDiscoveredDevice(from: result)
            case .removed(let result):
                print("[AirPlay] Lost device: \(result.endpoint)")
                removeDiscoveredDevice(from: result)
            default:
                break
            }
        }
    }
    
    private func addDiscoveredDevice(from result: NWBrowser.Result) {
        guard case let .service(name, type, domain, _) = result.endpoint else { return }
        
        let hostName: String? = nil
        let port: Int = 7000 // Default AirPlay port
        var txtRecords: [String: Data] = [:]
        
        if case let .bonjour(txtRecord) = result.metadata {
            // Convert NWTXTRecord to [String: Data]
            for (key, value) in txtRecord {
                switch value {
                case .data(let data):
                    txtRecords[key] = data
                case .string(let string):
                    txtRecords[key] = string.data(using: .utf8) ?? Data()
                default:
                    break
                }
            }
        }
        
        let device = AirPlayDevice(
            name: name,
            identifier: "\(name).\(type).\(domain)",
            hostName: hostName,
            port: port,
            txtRecords: txtRecords
        )

        DispatchQueue.main.async {
            // Show all AirPlay-capable devices (not just Apple TVs)
            print("[AirPlay] Processing Network framework device: \(device.name) (\(device.deviceType), AirPlay: \(device.isAirPlayCapable))")
            if !self.availableDevices.contains(device) {
                self.availableDevices.append(device)
                print("[AirPlay] Added AirPlay device: \(device.name) (\(device.deviceType))")
                print("[AirPlay] Total devices in list: \(self.availableDevices.count)")
            } else {
                print("[AirPlay] Network framework device already exists: \(device.name)")
            }
        }
    }
    
    private func removeDiscoveredDevice(from result: NWBrowser.Result) {
        guard case let .service(name, type, domain, _) = result.endpoint else { return }
        
        let identifier = "\(name).\(type).\(domain)"
        if let index = availableDevices.firstIndex(where: { $0.identifier == identifier }) {
            let removedDevice = availableDevices.remove(at: index)
            print("[AirPlay] Removed Apple TV: \(removedDevice.name)")
        }
    }
    
    private func discoverAirPlayDevices() {
        // Legacy method - now calls the new discovery
        startDiscovery()
    }
    
    func selectDevice(_ device: AirPlayDevice) {
        selectedDevice = device
        print("[AirPlay] Selected device: \(device.name)")
        setupStreamingForDevice(device)
    }
    
    private func setupStreamingForDevice(_ device: AirPlayDevice) {
        // Create a streaming setup for the selected device
        setupAirPlayOutput()
    }
    
    private func setupAirPlayOutput() {
        // Create route picker for AirPlay device selection (macOS version)
        routePickerView = AVRoutePickerView()
        
        // Create player for streaming
        streamingPlayer = AVPlayer()
        playerLayer = AVPlayerLayer(player: streamingPlayer)
        playerLayer?.videoGravity = .resizeAspect
        
        print("[AirPlay] AirPlay output setup completed")
    }
    
    func startStreaming(with imageData: Data) {
        guard let device = selectedDevice else {
            print("[AirPlay] No device selected for streaming")
            return
        }
        
        print("[AirPlay] Starting stream to \(device.name)")
        currentImageData = imageData
        isStreaming = true
        
        // Convert image data to streaming format
        if let image = NSImage(data: imageData) {
            createStreamingContent(from: image)
        }
    }
    
    private func createStreamingContent(from image: NSImage) {
        // Create a temporary video file from the image for streaming
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let tempURL = self.createVideoFromImage(image)
            
            DispatchQueue.main.async {
                self.playVideoContent(at: tempURL)
            }
        }
    }
    
    private func createVideoFromImage(_ image: NSImage) -> URL {
        // Create temporary video file
        let tempDir = FileManager.default.temporaryDirectory
        let videoURL = tempDir.appendingPathComponent("airplay_frame_\(Date().timeIntervalSince1970).mp4")
        
        // Convert NSImage to CGImage for video creation
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("[AirPlay] Failed to convert NSImage to CGImage")
            return videoURL
        }
        
        createVideoFile(from: cgImage, outputURL: videoURL)
        return videoURL
    }
    
    private func createVideoFile(from cgImage: CGImage, outputURL: URL) {
        // Create video writer
        guard let videoWriter = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            print("[AirPlay] Failed to create video writer")
            return
        }
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: cgImage.width,
            AVVideoHeightKey: cgImage.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel
            ]
        ]
        
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: nil)
        
        videoWriter.add(videoInput)
        
        if videoWriter.startWriting() {
            videoWriter.startSession(atSourceTime: .zero)
            
            if let pixelBuffer = createPixelBuffer(from: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height)) {
                pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: .zero)
            }
            
            videoInput.markAsFinished()
            videoWriter.finishWriting {
                print("[AirPlay] Video file created successfully")
            }
        }
    }
    
    private func createPixelBuffer(from cgImage: CGImage, size: CGSize) -> CVPixelBuffer? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32ARGB,
            attributes as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: pixelData,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        
        context?.draw(cgImage, in: CGRect(origin: .zero, size: size))
        CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        
        return buffer
    }
    
    private func playVideoContent(at url: URL) {
        guard let player = streamingPlayer else { return }
        
        currentItem = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: currentItem)
        
        // Enable AirPlay for macOS
        player.allowsExternalPlayback = true
        
        // Start playback
        player.play()
        
        print("[AirPlay] Started playback for AirPlay streaming")
    }
    
    func updateStream(with imageData: Data) {
        guard isStreaming else { return }
        
        currentImageData = imageData
        
        if let image = NSImage(data: imageData) {
            createStreamingContent(from: image)
        }
    }
    
    func stopStreaming() {
        isStreaming = false
        currentImageData = nil
        
        // Stop the current player
        streamingPlayer?.pause()
        streamingPlayer?.replaceCurrentItem(with: nil)
        
        // Clean up temporary files
        cleanupTemporaryFiles()
        
        print("[AirPlay] Stopped streaming to AirPlay device")
    }
    
    private func cleanupTemporaryFiles() {
        // Remove temporary video files
        let tempDir = FileManager.default.temporaryDirectory
        do {
            let tempFiles = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            for file in tempFiles {
                if file.lastPathComponent.hasPrefix("airplay_frame_") {
                    try FileManager.default.removeItem(at: file)
                }
            }
        } catch {
            print("[AirPlay] Error cleaning temporary files: \(error)")
        }
    }
    
    // Method to be called when new frame data arrives from MultipeerConnectivity
    func handleIncomingFrame(_ imageData: Data, from deviceName: String) {
        print("[AirPlay] Received frame from \(deviceName), forwarding to Apple TV")
        
        if isStreaming {
            updateStream(with: imageData)
        } else {
            startStreaming(with: imageData)
        }
    }
}

// MARK: - NetServiceBrowserDelegate
extension AirPlayManager {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("[AirPlay] Found service via NetServiceBrowser: \(service.name)")
        
        // Resolve the service to get more details
        service.delegate = self
        service.resolve(withTimeout: 10.0)
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        print("[AirPlay] Lost service via NetServiceBrowser: \(service.name)")
        
        DispatchQueue.main.async {
            if let index = self.availableDevices.firstIndex(where: { $0.name == service.name }) {
                let removedDevice = self.availableDevices.remove(at: index)
                print("[AirPlay] Removed Apple TV: \(removedDevice.name)")
            }
        }
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        print("[AirPlay] NetServiceBrowser failed to search: \(errorDict)")
    }
}

// MARK: - NetServiceDelegate
extension AirPlayManager: NetServiceDelegate {
    func netServiceDidResolveAddress(_ service: NetService) {
        print("[AirPlay] Resolved service: \(service.name) at \(service.hostName ?? "unknown"):\(service.port)")
        
        // Create device from resolved service
        let txtData = service.txtRecordData()
        var txtRecords: [String: Data] = [:]
        
        if let txtData = txtData {
            let parsedRecords = NetService.dictionary(fromTXTRecord: txtData)
            for (key, value) in parsedRecords {
                txtRecords[key] = value
            }
        }
        
        let device = AirPlayDevice(
            name: service.name,
            identifier: "\(service.name).\(service.type).\(service.domain)",
            hostName: service.hostName,
            port: service.port,
            txtRecords: txtRecords
        )
        
        DispatchQueue.main.async {
            // Show all AirPlay-capable devices (not just Apple TVs)
            print("[AirPlay] Processing resolved device: \(device.name) (\(device.deviceType), AirPlay: \(device.isAirPlayCapable))")
            if !self.availableDevices.contains(device) {
                self.availableDevices.append(device)
                print("[AirPlay] Added resolved AirPlay device: \(device.name) (\(device.deviceType))")
                print("[AirPlay] Total devices in list: \(self.availableDevices.count)")
            } else {
                print("[AirPlay] Resolved device already exists: \(device.name)")
            }
        }
    }
    
    func netService(_ service: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("[AirPlay] Failed to resolve service \(service.name): \(errorDict)")
    }
}
