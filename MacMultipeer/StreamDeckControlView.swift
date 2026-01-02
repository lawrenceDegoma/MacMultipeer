import SwiftUI
import MultipeerConnectivity
import AVKit

struct StreamDeckControlView: View {
    @ObservedObject var manager: MultipeerManager
    
    private let buttonSize: CGFloat = 120
    private let buttonSpacing: CGFloat = 16
    
    var body: some View {
        VStack(spacing: 20) {
            // Apple TV Control Section
            AirPlayControlPanel(airPlayManager: manager.airPlayManager)
            
            // Header
            HStack {
                Text("Stream Control Deck")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(manager.isController ? "Controller Mode ✅" : "Enable Controller") {
                    manager.enableControllerMode()
                }
                .disabled(manager.isController)
            }
            
            // Current Status
            if let currentSender = manager.currentSender {
                HStack {
                    Text("🔴 LIVE:")
                        .foregroundColor(.red)
                        .fontWeight(.bold)
                    Text(currentSender.displayName)
                    if let deviceInfo = currentSender.deviceInfo {
                        Text("(\(deviceInfo.deviceType.rawValue))")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Device Grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: buttonSpacing), count: 3), spacing: buttonSpacing) {
                ForEach(availableInputSources, id: \.id) { peer in
                    deviceButton(for: peer)
                }
            }
            
            Spacer()
            
            // Connection Status
            HStack {
                Text("Connected Devices: \(manager.peers.filter { $0.state == .connected }.count)")
                Spacer()
                if manager.isAdvertising {
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Discoverable")
                    }
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            // Debug Info
            if manager.isController {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Debug Info:")
                        .font(.caption2)
                        .fontWeight(.bold)
                    Text("Session connected peers: \(manager.sessionForDebug.connectedPeers.map { $0.displayName }.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Managed peers: \(manager.peers.map { "\($0.displayName)(\($0.state.rawValue))" }.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)
            }
        }
        .padding()
    }
    
    private var availableInputSources: [Peer] {
        // Get connected peers that can send screen
        var sources = manager.peers.filter { peer in
            peer.state == .connected
        }
        
        // Add self as a source if capable
        let mySelf = Peer(peer: manager.myPeerID)
        mySelf.deviceInfo = DeviceInfo(
            peerId: manager.myPeerID.displayName,
            deviceType: .mac,
            capabilities: [.canSendScreen, .canReceiveScreen, .canControlInputs],
            isCurrentlySending: manager.captureSender != nil
        )
        mySelf.state = .connected
        sources.append(mySelf)
        
        print("[UI] Available sources: \(sources.map { "\($0.displayName)(\($0.deviceInfo?.deviceType.rawValue ?? "unknown"))" })")
        
        return sources
    }
    
    @ViewBuilder
    private func deviceButton(for peer: Peer) -> some View {
        Button(action: {
            if manager.isController {
                print("[UI] Attempting to switch to \(peer.displayName), state: \(peer.state.rawValue), connected peers: \(manager.sessionForDebug.connectedPeers.map { $0.displayName })")
                manager.switchInputToDevice(peer)
            }
        }) {
            VStack(spacing: 8) {
                // Device Icon
                deviceIcon(for: peer.deviceInfo?.deviceType ?? .mac)
                    .font(.system(size: 40))
                
                // Device Name
                Text(peer.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                // Status Indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor(for: peer))
                        .frame(width: 6, height: 6)
                    
                    Text(statusText(for: peer))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: buttonSize, height: buttonSize)
        .background(backgroundColorForDevice(peer))
        .foregroundColor(.primary)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor(for: peer), lineWidth: isCurrentSender(peer) ? 3 : 1)
        )
        .disabled(!manager.isController || peer.state != .connected)
        .scaleEffect(isCurrentSender(peer) ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isCurrentSender(peer))
    }
    
    private func deviceIcon(for deviceType: DeviceType) -> Text {
        switch deviceType {
        case .mac:
            return Text("💻")
        case .iPhone:
            return Text("📱")
        case .iPad:
            return Text("📱") // You could use a different icon for iPad
        }
    }
    
    private func backgroundColorForDevice(_ peer: Peer) -> Color {
        if isCurrentSender(peer) {
            return Color.red.opacity(0.2)
        } else if peer.state == .connected {
            return Color.blue.opacity(0.1)
        } else {
            return Color.gray.opacity(0.1)
        }
    }
    
    private func borderColor(for peer: Peer) -> Color {
        if isCurrentSender(peer) {
            return Color.red
        } else if peer.state == .connected {
            return Color.blue.opacity(0.5)
        } else {
            return Color.gray.opacity(0.3)
        }
    }
    
    private func statusColor(for peer: Peer) -> Color {
        if isCurrentSender(peer) {
            return .red
        } else if peer.state == .connected {
            return .green
        } else {
            return .gray
        }
    }
    
    private func statusText(for peer: Peer) -> String {
        if isCurrentSender(peer) {
            return "LIVE"
        } else if peer.state == .connected {
            return "Ready"
        } else {
            return "Offline"
        }
    }
    
    private func isCurrentSender(_ peer: Peer) -> Bool {
        if peer.peer.displayName == manager.myPeerID.displayName {
            return manager.captureSender != nil
        }
        return manager.currentSender?.peer.displayName == peer.peer.displayName
    }
}

struct StreamDeckControlView_Previews: PreviewProvider {
    static var previews: some View {
        StreamDeckControlView(manager: MultipeerManager())
    }
}
