//
//  SharedStore.swift
//  ActuallyDoIt
//
//  Single source of truth for the SwiftData store that both the app and the widget extension
//  open. The store lives in a shared **App Group** container so the widget process can read the
//  same tasks the app writes (the app's private container is invisible to extensions).
//
//  IMPORTANT: this file must be a member of BOTH the `ActuallyDoIt` app target and the
//  `FocusActivityExtension` target.
//
//  CloudKit ownership: the app opens the store *with* CloudKit (`cloudKit: true`); the extension
//  opens the *same* store *without* CloudKit (`cloudKit: false`). Writes the widget makes land in
//  the shared SQLite + persistent history, and the app exports them to iCloud on its next run.
//

import Foundation
import SwiftData

enum SharedStore {
    /// The App Group both targets share. Must match the `com.apple.security.application-groups`
    /// entry in each target's entitlements.
    nonisolated static let appGroupID = "group.com.devinharmse.ActuallyDoIt"

    /// The iCloud container backing CloudKit sync (mirrors the app's entitlements).
    nonisolated static let cloudKitContainerIdentifier = "iCloud.com.devinharmse.ActuallyDoIt"

    /// The store file name inside the App Group container.
    nonisolated static let storeFileName = "ActuallyDoIt.store"

    /// The shared App Group container directory. Fatal only if the App Groups capability is
    /// missing/misconfigured, which is a build-time setup error rather than a runtime condition.
    nonisolated static var groupContainerURL: URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            fatalError("App Group container \(appGroupID) is unavailable. Check the App Groups capability on both targets.")
        }
        return url
    }

    /// The on-disk location of the shared store.
    nonisolated static var storeURL: URL {
        groupContainerURL.appendingPathComponent(storeFileName)
    }

    /// Whether an iCloud account is currently signed in on this device.
    ///
    /// A synchronous, network-free check (unlike `CKContainer.accountStatus`) used at launch to
    /// decide whether to open the store with CloudKit mirroring. Opening a syncing store while
    /// signed out triggers noisy — though non-fatal — CoreData+CloudKit account-recovery logging
    /// (`CKAccountStatusNoAccount`, "Could not validate account info cache"), so we simply run the
    /// store locally until an account is available. Sync resumes on the next launch after sign-in.
    nonisolated static var iCloudAccountAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Builds the SwiftData container for the shared store through the versioned `AppMigrationPlan`.
    /// Pass `cloudKit: true` from the app (which owns syncing) and `false` from the extension.
    nonisolated static func makeContainer(cloudKit: Bool) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: cloudKit ? .private(cloudKitContainerIdentifier) : .none
        )
        return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [configuration])
    }

    /// Fetches a single task by its `id.uuidString`, used by the widget App Intents.
    nonisolated static func task(withID id: String, in context: ModelContext) -> TaskItem? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// One-time safety net for the move from the app's private container into the App Group.
    ///
    /// For users signed into iCloud the CloudKit mirror re-downloads their data into the new store
    /// automatically, so this is mainly for users *not* syncing: if the shared store doesn't exist
    /// yet but a store exists at the old default location, copy it (and its `-wal`/`-shm` sidecars)
    /// across so their local data isn't stranded. Best-effort and non-fatal.
    nonisolated static func relocateLegacyStoreIfNeeded() {
        let fileManager = FileManager.default
        let destination = storeURL

        // Already migrated (or a fresh install): nothing to do.
        guard !fileManager.fileExists(atPath: destination.path) else { return }

        // SwiftData's default store when no URL is given: "default.store" in Application Support.
        let legacy = URL.applicationSupportDirectory.appendingPathComponent("default.store")
        guard fileManager.fileExists(atPath: legacy.path) else { return }

        // The store is backed by three files that must move together.
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: legacy.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }

            let target = URL(fileURLWithPath: destination.path + suffix)
            do {
                try fileManager.copyItem(at: source, to: target)
            } catch {
                print("SharedStore relocate: could not copy \(source.lastPathComponent): \(error)")
            }
        }
    }
}
