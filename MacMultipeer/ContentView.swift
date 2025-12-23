import SwiftUI
import MultipeerConnectivity

struct ContentView: View {
    @StateObject private var manager = MultipeerManager()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // StreamDeck Control Tab
            StreamDeckControlView(manager: manager)
                .tabItem {
                    Image(systemName: "rectangle.grid.3x2")
                    Text("Control Deck")
                }
                .tag(0)
            
            // Technical View Tab
            technicalView
                .tabItem {
                    Image(systemName: "gear")
                    Text("Technical")
                }
                .tag(1)
        }
        .frame(minWidth: 900, minHeight: 600)
    }
    
    private var technicalView: some View {
        VStack(spacing: 12) {
            Text("ScreenMirror — Multipeer")
                .font(.title)

            HStack(spacing: 10) {
                Button(manager.isAdvertising ? "Stop Advertising" : "Start Advertising") {
                    manager.toggleAdvertising()
                }
                Button(manager.isBrowsing ? "Stop Browsing" : "Start Browsing") {
                    manager.toggleBrowsing()
                }
                if manager.captureSender == nil {
                    Button("Start Sending") { manager.startSending() }
                } else {
                    Button("Stop Sending") { manager.stopSending() }
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

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Discovered Peers")
                        .font(.headline)
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
                    .frame(width: 400, height: 300)
                }

                VStack {
                    HStack {
                        Text("Receiver")
                            .font(.headline)
                        Spacer()
                        if let currentSender = manager.currentSender {
                            Text("Source: \(currentSender.displayName)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    if let img = manager.lastImage {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 480, height: 320)
                            .border(Color.black, width: 1)
                    } else {
                        Text("Waiting for frames...")
                            .frame(width: 480, height: 320)
                            .border(Color.black, width: 1)
                    }
                }
            }

            Spacer()
        }
        .padding()
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
