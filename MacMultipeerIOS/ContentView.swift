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
                
            // Receiver View Tab
            receiverView
                .tabItem {
                    Image(systemName: "tv")
                    Text("Receiver")
                }
        }
        .onAppear {
            print("App bundle path:", Bundle.main.bundleURL.path)
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
    
    private var receiverView: some View {
        NavigationStack {
            VStack(spacing: 12) {
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

                if let img = manager.lastImage as? UIImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .border(Color.primary.opacity(0.2))
                } else {
                    Text("Waiting for frames...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .border(Color.primary.opacity(0.2))
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Screen Mirror")
        }
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
