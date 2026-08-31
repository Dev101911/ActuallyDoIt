//
//  ActuallyDoItApp.swift
//  ActuallyDoIt
//
//  Created by Devin Harmse on 03/08/2026.
//

import SwiftUI
import SwiftData
import CoreData

@main
struct ActuallyDoItApp: App {
    @AppStorage(AccentTheme.storageKey) private var accentTheme = AccentTheme.default
    @AppStorage(AppearanceTheme.storageKey) private var appearanceTheme = AppearanceTheme.default
    @Environment(\.scenePhase) private var scenePhase

    let sharedModelContainer: ModelContainer = ActuallyDoItApp.makeSharedModelContainer()

    /// Routes notification taps to the matching task. Created here (not lazily) so it becomes the
    /// notification-center delegate before the app finishes launching, as UserNotifications requires
    /// to catch a tap that cold-launches the app.
    private let notificationRouter = NotificationRouter()

    init() {
        #if DEBUG
        // When launched for App Store screenshot capture, pin a deterministic look before any view
        // reads its `@AppStorage`, and suppress the first-run tour so it never covers the UI.
        if ActuallyDoItApp.isScreenshotMode {
            UserDefaults.standard.set(AccentTheme.green.rawValue, forKey: AccentTheme.storageKey)
            UserDefaults.standard.set(AppearanceTheme.light.rawValue, forKey: AppearanceTheme.storageKey)
            UserDefaults.standard.set(true, forKey: TutorialView.storageKey)
        }
        #endif

        // Register the background reconcile handler before the app finishes launching, as
        // BGTaskScheduler requires. The request itself is submitted from the scene lifecycle below.
        BackgroundReconcile.register(container: sharedModelContainer)
    }

    #if DEBUG
    /// True when the app was launched by the screenshot UI test (see `Scripts/generate_screenshots.sh`).
    /// In this mode the app uses a curated in-memory store and skips runtime side effects — notably
    /// the notification-permission prompt — so captures are clean and deterministic.
    static var isScreenshotMode: Bool {
        CommandLine.arguments.contains("--screenshots")
    }
    #endif

    /// Builds the SwiftData container for the shared App Group store (see `SharedStore`) through the
    /// versioned `AppMigrationPlan`. The app opens the store *with* CloudKit — but only when an
    /// iCloud account is signed in; the widget extension always opens the same store without it.
    ///
    /// Enabling CloudKit mirroring while signed out produces noisy (non-fatal) account-recovery
    /// logging and no actual sync, so when there's no account we open the store locally and let
    /// sync resume on the next launch after sign-in.
    ///
    /// If the store can't be opened — almost always a migration that failed after an app update —
    /// we do **not** `fatalError` (that would crash every launch and lock the user out of their
    /// data permanently). Instead we move the existing store files aside, preserving them for
    /// recovery, and retry with a fresh store so the app stays usable. A `fatalError` is kept only
    /// as an unreachable last resort, when even an empty store can't be created.
    static func makeSharedModelContainer() -> ModelContainer {
        #if DEBUG
        // Screenshot capture runs against a throwaway in-memory store so it never touches (or is
        // polluted by) the user's real data or CloudKit.
        if isScreenshotMode {
            return SampleData.makeScreenshotContainer()
        }
        #endif

        // One-time move of any pre-App-Group store into the shared container.
        SharedStore.relocateLegacyStoreIfNeeded()

        // Only mirror to CloudKit when there's actually an iCloud account to mirror to.
        let useCloudKit = SharedStore.iCloudAccountAvailable

        // In DEBUG, ensure the CloudKit development schema is fully materialised before we open the
        // syncing store (see `initializeCloudKitSchema`). Best-effort and non-fatal, and pointless
        // (it just fails and logs) when signed out — so skip it then.
        #if DEBUG
        if useCloudKit {
            initializeCloudKitSchema()
        }
        #endif

        do {
            return try SharedStore.makeContainer(cloudKit: useCloudKit)
        } catch {
            // Preserve the unreadable store rather than losing it, then start clean.
            backupStoreFiles(at: SharedStore.storeURL, reason: error)

            do {
                return try SharedStore.makeContainer(cloudKit: useCloudKit)
            } catch {
                fatalError("Could not create ModelContainer even after preserving the existing store: \(error)")
            }
        }
    }

