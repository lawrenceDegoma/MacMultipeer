import Foundation
import MultipeerConnectivity
import Combine
import AppKit

enum DeviceCapability: String, CaseIterable, Codable {
    case canSendScreen = "screen_sender"
    case canReceiveScreen = "screen_receiver" 
    case canControlInputs = "input_controller"
}

enum DeviceType: String, CaseIterable, Codable {
    case mac = "mac"
    case iPhone = "iphone"
    case iPad = "ipad"
}

enum ControlCommand: String, Codable {
    case startSending = "start_sending"
    case stopSending = "stop_sending"
    case switchToSender = "switch_to_sender"
}

struct DeviceInfo: Codable {
    let peerId: String
    let deviceType: DeviceType
    let capabilities: [DeviceCapability]
    let isCurrentlySending: Bool
}

struct ControlMessage: Codable {
    let command: ControlCommand
    let targetPeerId: String?
    let sourceInfo: DeviceInfo
}

class Peer: Identifiable {
    let id = UUID()
    let peer: MCPeerID
    var displayName: String { peer.displayName }
    var state: MCSessionState = .notConnected
    var deviceInfo: DeviceInfo?
    var isCurrentlySending: Bool = false

    init(peer: MCPeerID) { 
        self.peer = peer 
    }
}

class MultipeerManager: NSObject, ObservableObject {
    private let serviceType = "screenshare"
    private let myPeerId = MCPeerID(displayName: Host.current().localizedName ?? "mac")
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var session: MCSession!

    @Published var peers: [Peer] = []
    @Published var isAdvertising = false
    @Published var isBrowsing = false
    @Published var lastImage: NSImage? = nil
    @Published var currentSender: Peer? = nil // Track who's currently sending
    @Published var isController = false // Whether this device acts as controller

    // Public access to peer ID
    var myPeerID: MCPeerID { myPeerId }
    
    // Public access to session for debugging
    var sessionForDebug: MCSession { session }

    // Device capabilities for this Mac
    private let myDeviceInfo = DeviceInfo(
        peerId: "",
        deviceType: .mac,
        capabilities: [.canSendScreen, .canReceiveScreen, .canControlInputs],
        isCurrentlySending: false
    )

    // make captureSender internal so UI can access it
    var captureSender: MacCaptureSender?
    
    // AirPlay manager for Apple TV output
    var airPlayManager: AirPlayManager = AirPlayManager()
    
    // Debug counter for frame transmission
    private var debugFrameCounter: Int = 0

    override init() {
        super.init()
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
    }

    // MARK: - StreamDeck-like Control Functions
    
    func enableControllerMode() {
        isController = true
        print("[Controller] Enabled controller mode")
    }
    
    func switchInputToDevice(_ peer: Peer) {
        guard isController else {
            print("[Controller] Not in controller mode")
            return
        }
        
        guard peer.state == .connected else {
            print("[Controller] Peer \(peer.displayName) is not connected (state: \(peer.state.rawValue))")
            return
        }
        
        guard session.connectedPeers.contains(peer.peer) else {
            print("[Controller] Peer \(peer.displayName) not in session's connected peers")
            return
        }
        
        // First stop current sender
        if let currentSender = currentSender, currentSender.peer != peer.peer {
            sendControlCommand(.stopSending, to: currentSender)
        }
        
        // Then start new sender (only if it's not already sending)
        if currentSender?.peer != peer.peer {
            sendControlCommand(.startSending, to: peer)
        }
        
        print("[Controller] Switching input to \(peer.displayName)")
    }
    
