import Foundation
import MultipeerConnectivity
import Combine

class DeviceManager: ObservableObject {
    @Published var peers: [Peer] = []
    @Published var currentSender: Peer? = nil
    
    private let myPeerId: MCPeerID
    private let myDeviceInfo: DeviceInfo
    
    init(myPeerId: MCPeerID, deviceInfo: DeviceInfo) {
        self.myPeerId = myPeerId
        self.myDeviceInfo = deviceInfo
    }
    
    // MARK: - Peer Management
    
    func addOrUpdatePeer(_ peerID: MCPeerID, state: MCSessionState, discoveryInfo: [String: String]? = nil) {
        if let existingPeer = peers.first(where: { $0.peer == peerID }) {
            existingPeer.state = state
        } else if state == .connecting || state == .connected {
            let newPeer = Peer(peer: peerID)
            newPeer.state = state
            
            // Parse device info from discovery
            if let info = discoveryInfo,
               let deviceTypeStr = info["deviceType"],
               let deviceType = DeviceType(rawValue: deviceTypeStr),
               let capabilitiesStr = info["capabilities"] {
                let capabilities = capabilitiesStr.split(separator: ",").compactMap { 
                    DeviceCapability(rawValue: String($0)) 
                }
                newPeer.deviceInfo = DeviceInfo(
                    peerId: peerID.displayName,
                    deviceType: deviceType,
                    capabilities: capabilities,
                    isCurrentlySending: false
                )
            }
            
            peers.append(newPeer)
        }
    }
    
    func removePeer(_ peerID: MCPeerID) {
        peers.removeAll { $0.peer == peerID }
        
        // Clear current sender if it was this peer
        if currentSender?.peer == peerID {
            currentSender = nil
        }
    }
    
    func resetPeer(_ peerID: MCPeerID) {
        if let peer = peers.first(where: { $0.peer == peerID }) {
            peer.state = .notConnected
            peer.deviceInfo = nil
        }
        
        // Clear current sender if it was this peer
        if currentSender?.peer == peerID {
            currentSender = nil
        }
    }
    
    func updatePeerDeviceInfo(_ peerID: MCPeerID, deviceInfo: DeviceInfo) {
        if let peer = peers.first(where: { $0.peer == peerID }) {
            peer.deviceInfo = deviceInfo
            peer.isCurrentlySending = deviceInfo.isCurrentlySending
            if deviceInfo.isCurrentlySending {
                currentSender = peer
            }
        }
    }
    
    func setCurrentSender(_ peer: Peer?) {
        currentSender = peer
    }
    
    func clearAllPeers() {
        peers.removeAll()
        currentSender = nil
    }
    
    func getMyPeerAsDevice() -> Peer? {
        return peers.first { $0.peer.displayName == myPeerId.displayName }
    }
    
    // MARK: - Device Info Broadcasting
    
    func createCurrentDeviceInfo(isCurrentlySending: Bool) -> DeviceInfo {
        return DeviceInfo(
            peerId: myPeerId.displayName,
            deviceType: myDeviceInfo.deviceType,
            capabilities: myDeviceInfo.capabilities,
            isCurrentlySending: isCurrentlySending
        )
    }
}
