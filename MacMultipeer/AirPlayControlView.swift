import SwiftUI

struct AirPlayControlView: View {
    @ObservedObject var airPlayManager: AirPlayManager
    @State private var showingDeviceDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AirPlay Output")
                    .font(.headline)
                
                Spacer()
                
                // Discovery indicator
                if airPlayManager.isDiscovering {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Discovering...")
                            .font(.caption)
                    }
                }
                
                Button(action: {
                    if airPlayManager.isDiscovering {
                        airPlayManager.stopDiscovery()
                    } else {
                        airPlayManager.startDiscovery()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help(airPlayManager.isDiscovering ? "Stop Discovery" : "Refresh Devices")
                
                Circle()
                    .fill(airPlayManager.isStreaming ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                
                Text(airPlayManager.isStreaming ? "Streaming" : "Ready")
                    .font(.caption)
                    .foregroundColor(airPlayManager.isStreaming ? .green : .gray)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Available AirPlay Devices:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(airPlayManager.availableDevices.count) found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if airPlayManager.availableDevices.isEmpty {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text(airPlayManager.isDiscovering ? "Searching for AirPlay devices..." : "No AirPlay devices found")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                        
                        if !airPlayManager.isDiscovering {
                            Text("Make sure your AirPlay devices are on the same network")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(airPlayManager.availableDevices, id: \.id) { device in
                            Button(action: {
                                airPlayManager.selectDevice(device)
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: device.isAppleTV ? "appletv.fill" : "tv")
                                        .foregroundColor(device.isAppleTV ? .black : .gray)
                                        .frame(width: 20)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.name)
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                        
                                        HStack {
                                            if let hostName = device.hostName {
                                                Text(hostName)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            
                                            Text(":\(device.port)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        if !device.deviceInfo.isEmpty {
                                            Text(device.deviceInfo)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(spacing: 4) {
                                        Image(systemName: airPlayManager.selectedDevice?.id == device.id ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(airPlayManager.selectedDevice?.id == device.id ? .blue : .gray)
                                        
                                        if device.isAppleTV {
                                            Text("Apple TV")
                                                .font(.caption2)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(airPlayManager.selectedDevice?.id == device.id ? Color.blue.opacity(0.1) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(airPlayManager.selectedDevice?.id == device.id ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                            )
                        }
                    }
                }
            }
            
            // Control buttons
            HStack {
                Button(action: {
                    if airPlayManager.isStreaming {
                        airPlayManager.stopStreaming()
                    } else {
                        print("[AirPlay] Ready - waiting for input selection")
                    }
                }) {
                    HStack {
                        Image(systemName: airPlayManager.isStreaming ? "stop.circle.fill" : "airplayvideo")
                        Text(airPlayManager.isStreaming ? "Stop AirPlay" : "Ready to Stream")
                    }
                    .foregroundColor(airPlayManager.isStreaming ? .red : .blue)
                }
                .disabled(airPlayManager.selectedDevice == nil)
                .buttonStyle(.bordered)
                
                Spacer()
                
                if let selectedDevice = airPlayManager.selectedDevice {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("→ \(selectedDevice.name)")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        if !selectedDevice.deviceInfo.isEmpty {
                            Text(selectedDevice.deviceInfo)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
    }
}