    private func sendControlCommand(_ command: ControlCommand, to peer: Peer) {
        guard peer.state == .connected else {
            print("[Controller] Cannot send command to \(peer.displayName) - not connected")
            return
        }
        
        guard session.connectedPeers.contains(peer.peer) else {
            print("[Controller] Cannot send command to \(peer.displayName) - not in session")
            return
        }
        
        let message = ControlMessage(
            command: command,
            targetPeerId: peer.peer.displayName,
            sourceInfo: myDeviceInfo
        )
        
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: [peer.peer], with: .reliable)
            print("[Controller] Sent command \(command) to \(peer.displayName)")
        } catch {
            print("[Controller] Failed to send command \(command) to \(peer.displayName): \(error)")
        }
    }
    
    private func handleControlMessage(_ message: ControlMessage, from peerID: MCPeerID) {
        print("[Control] Received command \(message.command) from \(peerID.displayName)")
        
        switch message.command {
        case .startSending:
            if message.targetPeerId == myPeerId.displayName || message.targetPeerId == nil {
                // Add a small delay to allow connection to stabilize
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.startSending()
                }
            }
        case .stopSending:
            if message.targetPeerId == myPeerId.displayName || message.targetPeerId == nil {
                stopSending()
            }
        case .switchToSender:
            if message.targetPeerId == myPeerId.displayName {
                // Add a small delay to allow connection to stabilize
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.startSending()
                }
            } else {
                stopSending()
            }
        }
    }
    
    private func broadcastDeviceInfo() {
        guard !session.connectedPeers.isEmpty else {
            print("[DeviceInfo] No connected peers to broadcast to")
            return
        }
        
        // Double-check that peers are actually connected
        let actuallyConnectedPeers = session.connectedPeers.filter { peer in
            session.connectedPeers.contains(peer)
        }
        
        guard !actuallyConnectedPeers.isEmpty else {
            print("[DeviceInfo] No actually connected peers")
            return
        }
        
        var deviceInfo = myDeviceInfo
        deviceInfo = DeviceInfo(
            peerId: myPeerId.displayName,
            deviceType: deviceInfo.deviceType,
            capabilities: deviceInfo.capabilities,
            isCurrentlySending: captureSender != nil
        )
        
        do {
            let data = try JSONEncoder().encode(deviceInfo)
            let dataWithType = "DEVICE_INFO:".data(using: .utf8)! + data
            try session.send(dataWithType, toPeers: actuallyConnectedPeers, with: .unreliable)
            print("[DeviceInfo] Broadcast successful to \(actuallyConnectedPeers.map { $0.displayName })")
        } catch {
            print("[DeviceInfo] Failed to broadcast: \(error)")
        }
    }

    func startSending() {
        // start capture and forward frames via sendFrame closure
        guard captureSender == nil else { return }
        captureSender = MacCaptureSender(onFrame: { [weak self] data in
            self?.sendFrame(data)
        })
        captureSender?.start()
        
        // Update current sender tracking
        DispatchQueue.main.async {
            if let myPeer = self.peers.first(where: { $0.peer.displayName == self.myPeerId.displayName }) {
                self.currentSender = myPeer
            }
        }
        
        // Broadcast updated device info
        broadcastDeviceInfo()
        print("[Multipeer] startSending: capture started")
    }

    func stopSending() {
        captureSender?.stop()
        captureSender = nil
        
        // Clear current sender tracking
        DispatchQueue.main.async {
            if self.currentSender?.peer.displayName == self.myPeerId.displayName {
                self.currentSender = nil
            }
        }
        
        // Broadcast updated device info
        broadcastDeviceInfo()
        print("[Multipeer] stopSending: capture stopped")
    }

    private func sendFrame(_ data: Data) {
        let peersCount = session.connectedPeers.count
        guard peersCount > 0 else {
            // no connected peers, but still forward to Apple TV if laptop is current sender
            if currentSender?.peer.displayName == myPeerId.displayName {
                airPlayManager.handleIncomingFrame(data, from: myPeerId.displayName)
            }
            return
        }
        
        // Double-check connection state before sending and verify each peer individually
        let connectedPeers = session.connectedPeers
        guard !connectedPeers.isEmpty else {
            // Still forward to Apple TV if laptop is current sender
            if currentSender?.peer.displayName == myPeerId.displayName {
                airPlayManager.handleIncomingFrame(data, from: myPeerId.displayName)
            }
            return
        }
        
        // Check if session is actually ready for data transmission
        guard connectedPeers.allSatisfy({ session.connectedPeers.contains($0) }) else {
            if debugFrameCounter % 50 == 0 {
                print("[Multipeer] Skipping frame - not all peers are stably connected")
            }
            debugFrameCounter += 1
            return
        }
        
        // Forward laptop screen to Apple TV if laptop is the current sender
        if currentSender?.peer.displayName == myPeerId.displayName {
            airPlayManager.handleIncomingFrame(data, from: myPeerId.displayName)
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Use unreliable transmission for frame data to reduce protocol overhead
                try self.session.send(data, toPeers: connectedPeers, with: .unreliable)
                // Only log occasionally to reduce console spam
                if self.debugFrameCounter % 10 == 0 {
                    print("Frame sent via unreliable transport to \(peersCount) peers")
                }
                self.debugFrameCounter += 1
            } catch {
                print("[Multipeer] Failed to send frame:", error)
            }
        }
    }

    func toggleAdvertising() {
        if isAdvertising {
            advertiser?.stopAdvertisingPeer()
            advertiser = nil
            isAdvertising = false
            print("[Multipeer] Stopped advertising")
        } else {
            // Include device capabilities in discovery info
            let discoveryInfo = [
                "deviceType": myDeviceInfo.deviceType.rawValue,
                "capabilities": myDeviceInfo.capabilities.map { $0.rawValue }.joined(separator: ",")
            ]
            advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: discoveryInfo, serviceType: serviceType)
            advertiser?.delegate = self
            advertiser?.startAdvertisingPeer()
            isAdvertising = true
            print("[Multipeer] Started advertising with serviceType=\(serviceType) peer=\(myPeerId.displayName)")
        }
    }

    func toggleBrowsing() {
        if isBrowsing {
            browser?.stopBrowsingForPeers()
            browser = nil
            isBrowsing = false
            print("[Multipeer] Stopped browsing")
        } else {
            browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
            browser?.delegate = self
            browser?.startBrowsingForPeers()
            isBrowsing = true
            print("[Multipeer] Started browsing for serviceType=\(serviceType) peer=\(myPeerId.displayName)")
        }
    }

    func invite(peer: Peer) {
        guard let browser = browser else { 
            print("[Multipeer] invite: browser is nil")
            return 
        }
        
        // Check if we're already connected to this peer
        if session.connectedPeers.contains(peer.peer) {
            print("[Multipeer] Already connected to \(peer.displayName)")
            return
        }
        
        // Check if peer is already connecting
        if peer.state == .connecting {
            print("[Multipeer] Already connecting to \(peer.displayName)")
            return
        }
        
        print("[Multipeer] inviting peer \(peer.displayName)")
        peer.state = .connecting
        browser.invitePeer(peer.peer, to: session, withContext: nil, timeout: 30)
    }
    
    func resetConnection() {
        print("[Multipeer] Resetting all connections...")
        
        // Disconnect from all peers
        session.disconnect()
        
        // Stop advertising and browsing
        if isAdvertising {
            toggleAdvertising()
        }
        if isBrowsing {
            toggleBrowsing()
        }
        
        // Clear peer list
        peers.removeAll()
        currentSender = nil
        
        // Wait a moment, then restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.toggleAdvertising()
            self.toggleBrowsing()
        }
    }
    
    // Manual device info broadcast for testing
    func sendDeviceInfo() {
        broadcastDeviceInfo()
    }
}

