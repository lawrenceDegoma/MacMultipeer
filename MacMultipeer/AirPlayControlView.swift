import SwiftUI

struct AirPlayControlView: View {
    @ObservedObject var airPlayManager: AirPlayManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("📺 Apple TV Output")
                    .font(.headline)
                
                Spacer()
                
                Circle()
                    .fill(airPlayManager.isStreaming ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                
                Text(airPlayManager.isStreaming ? "Streaming" : "Not Streaming")
                    .font(.caption)
                    .foregroundColor(airPlayManager.isStreaming ? .green : .gray)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Available Apple TVs:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if airPlayManager.availableDevices.isEmpty {
                    Text("Discovering devices...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(airPlayManager.availableDevices, id: \.id) { device in
                        HStack {
                            Button(action: {
                                airPlayManager.selectDevice(device)
                            }) {
                                HStack {
                                    Image(systemName: airPlayManager.selectedDevice?.id == device.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(airPlayManager.selectedDevice?.id == device.id ? .blue : .gray)
                                    
                                    Text(device.name)
                                        .font(.body)
                                    
                                    Spacer()
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(airPlayManager.selectedDevice?.id == device.id ? Color.blue.opacity(0.1) : Color.clear)
                        )
                    }
                }
            }
            
            HStack {
                Button(action: {
                    if airPlayManager.isStreaming {
                        airPlayManager.stopStreaming()
                    } else {
                        // This would be triggered when a device starts sending
                        print("AirPlay ready - waiting for input selection")
                    }
                }) {
                    HStack {
                        Image(systemName: airPlayManager.isStreaming ? "stop.circle" : "airplayvideo")
                        Text(airPlayManager.isStreaming ? "Stop AirPlay" : "Ready to AirPlay")
                    }
                }
                .disabled(airPlayManager.selectedDevice == nil)
                
                Spacer()
                
                if let selectedDevice = airPlayManager.selectedDevice {
                    Text("→ \(selectedDevice.name)")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
    }
}
