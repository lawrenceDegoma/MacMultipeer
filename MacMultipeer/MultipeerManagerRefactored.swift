import Foundation
import MultipeerConnectivity
import Combine
import AppKit

class MultipeerManagerRefactored: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var peers: [Peer] = []
    @Published var isAdvertising = false
    @Published var isBrowsing = false
    @Published var lastImage: NSImage? = nil
    @Published var currentSender: Peer? = nil
    @Published var isController = false
    
    // MARK: - Components
    private let networking: MultipeerNetworking
    private let deviceManager: DeviceManager
    private let controller: MultipeerController
    
    // MARK: - Screen Capture
    var captureSender: MacCaptureSender?
    
    // MARK: - AirPlay Integration
    var airPlayManager: AirPlayManager = AirPlayManager()
    
    // MARK: - Configuration
    private let myPeerId = MCPeerID(displayName: Host.current().localizedName ?? "mac")
    private let myDeviceInfo = DeviceInfo(
        peerId: "",
        deviceType: .mac,
        capabilities: [.canSendScreen, .canReceiveScreen, .canControlInputs],
        isCurrentlySending: false
    )
    
    // MARK: - Public Access
    var myPeerID: MCPeerID { myPeerId }
    var sessionForDebug: MCSession { networking.sessionForDebug }
    
    override init() {
        // Initialize components
        self.networking = MultipeerNetworking(myPeerId: myPeerId, deviceInfo: myDeviceInfo)
        self.deviceManager = DeviceManager(myPeerId: myPeerId, deviceInfo: myDeviceInfo)
        self.controller = MultipeerController(networking: networking, deviceManager: deviceManager)
        
        super.init()
        
        // Set up networking delegate
        networking.delegate = self
        
        // Bind published properties
        setupBindings()
    }
    
    private func setupBindings() {
        // Bind device manager properties
        deviceManager.$peers
            .assign(to: &$peers)
        
        deviceManager.$currentSender
            .assign(to: &$currentSender)
        
        // Bind networking properties
        networking.$isAdvertising
            .assign(to: &$isAdvertising)
        
        networking.$isBrowsing
            .assign(to: &$isBrowsing)
        
        // Bind controller properties
        controller.$isController
            .assign(to: &$isController)
    }
    
    // MARK: - Public API
    
    // Networking Controls
    func toggleAdvertising() {
        if isAdvertising {
            networking.stopAdvertising()
        } else {
            networking.startAdvertising()
        }
    }
    
    func toggleBrowsing() {
        if isBrowsing {
            networking.stopBrowsing()
        } else {
            networking.startBrowsing()
        }
    }
    
    func invite(peer: Peer) {
        guard peer.state != .connecting && peer.state != .connected else {
            print("[Manager] Peer \(peer.displayName) already connecting/connected")
            return
        }
        
        print("[Manager] Inviting peer \(peer.displayName)")
        peer.state = .connecting
        networking.invitePeer(peer.peer)
    }
    
    // Controller Functions
    func enableControllerMode() {
        controller.enableControllerMode()
    }
    
    func switchInputToDevice(_ peer: Peer) {
        controller.switchInputToDevice(peer)
    }
    
    // Screen Capture
    func startSending() {
        guard captureSender == nil else { return }
        
        captureSender = MacCaptureSender(onFrame: { [weak self] data in
            self?.sendFrame(data)
        })
        captureSender?.start()
        
        // Update current sender tracking
        DispatchQueue.main.async {
            if let myPeer = self.deviceManager.getMyPeerAsDevice() {
                self.deviceManager.setCurrentSender(myPeer)
            }
        }
        
        // Broadcast updated device info
        broadcastDeviceInfo()
        print("[Manager] startSending: capture started")
    }
    
    func stopSending() {
        captureSender?.stop()
        captureSender = nil
        
        // Clear current sender tracking
        DispatchQueue.main.async {
            if self.deviceManager.currentSender?.peer.displayName == self.myPeerId.displayName {
                self.deviceManager.setCurrentSender(nil)
            }
        }
        
        // Broadcast updated device info
        broadcastDeviceInfo()
        print("[Manager] stopSending: capture stopped")
    }
    
    private func sendFrame(_ data: Data) {
        // Forward to Apple TV if laptop is current sender
        if deviceManager.currentSender?.peer.displayName == myPeerId.displayName {
            airPlayManager.handleIncomingFrame(data, from: myPeerId.displayName)
        }
        
        // Send to connected peers
        do {
            try networking.sendFrameData(data)
        } catch {
            print("[Manager] Failed to send frame: \(error)")
        }
    }
    
    // Utility Functions
    func resetConnection() {
        print("[Manager] Resetting all connections...")
        
        networking.disconnect()
        deviceManager.clearAllPeers()
        captureSender?.stop()
        captureSender = nil
        
        // Wait a moment, then restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.toggleAdvertising()
            self.toggleBrowsing()
        }
    }
    
    func sendDeviceInfo() {
        broadcastDeviceInfo()
    }
    
    private func broadcastDeviceInfo() {
        let deviceInfo = deviceManager.createCurrentDeviceInfo(isCurrentlySending: captureSender != nil)
        
        do {
            try networking.broadcastDeviceInfo(deviceInfo)
        } catch {
            print("[Manager] Failed to broadcast device info: \(error)")
        }
    }
}

// MARK: - MultipeerNetworkingDelegate
extension MultipeerManagerRefactored: MultipeerNetworkingDelegate {
    func didReceiveControlMessage(_ message: ControlMessage, from peerID: MCPeerID) {
        controller.handleControlMessage(message, from: peerID,
            onStartSending: { [weak self] in
                self?.startSending()
            },
            onStopSending: { [weak self] in
                self?.stopSending()
            }
        )
    }
    
    func didReceiveDeviceInfo(_ deviceInfo: DeviceInfo, from peerID: MCPeerID) {
        deviceManager.updatePeerDeviceInfo(peerID, deviceInfo: deviceInfo)
    }
    
    func didReceiveFrameData(_ data: Data, from peerID: MCPeerID) {
        // Store locally for preview (optional)
        if let img = NSImage(data: data) {
            self.lastImage = img
        }
        
        // Forward to Apple TV via AirPlay
        airPlayManager.handleIncomingFrame(data, from: peerID.displayName)
    }
}