// MARK: MCNearbyServiceAdvertiserDelegate
extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            print("[Multipeer] Received invitation from peer: \(peerID.displayName)")
            
            // Check if we're already connected
            if self.session.connectedPeers.contains(peerID) {
                print("[Multipeer] Already connected to \(peerID.displayName), declining invitation")
                invitationHandler(false, nil)
                return
            }
            
            // Check if we're already connecting
            if let peer = self.peers.first(where: { $0.peer == peerID }), peer.state == .connecting {
                print("[Multipeer] Already connecting to \(peerID.displayName), declining invitation")
                invitationHandler(false, nil)
                return
            }
            
            // Auto-accept the invitation
            print("[Multipeer] Accepting invitation from \(peerID.displayName)")
            invitationHandler(true, self.session)
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("[Multipeer] advertiser didNotStartAdvertisingPeer error:\(error)")
    }
}

// MARK: MCNearbyServiceBrowserDelegate
extension MultipeerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        DispatchQueue.main.async {
            print("[Multipeer] foundPeer: \(peerID.displayName) with info: \(info ?? [:])")
            if !self.peers.contains(where: { $0.peer == peerID }) {
                let peer = Peer(peer: peerID)
                
                // Parse device info from discovery
                if let info = info,
                   let deviceTypeStr = info["deviceType"],
                   let deviceType = DeviceType(rawValue: deviceTypeStr),
                   let capabilitiesStr = info["capabilities"] {
                    let capabilities = capabilitiesStr.split(separator: ",").compactMap { DeviceCapability(rawValue: String($0)) }
                    peer.deviceInfo = DeviceInfo(
                        peerId: peerID.displayName,
                        deviceType: deviceType,
                        capabilities: capabilities,
                        isCurrentlySending: false
                    )
                }
                
                self.peers.append(peer)
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            print("[Multipeer] lostPeer: \(peerID.displayName)")
            self.peers.removeAll { $0.peer == peerID }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotSearch error: Error) {
        print("[Multipeer] browser didNotSearch error:\(error)")
    }
}

