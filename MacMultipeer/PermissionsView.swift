import SwiftUI
import AVFoundation
import ScreenCaptureKit
import AppKit
import Combine

@available(macOS 12.3, *)
class ScreenRecordingPermissions: NSObject, ObservableObject {
    @Published var hasScreenRecordingPermission = false
    @Published var hasMicrophonePermission = false
    @Published var permissionCheckInProgress = false
    
    override init() {
        super.init()
        checkPermissions()
    }
    
    func checkPermissions() {
        permissionCheckInProgress = true
        
        // Check microphone permission
        checkMicrophonePermission()
        
        // Check screen recording permission
        checkScreenRecordingPermission()
    }
    
    // Force the app to appear in System Preferences by actually using the APIs
    func triggerSystemRecognition() {
        Task { @MainActor in
            // This ensures the app appears in System Preferences
            do {
                // Attempt to get screen content (will fail if no permission but registers the app)
                let _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            } catch {
                print("[Permissions] App is now registered for screen recording permissions")
            }
            
            // Also trigger microphone registration
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                print("[Permissions] App is now registered for microphone permissions")
            }
            
            checkPermissions()
        }
    }
    
    private func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            DispatchQueue.main.async {
                self.hasMicrophonePermission = true
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.hasMicrophonePermission = granted
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.hasMicrophonePermission = false
            }
        @unknown default:
            DispatchQueue.main.async {
                self.hasMicrophonePermission = false
            }
        }
    }
    
    private func checkScreenRecordingPermission() {
        Task { @MainActor in
            let canRecord = await canRecordScreen()
            self.hasScreenRecordingPermission = canRecord
            self.permissionCheckInProgress = false
        }
    }
    
    private func canRecordScreen() async -> Bool {
        do {
            // Try to get available content - this will prompt for permission if needed
            let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return !availableContent.displays.isEmpty
        } catch {
            print("[Permissions] Screen recording permission check failed: \(error)")
            return false
        }
    }
    
    func requestScreenRecordingPermission() {
        Task { @MainActor in
            do {
                // This will trigger the permission dialog if not already granted
                // and add the app to System Preferences -> Privacy & Security -> Screen Recording
                let _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                checkScreenRecordingPermission()
            } catch {
                print("[Permissions] Failed to request screen recording permission: \(error)")
                // Even if this fails, the app should now appear in System Preferences
                // Set a small delay and check again
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                    self.hasScreenRecordingPermission = false
                    self.permissionCheckInProgress = false
                }
            }
        }
    }
    
    func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                self.hasMicrophonePermission = granted
            }
        }
    }
    
    func openSystemPreferences() {
        // Open Screen Recording preferences
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func openMicrophonePreferences() {
        // Open Microphone preferences  
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}

// Legacy support for older macOS versions
class LegacyScreenRecordingPermissions: NSObject, ObservableObject {
    @Published var hasScreenRecordingPermission = false
    @Published var hasMicrophonePermission = false
    @Published var permissionCheckInProgress = false
    
    override init() {
        super.init()
        checkPermissions()
    }
    
    func checkPermissions() {
        permissionCheckInProgress = true
        
        // Check microphone permission
        checkMicrophonePermission()
        
        // For legacy systems, assume screen recording is available
        // (older macOS versions don't have the same permission model)
        DispatchQueue.main.async {
            self.hasScreenRecordingPermission = true
            self.permissionCheckInProgress = false
        }
    }
    
    private func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            DispatchQueue.main.async {
                self.hasMicrophonePermission = true
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.hasMicrophonePermission = granted
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.hasMicrophonePermission = false
            }
        @unknown default:
            DispatchQueue.main.async {
                self.hasMicrophonePermission = false
            }
        }
    }
    
    func requestScreenRecordingPermission() {
        // For legacy systems, redirect to system preferences
        openSystemPreferences()
    }
    
    func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                self.hasMicrophonePermission = granted
            }
        }
    }
    
    func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func openMicrophonePreferences() {
        openSystemPreferences()
    }
}

