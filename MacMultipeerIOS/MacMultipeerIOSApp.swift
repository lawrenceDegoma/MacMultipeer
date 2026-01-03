//
//  MacMultipeerIOSApp.swift
//  MacMultipeerIOS
//

import SwiftUI
import SwiftData

@main
struct MacMultipeerIOSApp: App {
    // Lazy initialization of ModelContainer to improve launch time
    private var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Fallback to in-memory container if persistent storage fails
            print("Failed to create persistent container, using in-memory: \(error)")
            let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [fallbackConfig])
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
