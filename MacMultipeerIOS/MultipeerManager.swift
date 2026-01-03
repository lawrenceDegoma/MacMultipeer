#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

import Foundation
import MultipeerConnectivity
import Combine

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
    private let myPeerId: MCPeerID = {
        #if os(macOS)
        return MCPeerID(displayName: Host.current().localizedName ?? "mac")
        #else
        return MCPeerID(displayName: UIDevice.current.name)
        #endif
    }()

    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var session: MCSession!

    @Published var peers: [Peer] = []
    @Published var isAdvertising = false
    @Published var isBrowsing = false
    @Published var lastImage: PlatformImage? = nil
    @Published var currentSender: Peer? = nil // Track who's currently sending
    @Published var isController = false // Whether this device acts as controller

    // Public access to peer ID
    var myPeerID: MCPeerID { myPeerId }
    
    // Public access to session for debugging
    var sessionForDebug: MCSession { session }

    // Device capabilities
    private let myDeviceInfo: DeviceInfo = {
        #if os(macOS)
        return DeviceInfo(
            peerId: "",
            deviceType: .mac,
            capabilities: [.canSendScreen, .canReceiveScreen, .canControlInputs],
            isCurrentlySending: false
        )
        #else
        let deviceType: DeviceType = UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        return DeviceInfo(
            peerId: "",
            deviceType: deviceType,
            capabilities: [.canSendScreen, .canReceiveScreen, .canControlInputs],
            isCurrentlySending: false
        )
        #endif
    }()

    // Debug counter for frame transmission (macOS only)
    #if os(macOS)
    private var debugFrameCounter: Int = 0
    #endif

    override init() {
        super.init()
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        
        // Add background handling for iOS
        #if os(iOS)
        setupBackgroundHandling()
        #endif
    }
    
    #if os(iOS)
    private func setupBackgroundHandling() {
        // Listen for background refresh notifications
        NotificationCenter.default.addObserver(
            forName: .backgroundRefresh,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.maintainConnectionsInBackground()
        }
        
        // Listen for app lifecycle events
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("UIApplicationWillResignActiveNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppWillResignActive()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("UIApplicationDidBecomeActiveNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppDidBecomeActive()
        }
    }
    
    private func handleAppWillResignActive() {
        print("[MultipeerManager] App will resign active - maintaining connections")
        // Keep connections alive by sending heartbeat
        sendHeartbeatToConnectedPeers()
    }
    
    private func handleAppDidBecomeActive() {
        print("[MultipeerManager] App became active - resuming normal operation")
        // Resume normal operations
        cleanupPeers()
    }
    
    private func maintainConnectionsInBackground() {
        print("[MultipeerManager] Maintaining connections in background")
        
        // Send heartbeat to keep connections alive
        sendHeartbeatToConnectedPeers()
        
        // Clean up any stale connections
        cleanupPeers()
    }
    
    private func sendHeartbeatToConnectedPeers() {
        let heartbeatData = "HEARTBEAT".data(using: .utf8)!
        
        for peer in peers where peer.state == .connected {
            do {
                try session.send(heartbeatData, toPeers: [peer.peer], with: .unreliable)
            } catch {
                print("[Heartbeat] Failed to send heartbeat to \(peer.displayName): \(error)")
            }
        }
        
        if !peers.isEmpty {
            print("[Heartbeat] Sent heartbeat to \(peers.filter { $0.state == .connected }.count) connected peers")
        }
    }
    #endif

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
                // iOS screen sharing would need additional implementation
                print("[iOS] Screen sharing not implemented yet")
            }
        case .stopSending:
            if message.targetPeerId == myPeerId.displayName || message.targetPeerId == nil {
                // iOS stop sending would be handled here
                print("[iOS] Stop sending not implemented yet")
            }
        case .switchToSender:
            if message.targetPeerId == myPeerId.displayName {
                // iOS screen sharing would need additional implementation
                print("[iOS] Switch to sender not implemented yet")
            } else {
                // iOS stop sending would be handled here
                print("[iOS] Stop sending not implemented yet")
            }
        }
    }
    
    private func broadcastDeviceInfo() {
        guard !session.connectedPeers.isEmpty else {
            print("[DeviceInfo] No connected peers to broadcast to")
            return
        }
        
        // Triple-check that peers are actually connected and session is stable
        let actuallyConnectedPeers = session.connectedPeers.filter { peer in
            session.connectedPeers.contains(peer)
        }
        
        guard !actuallyConnectedPeers.isEmpty else {
            print("[DeviceInfo] No actually connected peers")
            return
        }
        
        // Wait a bit more to ensure the session channels are fully established
        print("[DeviceInfo] Waiting for channels to stabilize before broadcasting...")
        
        var deviceInfo = myDeviceInfo
        deviceInfo = DeviceInfo(
            peerId: myPeerId.displayName,
            deviceType: deviceInfo.deviceType,
            capabilities: deviceInfo.capabilities,
            isCurrentlySending: false // iOS doesn't support screen capture yet
        )
        
        do {
            let data = try JSONEncoder().encode(deviceInfo)
            let dataWithType = "DEVICE_INFO:".data(using: .utf8)! + data
            
            // Add delay to ensure channel stability
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Final check that connection is still stable
                guard self.session.connectedPeers.contains(where: { actuallyConnectedPeers.contains($0) }) else {
                    print("[DeviceInfo] Connection no longer stable at broadcast time")
                    return
                }
                
                do {
                    try self.session.send(dataWithType, toPeers: actuallyConnectedPeers, with: .reliable)
                    print("[DeviceInfo] Broadcast successful to \(actuallyConnectedPeers.map { $0.displayName })")
                } catch {
                    print("[DeviceInfo] Failed to broadcast (with channel stability check): \(error)")
                    // If this fails, the connection might not be fully ready yet
                    // Try one more time after another delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        do {
                            let stillConnectedPeers = self.session.connectedPeers
                            if !stillConnectedPeers.isEmpty {
                                try self.session.send(dataWithType, toPeers: stillConnectedPeers, with: .reliable)
                                print("[DeviceInfo] Retry broadcast successful")
                            }
                        } catch {
                            print("[DeviceInfo] Retry broadcast also failed: \(error)")
                        }
                    }
                }
            }
        } catch {
            print("[DeviceInfo] Failed to encode device info: \(error)")
        }
    }

    // MARK: - Network Management

    func toggleAdvertising() {
        if isAdvertising {
            advertiser?.stopAdvertisingPeer()
            advertiser = nil
            isAdvertising = false
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
        }
    }

    func toggleBrowsing() {
        if isBrowsing {
            stopBrowsing()
        } else {
            startBrowsing()
        }
    }
    
    func startBrowsing() {
        guard !isBrowsing else { return }
        
        // Clean up any stale peers before starting to browse
        cleanupPeers()
        
        browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        isBrowsing = true
        print("[Multipeer] Started browsing for serviceType=\(serviceType) peer=\(myPeerId.displayName)")
    }
    
    func stopBrowsing() {
        guard isBrowsing else { return }
        browser?.stopBrowsingForPeers()
        browser = nil
        isBrowsing = false
        print("[Multipeer] Stopped browsing")
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
        browser.invitePeer(peer.peer, to: session, withContext: nil, timeout: 60) // Increased timeout
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
    
    // MARK: - Test Methods
    func sendTestMessage(_ data: Data) {
        let connectedPeers = session.connectedPeers
        guard !connectedPeers.isEmpty else {
            print("[Test] No connected peers available")
            return
        }
        
        do {
            try session.send(data, toPeers: connectedPeers, with: .reliable)
            print("[Test] ✅ Sent test message to \(connectedPeers.count) peers")
        } catch {
            print("[Test] ❌ Failed to send test message: \(error)")
        }
    }
    
    func sendTestControl() {
        let testMessage = ControlMessage(
            command: .startSending,
            targetPeerId: nil,
            sourceInfo: DeviceInfo(
                peerId: myPeerId.displayName,
                deviceType: .iPhone,
                capabilities: [.canControlInputs],
                isCurrentlySending: false
            )
        )
        
        let connectedPeers = session.connectedPeers
        guard !connectedPeers.isEmpty else {
            print("[Test] No connected peers available for control")
            return
        }
        
        do {
            let data = try JSONEncoder().encode(testMessage)
            try session.send(data, toPeers: connectedPeers, with: .reliable)
            print("[Test] ✅ Sent test control to \(connectedPeers.count) peers")
        } catch {
            print("[Test] ❌ Failed to send test control: \(error)")
        }
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
            
            // Remove any existing peer with the same display name to avoid duplicates
            self.peers.removeAll { $0.peer.displayName == peerID.displayName }
            
            // Add the new peer
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
            print("[Multipeer] Added unique peer: \(peerID.displayName), total peers: \(self.peers.count)")
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.peers.removeAll { $0.peer == peerID }
        }
    }
}

