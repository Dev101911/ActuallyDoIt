//
//  ADHDoItApp.swift
//  ADHDoIt
//
//  Created by Devin Harmse on 03/08/2026.
//

import SwiftUI
import SwiftData

@main
struct ADHDoItApp: App {
    @AppStorage(AccentTheme.storageKey) private var accentTheme = AccentTheme.default
    @AppStorage(AppearanceTheme.storageKey) private var appearanceTheme = AppearanceTheme.default

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TaskItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // In DEBUG, populate the simulator with mock data on first launch.
                    #if DEBUG
                    SampleData.seedIfEmpty(sharedModelContainer.mainContext)
                    #endif

                    // Re-adopt any Live Activity still running from a previous launch and
                    // sync it with the current focus state.
                    FocusActivityController.shared.restore(in: sharedModelContainer.mainContext)

                    // Ask for notification permission, then (re)schedule today's nudges.
                    await NudgeScheduler.shared.requestAuthorization()
                    NudgeScheduler.shared.reconcile(in: sharedModelContainer.mainContext)
                }
                .tint(accentTheme.color)
                .preferredColorScheme(appearanceTheme.colorScheme)
        }
        .modelContainer(sharedModelContainer)
    }
}
