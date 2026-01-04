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
    
    // Force fresh permission check by clearing cache
    func forcePermissionCheck() {
        // Clear all cached permission states
        UserDefaults.standard.removeObject(forKey: "lastKnownScreenPermission")
        UserDefaults.standard.removeObject(forKey: "lastPermissionCheck")
        UserDefaults.standard.removeObject(forKey: "lastKnownMicPermission")
        UserDefaults.standard.removeObject(forKey: "lastMicPermissionCheck")
        
        print("[Permissions] 🔄 Forcing fresh permission check - clearing cache")
        checkPermissions()
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
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch authStatus {
        case .authorized:
            DispatchQueue.main.async {
                self.hasMicrophonePermission = true
                UserDefaults.standard.set(true, forKey: "lastKnownMicPermission")
                UserDefaults.standard.set(Date(), forKey: "lastMicPermissionCheck")
            }
        case .notDetermined:
            // Only request if we don't have a recent check
            if let lastCheck = UserDefaults.standard.object(forKey: "lastMicPermissionCheck") as? Date,
               Date().timeIntervalSince(lastCheck) < 300 { // 5 minutes grace period
                print("[Permissions] Skipping mic permission request - recent check")
                let cached = UserDefaults.standard.bool(forKey: "lastKnownMicPermission")
                DispatchQueue.main.async {
                    self.hasMicrophonePermission = cached
                }
                return
            }
            
            print("[Permissions] Requesting microphone permission")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.hasMicrophonePermission = granted
                    UserDefaults.standard.set(granted, forKey: "lastKnownMicPermission")
                    UserDefaults.standard.set(Date(), forKey: "lastMicPermissionCheck")
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.hasMicrophonePermission = false
                UserDefaults.standard.set(false, forKey: "lastKnownMicPermission")
                UserDefaults.standard.set(Date(), forKey: "lastMicPermissionCheck")
            }
        @unknown default:
            DispatchQueue.main.async {
                self.hasMicrophonePermission = false
            }
        }
    }
    
    private func checkScreenRecordingPermission() {
        Task { @MainActor in
            // Add a small delay to ensure any previous permission requests have settled
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            let canRecord = await canRecordScreen()
            self.hasScreenRecordingPermission = canRecord
            self.permissionCheckInProgress = false
            
            // Log the current permission status for debugging
            print("[Permissions] Screen recording permission: \(canRecord ? "✅ Granted" : "❌ Denied")")
        }
    }
    
    private func canRecordScreen() async -> Bool {
        // First, check if we have any cached permission state to avoid repeated prompts
        if let cachedPermission = UserDefaults.standard.object(forKey: "lastKnownScreenPermission") as? Bool,
           let lastCheck = UserDefaults.standard.object(forKey: "lastPermissionCheck") as? Date,
           Date().timeIntervalSince(lastCheck) < 300 { // 5 minutes grace period
            print("[Permissions] Using cached screen recording permission: \(cachedPermission ? "✅ Granted" : "❌ Denied")")
            return cachedPermission
        }
        
        do {
            // Try to get available content - this should NOT prompt if permission was already granted
            let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let hasDisplays = !availableContent.displays.isEmpty
            print("[Permissions] Found \(availableContent.displays.count) displays available")
            
            // Cache the successful result
            UserDefaults.standard.set(true, forKey: "lastKnownScreenPermission")
            UserDefaults.standard.set(Date(), forKey: "lastPermissionCheck")
            
            // Additional validation to ensure CMIO system is stable
            if hasDisplays {
                // Test CMIO stability by checking if we can access display properties
                for display in availableContent.displays {
                    print("[Permissions] Display \(display.displayID) - \(Int(display.width))x\(Int(display.height))")
                }
            }
            
            return hasDisplays
        } catch {
            print("[Permissions] Screen recording permission check failed: \(error)")
            
            // Check if this is a specific permission error
            let nsError = error as NSError
            switch nsError.code {
            case -3801: // Screen recording permission denied
                print("[Permissions] Screen recording explicitly denied")
                UserDefaults.standard.set(false, forKey: "lastKnownScreenPermission")
                UserDefaults.standard.set(Date(), forKey: "lastPermissionCheck")
                return false
            case -3802: // Screen recording permission not determined
                print("[Permissions] Screen recording permission not determined")
                UserDefaults.standard.set(false, forKey: "lastKnownScreenPermission")
                UserDefaults.standard.set(Date(), forKey: "lastPermissionCheck")
                return false
            default:
                print("[Permissions] Unknown screen capture error: \(nsError)")
                // For unknown errors, don't cache the result and be more lenient
                if nsError.domain.contains("CMIO") {
                    print("[Permissions] ⚠️ CMIO system error detected - assuming permission granted")
                    // Don't cache CMIO errors as they may be temporary
                    return true
                }
                return false
            }
        }
    }
    
    func requestScreenRecordingPermission() {
        Task { @MainActor in
            // Clear cached permission state to force fresh check
            UserDefaults.standard.removeObject(forKey: "lastKnownScreenPermission")
            UserDefaults.standard.removeObject(forKey: "lastPermissionCheck")
            
            do {
                // This will trigger the permission dialog if not already granted
                // and add the app to System Preferences -> Privacy & Security -> Screen Recording
                let _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                checkScreenRecordingPermission()
            } catch {
                print("[Permissions] Failed to request screen recording permission: \(error)")
                
                // Check if this might be a CMIO system issue
                let nsError = error as NSError
                if nsError.domain.contains("CMIO") || nsError.code == -7 {
                    print("[Permissions] 🔧 CMIO system issue detected - restarting permission check")
                    // Give CMIO system time to stabilize and try again
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                        print("[Permissions] 🔄 Retrying permission check after CMIO stabilization")
                        self.checkScreenRecordingPermission()
                    }
                } else {
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
    }
    
    func requestMicrophonePermission() {
        // Clear cached permission state to force fresh check
        UserDefaults.standard.removeObject(forKey: "lastKnownMicPermission")
        UserDefaults.standard.removeObject(forKey: "lastMicPermissionCheck")
        
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                self.hasMicrophonePermission = granted
                UserDefaults.standard.set(granted, forKey: "lastKnownMicPermission")
                UserDefaults.standard.set(Date(), forKey: "lastMicPermissionCheck")
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
                    
                    // Debug: Force refresh permissions
                    Button("Refresh Permission Status") {
                        forceRefreshPermissions()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.blue)
                    .help("Force check permission status if app shows wrong state")
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
    
    private func forceRefreshPermissions() {
        print("[PermissionsView] 🔄 Force refreshing all permission states")
        if #available(macOS 12.3, *), let modern = modernPermissions {
            modern.forcePermissionCheck()
        } else {
            legacyPermissions.checkPermissions()
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
