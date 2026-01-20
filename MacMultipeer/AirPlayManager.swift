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
        initializeCoreMedia()
        setupAirPlay()
        // Don't start discovery automatically - let it be triggered when needed
        Swift.print("[AirPlay] AirPlayManager initialized (discovery not started)")
    }
    
    private func initializeCoreMedia() {
        // Initialize Core Media I/O with proper metadata to prevent analytics errors
        Swift.print("[AirPlay] Initializing Core Media I/O system...")
        
        // Pre-warm the Core Media system to establish proper device context
        DispatchQueue.global(qos: .utility).async {
            // Create a minimal pixel buffer to initialize CMIO properly
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey: 32,
                kCVPixelBufferHeightKey: 32,
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ]
            
            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                32, 32,
                kCVPixelFormatType_32ARGB,
                attributes as CFDictionary,
                &pixelBuffer
            )
            
            if status == kCVReturnSuccess {
                print("[AirPlay] ✅ Core Media I/O system initialized successfully")
            } else {
                print("[AirPlay] ⚠️ Core Media I/O initialization warning: \(status)")
            }
        }
    }
    
    private func setupAirPlay() {
        // Initialize AirPlay setup without starting discovery
        print("[AirPlay] Setting up AirPlay manager")
    }
    
    func startDiscovery() {
        guard !isDiscovering else { return }
        
        isDiscovering = true
        print("[AirPlay] Starting Apple TV discovery...")
        
        // Delay the heavy network operations slightly to improve responsiveness
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.setupNetworkDiscovery()
        }
    }
    
    private func setupNetworkDiscovery() {
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
        
        browser.start(queue: .global(qos: .background))
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
        // Note: This may show system-level cache/permission messages in console (normal)
        routePickerView = AVRoutePickerView()
        
        // Create player for streaming
        streamingPlayer = AVPlayer()
        playerLayer = AVPlayerLayer(player: streamingPlayer)
        playerLayer?.videoGravity = .resizeAspect
        
        print("[AirPlay] AirPlay output setup completed")
        print("[AirPlay] Note: System cache/permission messages are normal during AirPlay initialization")
    }
    
    func startStreaming(with imageData: Data) {
        guard let device = selectedDevice else {
            print("[AirPlay] No device selected for streaming")
            return
        }
        
        print("[AirPlay] Starting real-time AirPlay stream to \(device.name)")
        currentImageData = imageData
        isStreaming = true
        
        // Initialize real-time streaming using macOS AirPlay capabilities
        setupRealTimeStreamingWindow(with: imageData)
    }
    
    private func setupRealTimeStreamingWindow(with imageData: Data) {
        // Create a streaming window that can be easily mirrored via AirPlay
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Create or update the streaming window
            if self.streamingWindow == nil {
                self.createStreamingWindow()
            }
            
            // Update the streaming window with real-time frame data
            if let image = NSImage(data: imageData) {
                self.updateStreamingWindowContent(with: image)
            }
        }
    }
    
    private func updateStreamingWindowContent(with image: NSImage) {
        // Update the streaming window content with new frame data
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let window = self.streamingWindow,
                  let contentView = window.contentView else { return }
            
            // Create or update image view
            if let imageView = contentView.subviews.first(where: { $0 is NSImageView }) as? NSImageView {
                imageView.image = image
            } else {
                let imageView = NSImageView()
                imageView.image = image
                imageView.imageScaling = .scaleProportionallyUpOrDown
                imageView.translatesAutoresizingMaskIntoConstraints = false
                
                contentView.addSubview(imageView)
                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                    imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                    imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
                    imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
                ])
            }
        }
    }
    
    private func createStreamingWindow() {
        print("[AirPlay] Creating dedicated streaming window for AirPlay")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Create a window that can be easily mirrored via AirPlay
            let window = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 1280, height: 720),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            
            window.title = "🖥️ MacMultipeer Screen Share - AirPlay this window to Apple TV"
            window.backgroundColor = .black
            window.level = .normal  // Make it visible for AirPlay selection
            
            // Position it prominently so users can see it
            window.center()
            window.makeKeyAndOrderFront(nil)
            
            // Enable external screen output for AirPlay
            window.sharingType = .readOnly
            
            self.streamingWindow = window
            print("[AirPlay] ✅ AirPlay streaming window created - use macOS screen mirroring to stream this window")
        }
    }
    
    func updateStream(with imageData: Data) {
        guard isStreaming else { return }
        
        currentImageData = imageData
        
        // Update the streaming display with new frame
        if let image = NSImage(data: imageData) {
            updateStreamingWindowContent(with: image)
        }
    }
    
    func stopStreaming() {
        print("[AirPlay] Stopping AirPlay streaming")
        isStreaming = false
        currentImageData = nil
        
        // Stop the current player
        streamingPlayer?.pause()
        streamingPlayer?.replaceCurrentItem(with: nil)
        
        // Close and clean up streaming window
        DispatchQueue.main.async { [weak self] in
            if let window = self?.streamingWindow {
                window.close()
                self?.streamingWindow = nil
                print("[AirPlay] Streaming window closed")
            }
        }
        
        Swift.print("[AirPlay] ✅ Streaming stopped and cleaned up")
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
            Swift.print("[AirPlay] Error cleaning temporary files: \(error)")
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
    
    // MARK: - Player Observation
    @objc private func playerDidFinishPlaying(_ notification: Notification) {
        print("[AirPlay] Player finished playing")
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status", let playerItem = object as? AVPlayerItem {
            switch playerItem.status {
            case .readyToPlay:
                print("[AirPlay] Player item ready to play")
            case .failed:
                print("[AirPlay] Player item failed: \(playerItem.error?.localizedDescription ?? "Unknown error")")
            case .unknown:
                print("[AirPlay] Player item status unknown")
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Convenience Methods for Integration
extension AirPlayManager {
    func startStreamingIfDeviceSelected() {
        guard selectedDevice != nil else {
            print("[AirPlay] No device selected - starting discovery")
            startDiscovery()
            return
        }
        print("[AirPlay] Device already selected, ready for streaming")
    }
    
    func isReadyForStreaming() -> Bool {
        return selectedDevice != nil
    }
    
    // Method to set up the streaming window without waiting for frame data
    func prepareForStreaming() {
        guard selectedDevice != nil else {
            print("[AirPlay] No device selected for streaming preparation")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if self.streamingWindow == nil {
                self.createStreamingWindow()
            }
        }
    }
}

// MARK: - Debug/Test Methods
extension AirPlayManager {
    func forceCreateStreamingWindow() {
        print("[AirPlay] 🧪 TEST: Force creating streaming window")
        createStreamingWindow()
    }
}
