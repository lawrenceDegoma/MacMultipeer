# MacMultipeer Setup Instructions

This project contains personal identifiers that need to be configured before building.

## Required Configuration

### 1. Development Team ID
Open `MacMultipeer.xcodeproj/project.pbxproj` and replace all instances of:
```
DEVELOPMENT_TEAM = YOUR_DEVELOPMENT_TEAM;
```
with your Apple Developer Team ID (found in your Apple Developer account).

### 2. Bundle Identifier
The project currently uses `com.yourcompany.MacMultipeer`. You should:
1. Replace `com.yourcompany.MacMultipeer` with your own bundle identifier
2. Make sure it's unique and follows reverse domain name notation
3. Example: `com.yourname.MacMultipeer` or `com.yourcompany.MacMultipeer`

### 3. Code Signing
Make sure you have:
- A valid Apple Developer account
- Appropriate certificates installed in Keychain Access
- Your device(s) added to your provisioning profiles

## Quick Setup
1. Open the project in Xcode
2. Select the project root in the navigator
3. Under "Signing & Capabilities":
   - Select your development team
   - Update the bundle identifier if needed
   - Xcode will automatically manage provisioning profiles

## Project Structure
- **MacMultipeer/**: macOS application
- **MacMultipeerIOS/**: iOS companion app
- **Shared**: Code shared between platforms

## Features
- MultipeerConnectivity for device discovery and communication
- AirPlay discovery and streaming capabilities
- Cross-platform screen sharing and control
- Stream Deck-style control interface

## Building
1. Complete the setup steps above
2. Select your target device or simulator
3. Build and run (⌘+R)
