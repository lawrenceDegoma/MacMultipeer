import SwiftUI
import MultipeerConnectivity

struct StreamDeckControlView: View {
    @ObservedObject var manager: MultipeerManager
    
    private let buttonSize: CGFloat = 100
    private let buttonSpacing: CGFloat = 12
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
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
                
                // Controller Toggle
                HStack {
                    Button(manager.isController ? "Controller Mode ✅" : "Enable Controller") {
                        manager.enableControllerMode()
                    }
                    .disabled(manager.isController)
                    Spacer()
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
                    Text("Connected: \(manager.peers.filter { $0.state == .connected }.count)")
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
            }
            .padding()
            .navigationTitle("🎮 Stream Deck")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var availableInputSources: [Peer] {
        // Get connected peers
        var sources = manager.peers.filter { peer in
            peer.state == .connected
        }
        
        // Add self as a source if capable
        let mySelf = Peer(peer: manager.myPeerID)
        mySelf.deviceInfo = DeviceInfo(
            peerId: manager.myPeerID.displayName,
            deviceType: UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone,
            capabilities: [.canSendScreen, .canReceiveScreen, .canControlInputs],
            isCurrentlySending: false // iOS screen sharing not implemented yet
        )
        mySelf.state = .connected
        sources.append(mySelf)
        
        return sources
    }
    
    @ViewBuilder
    private func deviceButton(for peer: Peer) -> some View {
        Button(action: {
            if manager.isController {
                manager.switchInputToDevice(peer)
            }
        }) {
            VStack(spacing: 6) {
                // Device Icon
                deviceIcon(for: peer.deviceInfo?.deviceType ?? .iPhone)
                    .font(.system(size: 32))
                
                // Device Name
                Text(peer.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                // Status Indicator
                HStack(spacing: 2) {
                    Circle()
                        .fill(statusColor(for: peer))
                        .frame(width: 4, height: 4)
                    
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
            return Text("📱")
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
            return false // iOS screen sharing not implemented yet
        }
        return manager.currentSender?.peer.displayName == peer.peer.displayName
    }
}

struct StreamDeckControlView_Previews: PreviewProvider {
    static var previews: some View {
        StreamDeckControlView(manager: MultipeerManager())
    }
}