// MARK: MCSessionDelegate
extension MultipeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            print("[Multipeer] session: peer=\(peerID.displayName) state=\(state.rawValue)")
            
            // Remove any existing peer with the same display name to avoid duplicates
            self.peers.removeAll { $0.peer.displayName == peerID.displayName && $0.peer != peerID }
            
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
                // Don't auto-stop browsing to allow additional connections
                // Give connection time to stabilize before broadcasting device info
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Check that the peer is still connected and session is stable
                    guard session.connectedPeers.contains(peerID) else {
                        print("[Multipeer] Connection no longer stable, skipping device info broadcast")
                        return
                    }
                    print("[Multipeer] Connection stable, broadcasting device info")
                    self.broadcastDeviceInfo()
                }
            } else if state == .notConnected {
                // Clear current sender if it was this peer
                if self.currentSender?.peer == peerID {
                    self.currentSender = nil
                }
                // If we lost all connections, resume browsing
                if session.connectedPeers.isEmpty && !self.isBrowsing {
                    print("[Multipeer] No connected peers, resuming browsing")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if !self.isBrowsing {
                            self.startBrowsing()
                        }
                    }
                }
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Check for test messages first
        if let dataString = String(data: data, encoding: .utf8), dataString.hasPrefix("TEST_MESSAGE:") {
            let message = String(dataString.dropFirst("TEST_MESSAGE:".count))
            print("[Test] ✅ Received test message from \(peerID.displayName): \(message)")
            return
        }
        
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
            #if os(iOS)
            if let img = UIImage(data: data) {
                self.lastImage = img
            }
            #else
            if let img = NSImage(data: data) {
                self.lastImage = img
            }
            #endif
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
    
    // Clean up duplicate and stale peers
    func cleanupPeers() {
        DispatchQueue.main.async {
            let beforeCount = self.peers.count
            
            // Remove disconnected peers that have been disconnected for a while
            self.peers.removeAll { peer in
                peer.state == .notConnected && !self.session.connectedPeers.contains(peer.peer)
            }
            
            // Remove duplicates based on display name, keeping the most recently connected one
            var seenNames: [String: Peer] = [:]
            
            for peer in self.peers {
                if let existingPeer = seenNames[peer.displayName] {
                    // Keep the one that's connected, or the newer one if both have same state
                    if peer.state == .connected && existingPeer.state != .connected {
                        seenNames[peer.displayName] = peer
                    } else if peer.state == existingPeer.state {
                        // If same state, keep the one that's in the actual session
                        if self.session.connectedPeers.contains(peer.peer) {
                            seenNames[peer.displayName] = peer
                        }
                    }
                } else {
                    seenNames[peer.displayName] = peer
                }
            }
            
            self.peers = Array(seenNames.values)
            
            let afterCount = self.peers.count
            if beforeCount != afterCount {
                print("[Multipeer] Cleaned up \(beforeCount - afterCount) duplicate/stale peers")
                print("[Multipeer] Remaining peers: \(self.peers.map { "\($0.displayName)(\($0.state.rawValue))" })")
            }
        }
    }
    
    // Add debugging function to test connection
    func sendTestMessage() {
        guard !session.connectedPeers.isEmpty else {
            print("[Test] No connected peers to send test message to")
            return
        }
        
        let testMessage = "TEST_MESSAGE:Hello from \(myPeerId.displayName) at \(Date())"
        guard let data = testMessage.data(using: .utf8) else { return }
        
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            print("[Test] ✅ Sent test message to \(session.connectedPeers.map { $0.displayName })")
        } catch {
            print("[Test] ❌ Failed to send test message: \(error)")
        }
    }
}