    #if DEBUG
    /// Pushes the current model schema to the CloudKit **development** environment so every record
    /// type and field exists server-side. This is what lets you later click "Deploy Schema to
    /// Production" in the CloudKit Console with a complete schema, rather than relying on lazy
    /// creation (which only registers fields it has actually seen data for).
    ///
    /// Best-effort by design: it never crashes the app. If it can't run — e.g. the simulator isn't
    /// signed into iCloud, or there's no network — SwiftData still creates the schema lazily on the
    /// first sync. The temporary Core Data store is unloaded before we return so it doesn't contend
    /// with the SwiftData container for the same on-disk file.
    private static func initializeCloudKitSchema() {
        do {
            try autoreleasepool {
                let description = NSPersistentStoreDescription(url: SharedStore.storeURL)
                description.cloudKitContainerOptions =
                    NSPersistentCloudKitContainerOptions(containerIdentifier: SharedStore.cloudKitContainerIdentifier)
                // Load synchronously so the store is ready before we initialize the schema.
                description.shouldAddStoreAsynchronously = false

                guard let model = NSManagedObjectModel.makeManagedObjectModel(for: CurrentSchema.models) else { return }
                let container = NSPersistentCloudKitContainer(name: "ActuallyDoIt", managedObjectModel: model)
                container.persistentStoreDescriptions = [description]
                container.loadPersistentStores { _, error in
                    if let error { print("CloudKit schema init: store load failed: \(error)") }
                }

                try container.initializeCloudKitSchema()

                // Unload the store so it doesn't fight the SwiftData container for the same file.
                if let store = container.persistentStoreCoordinator.persistentStores.first {
                    try container.persistentStoreCoordinator.remove(store)
                }
            }
        } catch {
            print("CloudKit schema init skipped: \(error)")
        }
    }
    #endif

    /// Moves the SwiftData store and its `-wal`/`-shm` sidecar files into a timestamped backup
    /// folder next to the store. Nothing is deleted, so a failed migration is recoverable (via
    /// support, a future re-import path, or manual inspection) instead of silently discarded.
    private static func backupStoreFiles(at storeURL: URL, reason: Error) {
        let fileManager = FileManager.default
        let directory = storeURL.deletingLastPathComponent()
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupDirectory = directory.appendingPathComponent("CorruptStoreBackup-\(stamp)", isDirectory: true)

        do {
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        } catch {
            print("SwiftData store recovery: could not create backup directory: \(error)")
            return
        }

        // The store is backed by three files that must move together.
        let sidecars = ["", "-wal", "-shm"]
        for suffix in sidecars {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }

            let destination = backupDirectory.appendingPathComponent(source.lastPathComponent)
            do {
                try fileManager.moveItem(at: source, to: destination)
            } catch {
                print("SwiftData store recovery: could not move \(source.lastPathComponent): \(error)")
            }
        }

        print("SwiftData store recovery: opening the store failed (\(reason)). Preserved existing store at \(backupDirectory.path) and started a fresh store.")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    #if DEBUG
                    // Screenshot capture uses a pre-seeded in-memory store and must not trigger the
                    // notification-permission prompt (it would cover the UI), so skip all launch
                    // side effects in that mode.
                    if ActuallyDoItApp.isScreenshotMode { return }

                    // In DEBUG, populate the simulator with mock data on first launch.
                    SampleData.seedIfEmpty(sharedModelContainer.mainContext)
                    #endif

                    // Re-adopt any Live Activity still running from a previous launch and
                    // sync it with the current focus state.
                    FocusActivityController.shared.restore(in: sharedModelContainer.mainContext)

                    // Ask for notification permission, then (re)schedule today's nudges.
                    await NudgeScheduler.shared.requestAuthorization()
                    NudgeScheduler.shared.reconcile(in: sharedModelContainer.mainContext)

                    // Ensure a background reconcile is queued even if the app is killed straight
                    // from the foreground without ever entering the background.
                    BackgroundReconcile.schedule()
                }
                .environment(notificationRouter)
                .tint(accentTheme.color)
                .background(AppearanceStyleSetter(style: appearanceTheme.uiStyle))
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        // Coming back to the foreground: a task may have been started or completed
                        // from the widget while we were backgrounded. Re-sync the Live Activity and
                        // nudges with the (possibly changed) store state.
                        FocusActivityController.shared.restore(in: sharedModelContainer.mainContext)
                        NudgeScheduler.shared.reconcile(in: sharedModelContainer.mainContext)
                    case .background:
                        // Leaving the foreground: queue the next opportunistic background reconcile.
                        BackgroundReconcile.schedule()
                    default:
                        break
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

/// Applies the chosen light/dark override to the host window. Sits behind the app's content so
/// it can reach `window`; setting `overrideUserInterfaceStyle` cascades to the whole window
/// (including presented sheets), and `.unspecified` reliably reverts to the system setting.
private struct AppearanceStyleSetter: UIViewRepresentable {
    let style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isHidden = true
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            uiView.window?.overrideUserInterfaceStyle = style
        }
    }
}
