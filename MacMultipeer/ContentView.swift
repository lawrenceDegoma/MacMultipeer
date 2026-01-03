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
            
            // AirPlay Tab
            airPlayView
                .tabItem {
                    Image(systemName: "airplayvideo")
                    Text("AirPlay")
                }
                .tag(1)
            
            // Permissions Tab
            PermissionsView()
                .tabItem {
                    Image(systemName: "lock.shield")
                    Text("Permissions")
                }
                .tag(2)
            
            // Technical View Tab
            technicalView
                .tabItem {
                    Image(systemName: "gear")
                    Text("Technical")
                }
                .tag(3)
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
                
                Button("🧪 Send Test Message") {
                    manager.sendTestMessage()
                }
                .foregroundColor(.purple)
                
                Button("🧹 Clean Up Peers") {
                    manager.cleanupPeers()
                }
                .foregroundColor(.red)
            }

            VStack(alignment: .leading) {
                Text("Discovered Peers")
                    .font(.headline)
                List(manager.peers, id: \.id) { peer in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            // Device type indicator
                            if let deviceInfo = peer.deviceInfo {
                                let icon = {
                                    switch deviceInfo.deviceType.rawValue {
                                    case "mac": return "💻"
                                    case "iphone": return "📱"  
                                    case "ipad": return "📱"
                                    default: return "❓"
                                    }
                                }()
                                Text(icon)
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
                .frame(width: 600, height: 300)
            }

            Spacer()
        }
        .padding()
    }
    
    private var airPlayView: some View {
        VStack(spacing: 16) {
            Text("AirPlay Streaming")
                .font(.title)
                .padding(.top)
                
            VStack(spacing: 12) {
                HStack {
                    Text("Apple TV Discovery")
                        .font(.headline)
                    
                    Spacer()
                    
                    if manager.airPlayManager.isDiscovering {
                        Button("Stop Discovery") {
                            manager.airPlayManager.stopDiscovery()
                        }
                    } else {
                        Button("Start Discovery") {
                            manager.airPlayManager.startDiscovery()
                        }
                    }
                }
                
                if manager.airPlayManager.isStreaming {
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        
                        Text("Streaming to Apple TV")
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("Stop Streaming") {
                            manager.airPlayManager.stopStreaming()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // Screen Capture + AirPlay Controls
                HStack(spacing: 12) {
                    if manager.captureSender == nil {
                        Button("Start Screen Sharing to AirPlay") {
                            manager.startSending()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Stop Screen Sharing") {
                            manager.stopSending()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                // Available Apple TVs
                if !manager.airPlayManager.availableDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Available Apple TV Devices (\(manager.airPlayManager.availableDevices.count))")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        ForEach(manager.airPlayManager.availableDevices) { device in
                            HStack {
                                Image(systemName: device.isAppleTV ? "appletv" : "airplayvideo")
                                    .foregroundColor(.blue)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    
                                    Text(device.deviceType)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if manager.airPlayManager.selectedDevice?.id == device.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.vertical, 4)
                            .onTapGesture {
                                manager.airPlayManager.selectDevice(device)
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                } else if manager.airPlayManager.isDiscovering {
                    Text("Searching for Apple TV devices...")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    Text("Click 'Start Discovery' to find Apple TV devices")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            
            Spacer()
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
