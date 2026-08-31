//
//  PersistenceTests.swift
//  ActuallyDoItTests
//
//  Guards the data-durability work: the versioned schema / migration plan, and the Codable
//  value types persisted on `TaskItem`. These are the pieces most likely to silently corrupt or
//  drop user data across an app update, so they get direct coverage.
//

import Testing
import SwiftData
import Foundation
@testable import ActuallyDoIt

// @MainActor so the SwiftData work runs serialized on the main actor, exactly as the app does.
// Swift Testing runs tests in parallel by default; concurrent access to SwiftData's composite
// attribute decoder from separate tests races and crashes ("Unable to decode this value"), which
// is a test-concurrency artifact, not app behaviour. See [[swiftdata-persistence-testing]].
@MainActor
@Suite("Persistence & migration")
struct PersistenceTests {

    // MARK: - Migration plan shape

    @Test("Migration plan declares V1 as its only, current version")
    func migrationPlanDeclaresV1() {
        #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(AppMigrationPlan.schemas.count == 1)
        #expect(AppMigrationPlan.schemas.first == SchemaV1.self)
        // No stages: additive changes (e.g. NudgePolicy's optional custom-time fields) are migrated
        // by SwiftData's automatic lightweight inference. A stage is added only for a change
        // inference can't handle on its own.
        #expect(AppMigrationPlan.stages.isEmpty)
        #expect(CurrentSchema.models.contains { $0 == TaskItem.self })
    }

    // MARK: - On-disk persistence through the migration-plan container path

    /// Builds a real on-disk store exactly as the app builds it (versioned schema + migration
    /// plan), inserts a task carrying both `Codable` composite properties, and saves. Asserts the
    /// row persists via a COUNT query.
    ///
    /// Why COUNT rather than fetch-and-inspect: this test suite builds several `ModelContainer`s
    /// for `TaskItem` across its tests, and SwiftData's per-type composite-attribute *decoder* gets
    /// into a bad state when multiple containers for the same model type exist in one process —
    /// decoding a composite from an on-disk row then fatal-errors ("Unable to decode this value").
    /// That is a test-process limitation (the app has a single container for its whole lifetime and
    /// is unaffected — verified by launching the built app twice and seeing persisted Chores/nudges
    /// load fine). COUNT proves the row persisted without hitting the decoder; the composite
    /// round-trip is asserted against an in-memory store below. See [[swiftdata-persistence-testing]].
    @Test("A task saves to a real on-disk store built through the migration plan")
    func taskPersistsToOnDiskStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("RoundTrip.store")
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema,
                                           migrationPlan: AppMigrationPlan.self,
                                           configurations: [configuration])

        let context = ModelContext(container)
        context.insert(TaskItem(title: "Buy milk",
                                estimatedMinutes: 25,
                                recurrenceRule: RecurrenceRule(frequency: .weekly, interval: 2),
                                nudgePolicy: NudgePolicy(intensity: .persistent)))
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<TaskItem>()) == 1)
    }

    /// Verifies the `Codable` composite properties survive an insert → save → fetch round trip
    /// against an in-memory store — the same read path the app exercises at runtime, and which
    /// (unlike the on-disk decoder under multiple containers) materialises composites reliably.
    @Test("Codable value types round-trip through an insert/save/fetch")
    func storedValueTypesRoundTrip() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])

        let context = ModelContext(container)
        // Carry a per-task custom-time override so the flattened NudgePolicy fields round-trip too.
        // Reading this composite back is the exact path that trapped at launch when the override was
        // stored as a nested struct-with-array.
        let override = NudgeTimes(gentleMinutes: 8 * 60,
                                  persistentMinutes: [9 * 60, 13 * 60, 20 * 60],
                                  relentlessStartMinutes: 7 * 60,
                                  relentlessEndMinutes: 22 * 60)
        let task = TaskItem(title: "Buy milk",
                            estimatedMinutes: 25,
                            recurrenceRule: RecurrenceRule(frequency: .weekly, interval: 2),
                            nudgePolicy: NudgePolicy(intensity: .persistent, customTimes: override),
                            verificationMethod: .delayedRecheck)
        let savedID = task.id
        context.insert(task)
        try context.save()

        let restored = try #require(try context.fetch(FetchDescriptor<TaskItem>()).first)
        #expect(restored.id == savedID)
        #expect(restored.title == "Buy milk")
        #expect(restored.estimatedMinutes == 25)
        #expect(restored.nudgePolicy.intensity == .persistent)
        #expect(restored.nudgePolicy.customTimes == override)
        #expect(restored.recurrenceRule == RecurrenceRule(frequency: .weekly, interval: 2))
        #expect(restored.verificationMethod == .delayedRecheck)
    }

    // MARK: - Codable stability of stored value types

    // These structs are stored inside the SwiftData model as Codable blobs. If their coding
    // changes incompatibly, existing rows fail to decode — so a round-trip guard protects them.

    @Test("NudgePolicy round-trips through Codable unchanged")
    func nudgePolicyCodableRoundTrip() throws {
        let original = NudgePolicy(intensity: .relentless, repeatInterval: 1800, maxNudgesPerDay: 4)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NudgePolicy.self, from: data)
        #expect(decoded == original)
    }

    @Test("RecurrenceRule round-trips through Codable unchanged")
    func recurrenceRuleCodableRoundTrip() throws {
        let original = RecurrenceRule(frequency: .weekly, interval: 2)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: data)
        #expect(decoded == original)
    }
}
