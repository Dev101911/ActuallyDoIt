//
//  NudgePolicy.swift
//  ADHDoIt
//
//  How persistently the app re-reminds the user about a given task.
//

import Foundation

/// Configuration for the nudge engine on a per-task basis.
///
/// Stored as a `Codable` value on the task model.
struct NudgePolicy: Codable, Hashable {
    var intensity: NudgeIntensity
    /// Gap between re-nudges, in seconds.
    var repeatInterval: TimeInterval
    var maxNudgesPerDay: Int

    init(intensity: NudgeIntensity = .gentle,
         repeatInterval: TimeInterval = 60 * 60,
         maxNudgesPerDay: Int = 6) {
        self.intensity = intensity
        self.repeatInterval = repeatInterval
        self.maxNudgesPerDay = maxNudgesPerDay
    }

    /// A sensible default policy for a new task.
    static let `default` = NudgePolicy()
}
