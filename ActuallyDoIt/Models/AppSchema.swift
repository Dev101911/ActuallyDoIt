//
//  AppSchema.swift
//  ActuallyDoIt
//
//  Versioned schema + migration plan for the SwiftData store.
//
//  Why this exists: SwiftData can only perform *automatic* lightweight migration for additive
//  changes (new optional properties, new models). Anything more — renames, type changes, deletions,
//  new uniqueness constraints — requires an explicit migration or the store fails to open. By
//  routing the container through a `SchemaMigrationPlan` from day one, every future schema change
//  has a defined, testable upgrade path instead of an implicit gamble.
//
//  How to evolve this:
//    1. Add a new `SchemaVN` enum capturing the models at that version.
//    2. Add a `MigrationStage` (`.lightweight` for additive changes, `.custom` otherwise) from the
//       previous version to the new one.
//    3. Append the new version to `schemas` and point `CurrentSchema` at it.
//    4. Add a fixture test that opens a real store from the previous version against the new plan.
//

import Foundation
import SwiftData

/// The initial shipped schema. Captures the models exactly as they exist today so future versions
/// have a concrete baseline to migrate from.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [TaskItem.self]
    }
}

/// Points at the latest schema so the rest of the app has a single source of truth. Update this
/// alias whenever a new `SchemaVN` becomes current.
typealias CurrentSchema = SchemaV1

/// Describes how the store evolves between schema versions. Empty stages today because there is
/// only one version; each future version adds one stage describing how to reach it.
///
/// Note: purely *additive* changes to the current models — including adding optional fields to a
/// `Codable` value stored on a model, such as `NudgePolicy`'s per-task time override — are migrated
/// automatically by SwiftData's lightweight inference and do **not** need a new version here. A new
/// `SchemaVN` + stage is required only for changes lightweight inference can't do on its own
/// (renames, type changes, deletions, new uniqueness constraints). Bumping the version for an
/// additive change would in fact fail: two `VersionedSchema`s that describe identical models produce
/// identical checksums, which a migration plan rejects ("Duplicate version checksums detected").
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
