import SwiftUI
import MultipeerConnectivity

struct ContentView: View {
    @StateObject private var manager = MultipeerManager()

    var body: some View {
        TabView {
            // StreamDeck Control Tab
            StreamDeckControlView(manager: manager)
                .tabItem {
                    Image(systemName: "rectangle.grid.3x2")
                    Text("Control Deck")
                }
            
            // Technical View Tab
            technicalView
                .tabItem {
                    Image(systemName: "gear")
                    Text("Technical")
                }
        }
        .onAppear {
            // Debug info for local network permissions
            let val = Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription") ?? "<missing>"
            print("NSLocalNetworkUsageDescription:", val)
            
            // Trigger local network permission request
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                manager.toggleAdvertising()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    manager.toggleBrowsing()
                }
            }
        }
    }
    
    private var technicalView: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("ScreenMirror — iOS")
                    .font(.title2)
                    .padding(.top)

                HStack(spacing: 12) {
                    Button(manager.isAdvertising ? "Stop Advertising" : "Start Advertising") {
                        manager.toggleAdvertising()
                    }
                    Button(manager.isBrowsing ? "Stop Browsing" : "Start Browsing") {
                        manager.toggleBrowsing()
                    }
                }
                
                // Reset button for debugging
                HStack {
                    Button("🔄 Reset Connections") {
                        manager.resetConnection()
                    }
                    .foregroundColor(.orange)
                    
                    Button("📤 Send Device Info") {
                        manager.sendDeviceInfo()
                    }
                    .foregroundColor(.blue)
                }
                
                // Connection Test Buttons
                if !manager.peers.filter({ $0.state == .connected }).isEmpty {
                    VStack(spacing: 8) {
                        Text("🧪 Connection Tests")
                            .font(.headline)
                            .foregroundColor(.blue)
                        
                        HStack(spacing: 8) {
                            Button("💬 Test Message") {
                                sendTestMessage()
                            }
                            .buttonStyle(.borderedProminent)
                            .font(.caption)
                            
                            Button("🎯 Test Control") {
                                sendTestControl()
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }

                List(manager.peers, id: \.id) { peer in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            // Device type indicator
                            if let deviceInfo = peer.deviceInfo {
                                Text(deviceIcon(for: deviceInfo.deviceType))
                                VStack(alignment: .leading) {
                                    Text(peer.displayName)
                                        .fontWeight(.medium)
                                    Text(deviceInfo.deviceType.rawValue)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text(peer.displayName)
                            }
                            
                            Spacer()
                            
                            // Connection status and actions
                            if peer.state == .connected {
                                VStack(alignment: .trailing, spacing: 2) {
                                    HStack {
                                        if peer.isCurrentlySending {
                                            Circle()
                                                .fill(Color.red)
                                                .frame(width: 8, height: 8)
                                            Text("Sending")
                                                .font(.caption2)
                                        }
                                        Text("Connected")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.green)
                                    
                                    if let capabilities = peer.deviceInfo?.capabilities {
                                        Text(capabilities.map { $0.rawValue }.joined(separator: ", "))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            } else {
                                Button("Connect") {
                                    manager.invite(peer: peer)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 300)

                Spacer()
            }
            .padding()
            .navigationTitle("Technical")
        }
    }
    
    
    // MARK: - Test Functions
    private func sendTestMessage() {
        let testData = "TEST_MESSAGE:Hello from iOS at \(Date())".data(using: .utf8)!
        let connectedPeers = manager.peers.filter { $0.state == MCSessionState.connected }
        
        guard !connectedPeers.isEmpty else {
            print("[Test] No connected peers to send test message to")
            return
        }
        
        // Use the manager's send method instead of accessing session directly
        manager.sendTestMessage(testData)
        print("[Test] ✅ Test message sent to \(connectedPeers.count) peers")
    }
    
    private func sendTestControl() {
        // Send a simple test control command via the manager
        let connectedPeers = manager.peers.filter { $0.state == MCSessionState.connected }
        guard !connectedPeers.isEmpty else {
            print("[Test] No connected peers to send test control to")
            return
        }
        
        manager.sendTestControl()
        print("[Test] ✅ Test control command sent to \(connectedPeers.count) peers")
    }
    
    private func deviceIcon(for deviceType: DeviceType) -> String {
        switch deviceType {
        case .mac: return "💻"
        case .iPhone: return "📱"
        case .iPad: return "📱"
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