// MARK: MCSessionDelegate
extension MultipeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            print("[Multipeer] session: peer=\(peerID.displayName) state=\(state.rawValue)")
            
            // Find or create peer in our list
            if let existingPeer = self.peers.first(where: { $0.peer == peerID }) {
                existingPeer.state = state
            } else if state == .connecting || state == .connected {
                // Add new peer if we don't have it and it's connecting/connected
                let newPeer = Peer(peer: peerID)
                newPeer.state = state
                self.peers.append(newPeer)
                print("[Multipeer] Added new peer to list: \(peerID.displayName)")
            }
            
            // Clean up disconnected peers
            if state == .notConnected {
                // Reset peer state instead of removing completely
                if let peer = self.peers.first(where: { $0.peer == peerID }) {
                    peer.state = .notConnected
                    peer.deviceInfo = nil
                    print("[Multipeer] Reset disconnected peer: \(peerID.displayName)")
                }
            }
            
            print("[Multipeer] connectedPeers count=\(session.connectedPeers.count)")
            print("[Multipeer] managed peers: \(self.peers.map { "\($0.displayName)(\($0.state.rawValue))" })")
            
            if state == .connected {
                print("[Multipeer] ✅ Successfully connected to \(peerID.displayName)")
                // Don't auto-broadcast device info immediately, let connection stabilize
            } else if state == .notConnected {
                // Clear current sender if it was this peer
                if self.currentSender?.peer == peerID {
                    self.currentSender = nil
                }
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Check if this is a control message or device info
        if let dataString = String(data: data, encoding: .utf8), dataString.hasPrefix("DEVICE_INFO:") {
            let infoData = data.dropFirst("DEVICE_INFO:".count)
            do {
                let deviceInfo = try JSONDecoder().decode(DeviceInfo.self, from: infoData)
                DispatchQueue.main.async {
                    if let peer = self.peers.first(where: { $0.peer == peerID }) {
                        peer.deviceInfo = deviceInfo
                        peer.isCurrentlySending = deviceInfo.isCurrentlySending
                        if deviceInfo.isCurrentlySending {
                            self.currentSender = peer
                        }
                    }
                }
                print("[DeviceInfo] Updated info for \(peerID.displayName): \(deviceInfo)")
            } catch {
                print("[DeviceInfo] Failed to decode: \(error)")
            }
            return
        }
        
        // Try to decode as control message
        do {
            let controlMessage = try JSONDecoder().decode(ControlMessage.self, from: data)
            handleControlMessage(controlMessage, from: peerID)
            return
        } catch {
            // Not a control message, treat as frame data
        }
        
        // handle incoming frame data
        DispatchQueue.main.async {
            print("[Multipeer] didReceive frame from \(peerID.displayName); size=\(data.count)")
            
            // Store locally for preview (optional)
            if let img = NSImage(data: data) {
                self.lastImage = img
            }
            
            // Forward to Apple TV via AirPlay
            self.airPlayManager.handleIncomingFrame(data, from: peerID.displayName)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
