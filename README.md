# MacMultipeer - StreamDeck-like Screen Mirroring Control

A seamless multi-device screen mirroring solution that works like a StreamDeck, allowing you to control input sources across your laptop, iPhone, and iPad from a centralized interface.

## Features

### 🎮 StreamDeck-like Control Interface
- **Central Control Panel**: One device can act as a controller to manage all input sources
- **One-Click Input Switching**: Seamlessly switch between devices without manual disconnection/reconnection
- **Visual Status Indicators**: See which device is currently sending and which are ready
- **Device Type Recognition**: Automatically identifies Macs, iPhones, and iPads

### 🔄 Seamless Input Switching
- **Automatic Source Management**: When switching to a new input, the previous source automatically stops
- **Real-time Status Updates**: All connected devices see live updates of who's currently streaming
- **No Manual Disconnection**: Switch inputs without having to manually stop/start on each device

### 📱 Multi-Platform Support
- **macOS**: Full screen capture and streaming capabilities
- **iOS/iPadOS**: Receives streams and can act as controller (screen sharing coming soon)
- **Cross-platform Communication**: All devices can communicate regardless of platform

## How It Works

### Device Roles
1. **Controller**: Any device can enable "Controller Mode" to manage input switching
2. **Sender**: Devices that can capture and stream their screen (currently macOS)
3. **Receiver**: Devices that display the incoming stream (all platforms)

### StreamDeck-like Workflow
1. **Connect all devices** to the same network
2. **Enable discovery** on all devices (Advertising + Browsing)
3. **Connect devices** when they appear in the peer list
4. **Enable Controller Mode** on the device you want to use as the control center
5. **Switch inputs** by clicking device buttons in the Control Deck interface

### Control Commands
The system uses a sophisticated command protocol:
- `startSending`: Tell a device to begin screen capture
- `stopSending`: Tell a device to stop screen capture  
- `switchToSender`: Coordinated switching (stop current + start new)

## Interface Overview

### Control Deck Tab
- **Device Grid**: Visual buttons for each connected device
- **Live Status**: Shows which device is currently streaming
- **Controller Toggle**: Enable/disable controller mode
- **Connection Status**: See how many devices are connected

### Technical Tab
- **Peer Management**: Connect/disconnect from discovered devices
- **Device Information**: See device types and capabilities
- **Manual Controls**: Direct start/stop sending controls

### Receiver Tab (iOS)
- **Screen Display**: View the incoming screen stream
- **Source Information**: See which device is currently sending

## Getting Started

### Prerequisites
- All devices must be on the same local network
- macOS devices need screen recording permissions
- iOS devices need local network access permissions

### Setup Steps

1. **Launch the app** on all devices you want to include
2. **Start Advertising** on each device (makes them discoverable)
3. **Start Browsing** on each device (finds other devices)
4. **Connect devices** as they appear in the peer list
5. **Choose a controller device** and enable "Controller Mode"
6. **Start switching inputs** using the Control Deck interface!

### Permission Requirements

#### macOS
- **Screen Recording**: System Preferences → Security & Privacy → Screen Recording
- **Local Network**: Automatically requested

#### iOS/iPadOS
- **Local Network**: Settings → Privacy & Security → Local Network
- **Camera/Screen Recording**: (Future feature - not yet implemented)

## Technical Details

### Communication Protocol
- **Multipeer Connectivity**: Uses Apple's framework for device discovery and communication
- **Service Type**: "screenshare" for device discovery
- **Data Types**: 
  - Frame data (JPEG compressed screen captures)
  - Control commands (JSON)
  - Device info broadcasts (JSON with metadata)

### Device Capabilities
Each device advertises its capabilities:
- `canSendScreen`: Can capture and stream screen
- `canReceiveScreen`: Can display incoming streams
- `canControlInputs`: Can act as a controller

### Frame Quality
- **Compression**: JPEG with 60% quality for optimal size/quality balance
- **Frame Rate**: ~5 FPS (configurable in CaptureSender)
- **Resolution**: Full screen resolution, scaled to fit receiver

## Future Enhancements

### iOS Screen Sharing
- Implement screen capture for iOS devices using ReplayKit
- Add camera streaming as an input source
- Picture-in-picture support

### Advanced Controls
- Input source presets and scenes
- Transition effects between sources
- Audio routing and mixing
- Recording capabilities

### Network Optimization
- Adaptive quality based on network conditions
- H.264 hardware encoding
- UDP streaming for lower latency

## Troubleshooting

### Devices Not Appearing
1. Check that both devices are on the same network
2. Ensure both advertising and browsing are enabled
3. Check firewall settings aren't blocking connections
4. Restart the app and try again

### Poor Stream Quality
1. Move devices closer to reduce network latency
2. Close other network-intensive apps
3. Check Wi-Fi signal strength
4. Consider reducing frame rate in CaptureSender

### Control Commands Not Working
1. Verify the controller device shows "Controller Mode ✅"
2. Check that target devices are connected (not just discovered)
3. Look for error messages in the Technical tab
4. Try reconnecting the devices

## Architecture

The system is built with SwiftUI and uses a reactive architecture:
- **MultipeerManager**: Core networking and control logic
- **StreamDeckControlView**: Main control interface
- **CaptureSender**: Screen capture (macOS only)
- **Peer & DeviceInfo**: Data models for device management

This creates a professional, seamless experience similar to hardware StreamDecks used by content creators, but for personal device screen mirroring!