struct PermissionsView: View {
    @State private var modernPermissions: ScreenRecordingPermissions?
    @StateObject private var legacyPermissions = LegacyScreenRecordingPermissions()
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    init() {
        if #available(macOS 12.3, *) {
            _modernPermissions = State(initialValue: ScreenRecordingPermissions())
        } else {
            _modernPermissions = State(initialValue: nil)
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Permissions Required")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("MacMultipeer needs permission to capture your screen and system audio for sharing.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            VStack(spacing: 16) {
                PermissionRow(
                    title: "Screen Recording",
                    description: "Required to capture and share your screen",
                    icon: "display",
                    isGranted: screenRecordingPermission,
                    action: requestScreenRecording
                )
                
                PermissionRow(
                    title: "Microphone",
                    description: "Required to capture system audio during screen sharing",
                    icon: "mic",
                    isGranted: microphonePermission,
                    action: requestMicrophone
                )
            }
            
            if !allPermissionsGranted {
                VStack(spacing: 12) {
                    Button("Request All Permissions") {
                        requestAllPermissions()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Open System Preferences") {
                        openSystemPreferences()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Register App for Permissions") {
                        registerAppForPermissions()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.orange)
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("All permissions granted!")
                        .fontWeight(.medium)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
            
            if permissionCheckInProgress {
                ProgressView("Checking permissions...")
                    .padding()
            }
        }
        .padding(24)
        .frame(maxWidth: 400)
        .onAppear {
            // Automatically trigger app registration when view appears
            if #available(macOS 12.3, *), let modern = modernPermissions {
                modern.triggerSystemRecognition()
            }
        }
        .alert("Permission Required", isPresented: $showingAlert) {
            Button("Open System Preferences") {
                openSystemPreferences()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
    
    // MARK: - Permission Properties
    
    private var screenRecordingPermission: Bool {
        if #available(macOS 12.3, *), let modern = modernPermissions {
            return modern.hasScreenRecordingPermission
        } else {
            return legacyPermissions.hasScreenRecordingPermission
        }
    }
    
    private var microphonePermission: Bool {
        if #available(macOS 12.3, *), let modern = modernPermissions {
            return modern.hasMicrophonePermission
        } else {
            return legacyPermissions.hasMicrophonePermission
        }
    }
    
    private var permissionCheckInProgress: Bool {
        if #available(macOS 12.3, *), let modern = modernPermissions {
            return modern.permissionCheckInProgress
        } else {
            return legacyPermissions.permissionCheckInProgress
        }
    }
    
    private var allPermissionsGranted: Bool {
        return screenRecordingPermission && microphonePermission
    }
    
    // MARK: - Actions
    
    private func requestScreenRecording() {
        if #available(macOS 12.3, *), let modern = modernPermissions {
            modern.requestScreenRecordingPermission()
        } else {
            alertMessage = "Please go to System Preferences → Security & Privacy → Privacy → Screen Recording and enable MacMultipeer."
            showingAlert = true
        }
    }
    
    private func requestMicrophone() {
        if #available(macOS 12.3, *), let modern = modernPermissions {
            modern.requestMicrophonePermission()
        } else {
            legacyPermissions.requestMicrophonePermission()
        }
    }
    
    private func requestAllPermissions() {
        requestScreenRecording()
        requestMicrophone()
    }
    
    private func registerAppForPermissions() {
        if #available(macOS 12.3, *), let modern = modernPermissions {
            modern.triggerSystemRecognition()
        } else {
            legacyPermissions.requestMicrophonePermission()
            alertMessage = "Please go to System Preferences → Security & Privacy → Privacy → Screen Recording and manually add MacMultipeer."
            showingAlert = true
        }
    }
    
    private func openSystemPreferences() {
        if #available(macOS 12.3, *), let modern = modernPermissions {
            modern.openSystemPreferences()
        } else {
            legacyPermissions.openSystemPreferences()
        }
    }
}

struct PermissionRow: View {
    let title: String
    let description: String
    let icon: String
    let isGranted: Bool
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(isGranted ? .green : .orange)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("Grant") {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
    }
}

#Preview {
    PermissionsView()
}
