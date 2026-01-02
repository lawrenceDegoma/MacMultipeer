import SwiftUI
import AVKit

struct AirPlayStreamingView: NSViewRepresentable {
    let airPlayManager: AirPlayManager
    
    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        
        // Create route picker view for AirPlay device selection
        let routePickerView = AVRoutePickerView()
        routePickerView.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(routePickerView)
        
        NSLayoutConstraint.activate([
            routePickerView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            routePickerView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            routePickerView.widthAnchor.constraint(equalToConstant: 44),
            routePickerView.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        return containerView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Update view if needed
    }
}

struct AirPlayControlPanel: View {
    @ObservedObject var airPlayManager: AirPlayManager
    @State private var showStreamingView = false
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("AirPlay Streaming")
                    .font(.headline)
                
                Spacer()
                
                // AirPlay Route Picker
                AirPlayStreamingView(airPlayManager: airPlayManager)
                    .frame(width: 44, height: 44)
            }
            
            if airPlayManager.isStreaming {
                HStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    
                    Text("Streaming to AirPlay device")
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("Stop Streaming") {
                        airPlayManager.stopStreaming()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Discovered AirPlay devices list
            if !airPlayManager.availableDevices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available AirPlay Devices (\(airPlayManager.availableDevices.count))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ForEach(airPlayManager.availableDevices) { device in
                        HStack {
                            Image(systemName: deviceIcon(for: device))
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
                            
                            if airPlayManager.selectedDevice?.id == device.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.vertical, 4)
                        .onTapGesture {
                            airPlayManager.selectDevice(device)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
    }
    
    private func deviceIcon(for device: AirPlayManager.AirPlayDevice) -> String {
        if device.isAppleTV {
            return "appletv"
        } else if device.deviceType.contains("Roku") {
            return "tv"
        } else if device.deviceType.contains("Mac") {
            return "desktopcomputer"
        } else {
            return "airplayvideo"
        }
    }
}

struct AirPlayStreamingView_Previews: PreviewProvider {
    static var previews: some View {
        AirPlayControlPanel(airPlayManager: AirPlayManager())
    }
}
