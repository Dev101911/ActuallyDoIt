//
//  NudgePolicy.swift
//  ActuallyDidIt
//
//  How persistently the app re-reminds the user about a given task.
//

import Foundation

/// Configuration for the nudge engine on a per-task basis.
///
/// Stored as a `Codable` value on the task model, which SwiftData persists as a **composite
/// attribute**. A composite can only be made of scalar members — it cannot hold a nested struct
/// that contains an array — so the per-task time override is stored here as flat optional `Int`
/// fields rather than a nested `NudgeTimes?`. The nested value type is still exposed to callers
/// through the computed `customTimes` property below.
struct NudgePolicy: Codable, Hashable {
    var intensity: NudgeIntensity
    /// Gap between re-nudges, in seconds.
    var repeatInterval: TimeInterval
    var maxNudgesPerDay: Int

    // A per-task override of the times of day nudges fire, flattened into scalars for composite
    // storage (see the type doc). All-`nil` means "follow the global schedule set in Settings".
    // Optional so older stored policies — which lacked these fields — decode cleanly.
    var customGentleMinutes: Int?
    var customPersistentMinutes0: Int?
    var customPersistentMinutes1: Int?
    var customPersistentMinutes2: Int?
    var customRelentlessStartMinutes: Int?
    var customRelentlessEndMinutes: Int?

    init(intensity: NudgeIntensity = .gentle,
         repeatInterval: TimeInterval = 60 * 60,
         maxNudgesPerDay: Int = 6,
         customTimes: NudgeTimes? = nil) {
        self.intensity = intensity
        self.repeatInterval = repeatInterval
        self.maxNudgesPerDay = maxNudgesPerDay
        // Initialise the override storage to nil so the instance is fully formed, then route through
        // the computed setter for a single decomposition point.
        self.customGentleMinutes = nil
        self.customPersistentMinutes0 = nil
        self.customPersistentMinutes1 = nil
        self.customPersistentMinutes2 = nil
        self.customRelentlessStartMinutes = nil
        self.customRelentlessEndMinutes = nil
        self.customTimes = customTimes
    }

    /// The per-task time override assembled from / decomposed into the stored scalar fields.
    /// `nil` when the task follows the global schedule.
    var customTimes: NudgeTimes? {
        get {
            guard let gentle = customGentleMinutes,
                  let persistent0 = customPersistentMinutes0,
                  let persistent1 = customPersistentMinutes1,
                  let persistent2 = customPersistentMinutes2,
                  let start = customRelentlessStartMinutes,
                  let end = customRelentlessEndMinutes else { return nil }
            return NudgeTimes(gentleMinutes: gentle,
                              persistentMinutes: [persistent0, persistent1, persistent2],
                              relentlessStartMinutes: start,
                              relentlessEndMinutes: end)
        }
        set {
            customGentleMinutes = newValue?.gentleMinutes
            customPersistentMinutes0 = newValue?.persistentMinutes[safe: 0]
            customPersistentMinutes1 = newValue?.persistentMinutes[safe: 1]
            customPersistentMinutes2 = newValue?.persistentMinutes[safe: 2]
            customRelentlessStartMinutes = newValue?.relentlessStartMinutes
            customRelentlessEndMinutes = newValue?.relentlessEndMinutes
        }
    }

    /// A sensible default policy for a new task.
    static let `default` = NudgePolicy()
}

/// A per-task override of the times of day nudges fire, expressed as minutes-from-midnight. Holds a
/// value for every intensity so the stored override stays valid even if the task's intensity later
/// changes. Mirrors the fields the global schedule (`NudgeSchedule`) exposes.
///
/// This is the in-memory / view-facing shape only; `NudgePolicy` persists it as flat scalar fields
/// (see its doc). Defined here rather than in `NudgeSchedule` because `NudgePolicy` uses it and must
/// compile into the widget extension target too (which doesn't include `NudgeSchedule`).
struct NudgeTimes: Codable, Hashable {
    /// The single reminder time for a Gentle task.
    var gentleMinutes: Int
    /// The three reminder times for a Persistent task.
    var persistentMinutes: [Int]
    /// The waking-window bounds a Relentless task fires hourly across.
    var relentlessStartMinutes: Int
    var relentlessEndMinutes: Int
}

private extension Array {
    /// Bounds-checked access so decomposing a `persistentMinutes` array with fewer than three
    /// entries yields `nil` rather than trapping.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
