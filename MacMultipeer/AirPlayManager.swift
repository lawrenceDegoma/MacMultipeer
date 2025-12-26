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
    }
    
    func startStreaming(with imageData: Data) {
        guard let device = selectedDevice else {
            print("[AirPlay] No device selected for streaming")
            return
        }
        
        currentImageData = imageData
        isStreaming = true
        
        // Convert Data to NSImage for AirPlay
        if let image = NSImage(data: imageData) {
            streamImageToAppleTV(image: image, device: device)
        }
    }
    
    func updateStream(with imageData: Data) {
        guard isStreaming, let device = selectedDevice else { return }
        
        currentImageData = imageData
        
        if let image = NSImage(data: imageData) {
            streamImageToAppleTV(image: image, device: device)
        }
    }
    
    func stopStreaming() {
        isStreaming = false
        currentImageData = nil
        print("[AirPlay] Stopped streaming to Apple TV")
    }
    
    private func streamImageToAppleTV(image: NSImage, device: AirPlayDevice) {
        // This is where the actual AirPlay magic would happen
        // For now, we'll use a simple approach with AVPlayerLayer or similar
        
        print("[AirPlay] Streaming frame to \(device.name) - Image size: \(image.size)")
        
        // In a real implementation, you would:
        // 1. Create an AVPlayerLayer or similar
        // 2. Use AVRoutePickerView for device selection
        // 3. Stream the image data to the selected AirPlay device
        
        // Placeholder implementation
        DispatchQueue.global(qos: .userInitiated).async {
            // Simulate streaming
            print("[AirPlay] Frame sent to Apple TV")
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
