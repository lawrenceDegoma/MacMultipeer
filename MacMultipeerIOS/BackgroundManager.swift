//
//  BackgroundManager.swift
//  MacMultipeerIOS
//

import SwiftUI
import MultipeerConnectivity
import Combine

#if canImport(UIKit)
import UIKit
import BackgroundTasks
#endif

@MainActor
class BackgroundManager: ObservableObject {
    @Published var isInBackground = false
    
    #if canImport(UIKit)
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier?
    #endif
    
    init() {
        #if canImport(UIKit)
        registerBackgroundTasks()
        #endif
    }
    
    #if canImport(UIKit)
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.macmultipeer.refresh", using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }
    #endif
    
    func handleAppWillResignActive() {
        print("[Background] App will resign active")
        isInBackground = true
        #if canImport(UIKit)
        scheduleBackgroundRefresh()
        beginBackgroundTask()
        #endif
    }
    
    func handleAppDidBecomeActive() {
        print("[Background] App did become active")
        isInBackground = false
        #if canImport(UIKit)
        endBackgroundTask()
        #endif
    }
    
    #if canImport(UIKit)
    private func beginBackgroundTask() {
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "MultipeerConnection") {
            // Called when the system is about to terminate the background task
            print("[Background] Background task will expire")
            self.endBackgroundTask()
        }
        
        print("[Background] Started background task: \(backgroundTaskIdentifier?.rawValue ?? 0)")
    }
    
    private func endBackgroundTask() {
        guard let taskId = backgroundTaskIdentifier else { return }
        
        print("[Background] Ending background task: \(taskId.rawValue)")
        UIApplication.shared.endBackgroundTask(taskId)
        backgroundTaskIdentifier = .invalid
    }
    
    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.macmultipeer.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[Background] Scheduled background refresh")
        } catch {
            print("[Background] Failed to schedule background refresh: \(error)")
        }
    }
    
    private func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()
        
        task.expirationHandler = {
            print("[Background] Background refresh task expired")
            task.setTaskCompleted(success: false)
        }
        
        Task {
            await handleBackgroundRefresh()
            task.setTaskCompleted(success: true)
        }
    }
    #endif
    
    func handleBackgroundRefresh() async {
        print("[Background] Handling background refresh")
        
        // Keep multipeer connection alive
        await MainActor.run {
            // This would be called to maintain connections
            NotificationCenter.default.post(name: .backgroundRefresh, object: nil)
        }
    }
}

extension Notification.Name {
    static let backgroundRefresh = Notification.Name("backgroundRefresh")
}
