import Foundation
import MultipeerConnectivity
import Combine

protocol MultipeerNetworkingDelegate: AnyObject {
    func didReceiveControlMessage(_ message: ControlMessage, from peerID: MCPeerID)
    func didReceiveDeviceInfo(_ deviceInfo: DeviceInfo, from peerID: MCPeerID)
    func didReceiveFrameData(_ data: Data, from peerID: MCPeerID)
}

class MultipeerNetworking: NSObject, ObservableObject {
    @Published var isAdvertising = false
    @Published var isBrowsing = false
    
    private let serviceType = "screenshare"
    private let myPeerId: MCPeerID
    private let myDeviceInfo: DeviceInfo
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    
    weak var delegate: MultipeerNetworkingDelegate?
    
    // Debug counter for frame transmission
    private var debugFrameCounter: Int = 0
    
    init(myPeerId: MCPeerID, deviceInfo: DeviceInfo) {
        self.myPeerId = myPeerId
        self.myDeviceInfo = deviceInfo
        super.init()
        
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
    }
    
    // MARK: - Public API
    
    var connectedPeers: [MCPeerID] {
        return session.connectedPeers
    }
    
    var sessionForDebug: MCSession {
        return session
    }
    
    func startAdvertising() {
        guard !isAdvertising else { return }
        
        let discoveryInfo = [
            "deviceType": myDeviceInfo.deviceType.rawValue,
            "capabilities": myDeviceInfo.capabilities.map { $0.rawValue }.joined(separator: ",")
        ]
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: discoveryInfo, serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        isAdvertising = true
        print("[Networking] Started advertising with serviceType=\(serviceType) peer=\(myPeerId.displayName)")
    }
    
    func stopAdvertising() {
        guard isAdvertising else { return }
        
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        isAdvertising = false
        print("[Networking] Stopped advertising")
    }
    
    func startBrowsing() {
        guard !isBrowsing else { return }
        
        browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        isBrowsing = true
        print("[Networking] Started browsing for serviceType=\(serviceType) peer=\(myPeerId.displayName)")
    }
    
    func stopBrowsing() {
        guard isBrowsing else { return }
        
        browser?.stopBrowsingForPeers()
        browser = nil
        isBrowsing = false
        print("[Networking] Stopped browsing")
    }
    
    func invitePeer(_ peerID: MCPeerID) {
        guard let browser = browser else {
            print("[Networking] invite: browser is nil")
            return
        }
        
        // Check if we're already connected to this peer
        if session.connectedPeers.contains(peerID) {
            print("[Networking] Already connected to \(peerID.displayName)")
            return
        }
        
        print("[Networking] Inviting peer \(peerID.displayName)")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
    }
    
    func sendControlCommand(_ message: ControlMessage, to peerID: MCPeerID) throws {
        guard session.connectedPeers.contains(peerID) else {
            throw NetworkingError.peerNotConnected
        }
        
        let data = try JSONEncoder().encode(message)
        try session.send(data, toPeers: [peerID], with: .reliable)
        print("[Networking] Sent command \(message.command) to \(peerID.displayName)")
    }
    
    func broadcastDeviceInfo(_ deviceInfo: DeviceInfo) throws {
        guard !session.connectedPeers.isEmpty else {
            print("[Networking] No connected peers to broadcast to")
            return
        }
        
        let actuallyConnectedPeers = session.connectedPeers.filter { peer in
            session.connectedPeers.contains(peer)
        }
        
        guard !actuallyConnectedPeers.isEmpty else {
            print("[Networking] No actually connected peers")
            return
        }
        
        let data = try JSONEncoder().encode(deviceInfo)
        let dataWithType = "DEVICE_INFO:".data(using: .utf8)! + data
        try session.send(dataWithType, toPeers: actuallyConnectedPeers, with: .unreliable)
        print("[Networking] Broadcast successful to \(actuallyConnectedPeers.map { $0.displayName })")
    }
    
    func sendFrameData(_ data: Data) throws {
        let connectedPeers = session.connectedPeers
        guard !connectedPeers.isEmpty else {
            return // No peers to send to
        }
        
        // Check if session is actually ready for data transmission
        guard connectedPeers.allSatisfy({ session.connectedPeers.contains($0) }) else {
            if debugFrameCounter % 50 == 0 {
                print("[Networking] Skipping frame - not all peers are stably connected")
            }
            debugFrameCounter += 1
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Use unreliable transmission for frame data to reduce protocol overhead
                try self.session.send(data, toPeers: connectedPeers, with: .unreliable)
                // Only log occasionally to reduce console spam
                if self.debugFrameCounter % 10 == 0 {
                    print("[Networking] Frame sent via unreliable transport to \(connectedPeers.count) peers")
                }
                self.debugFrameCounter += 1
            } catch {
                print("[Networking] Failed to send frame:", error)
            }
        }
    }
    
    func disconnect() {
        session.disconnect()
        stopAdvertising()
        stopBrowsing()
    }
}

// MARK: - Error Types
enum NetworkingError: Error {
    case peerNotConnected
    case encodingFailed
    case sendingFailed
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerNetworking: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            print("[Networking] Received invitation from peer: \(peerID.displayName)")
            
            // Check if we're already connected
            if self.session.connectedPeers.contains(peerID) {
                print("[Networking] Already connected to \(peerID.displayName), declining invitation")
                invitationHandler(false, nil)
                return
            }
            
            // Auto-accept the invitation
            print("[Networking] Accepting invitation from \(peerID.displayName)")
            invitationHandler(true, self.session)
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("[Networking] advertiser didNotStartAdvertisingPeer error:\(error)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerNetworking: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        DispatchQueue.main.async {
            print("[Networking] foundPeer: \(peerID.displayName) with info: \(info ?? [:])")
            // Delegate will handle peer management
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            print("[Networking] lostPeer: \(peerID.displayName)")
            // Delegate will handle peer removal
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotSearch error: Error) {
        print("[Networking] browser didNotSearch error:\(error)")
    }
}

// MARK: - MCSessionDelegate
extension MultipeerNetworking: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            print("[Networking] session: peer=\(peerID.displayName) state=\(state.rawValue)")
            // Delegate will handle state changes
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Check if this is a control message or device info
        if let dataString = String(data: data, encoding: .utf8), dataString.hasPrefix("DEVICE_INFO:") {
            let infoData = data.dropFirst("DEVICE_INFO:".count)
            do {
                let deviceInfo = try JSONDecoder().decode(DeviceInfo.self, from: infoData)
                DispatchQueue.main.async {
                    self.delegate?.didReceiveDeviceInfo(deviceInfo, from: peerID)
                }
                print("[Networking] Updated info for \(peerID.displayName): \(deviceInfo)")
            } catch {
                print("[Networking] Failed to decode device info: \(error)")
            }
            return
        }
        
        // Try to decode as control message
        do {
            let controlMessage = try JSONDecoder().decode(ControlMessage.self, from: data)
            DispatchQueue.main.async {
                self.delegate?.didReceiveControlMessage(controlMessage, from: peerID)
            }
            return
        } catch {
            // Not a control message, treat as frame data
        }
        
        // Handle incoming frame data
        DispatchQueue.main.async {
            print("[Networking] didReceive frame from \(peerID.displayName); size=\(data.count)")
            self.delegate?.didReceiveFrameData(data, from: peerID)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
