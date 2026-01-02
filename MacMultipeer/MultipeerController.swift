import Foundation
import MultipeerConnectivity
import Combine

class MultipeerController: ObservableObject {
    @Published var isController = false
    
    private let networking: MultipeerNetworking
    private let deviceManager: DeviceManager
    
    init(networking: MultipeerNetworking, deviceManager: DeviceManager) {
        self.networking = networking
        self.deviceManager = deviceManager
    }
    
    // MARK: - Controller Mode
    
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
        
        guard networking.connectedPeers.contains(peer.peer) else {
            print("[Controller] Peer \(peer.displayName) not in session's connected peers")
            return
        }
        
        // First stop current sender
        if let currentSender = deviceManager.currentSender, currentSender.peer != peer.peer {
            sendControlCommand(.stopSending, to: currentSender)
        }
        
        // Then start new sender (only if it's not already sending)
        if deviceManager.currentSender?.peer != peer.peer {
            sendControlCommand(.startSending, to: peer)
        }
        
        print("[Controller] Switching input to \(peer.displayName)")
    }
    
    // MARK: - Control Commands
    
    private func sendControlCommand(_ command: ControlCommand, to peer: Peer) {
        guard peer.state == .connected else {
            print("[Controller] Cannot send command to \(peer.displayName) - not connected")
            return
        }
        
        guard networking.connectedPeers.contains(peer.peer) else {
            print("[Controller] Cannot send command to \(peer.displayName) - not in session")
            return
        }
        
        let message = ControlMessage(
            command: command,
            targetPeerId: peer.peer.displayName,
            sourceInfo: deviceManager.createCurrentDeviceInfo(isCurrentlySending: false)
        )
        
        do {
            try networking.sendControlCommand(message, to: peer.peer)
            print("[Controller] Sent command \(command) to \(peer.displayName)")
        } catch {
            print("[Controller] Failed to send command \(command) to \(peer.displayName): \(error)")
        }
    }
    
    func handleControlMessage(_ message: ControlMessage, from peerID: MCPeerID, onStartSending: @escaping () -> Void, onStopSending: @escaping () -> Void) {
        print("[Controller] Received command \(message.command) from \(peerID.displayName)")
        
        switch message.command {
        case .startSending:
            if message.targetPeerId == peerID.displayName || message.targetPeerId == nil {
                // Add a small delay to allow connection to stabilize
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onStartSending()
                }
            }
        case .stopSending:
            if message.targetPeerId == peerID.displayName || message.targetPeerId == nil {
                onStopSending()
            }
        case .switchToSender:
            if message.targetPeerId == peerID.displayName {
                // Add a small delay to allow connection to stabilize
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onStartSending()
                }
            } else {
                onStopSending()
            }
        }
    }
}
