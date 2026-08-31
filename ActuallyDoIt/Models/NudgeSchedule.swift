//
//  NudgeSchedule.swift
//  ActuallyDoIt
//
//  The user-configurable times of day at which nudges fire, one schedule per `NudgeIntensity`.
//
//  Values are stored in `UserDefaults` as minutes-from-midnight, which binds cleanly to both
//  `@AppStorage` and SwiftUI time pickers. `NudgeScheduler` reads `fireTimes(for:)` when building
//  notification requests; the settings screen writes the same keys. Defaults mirror the app's
//  original hardcoded schedule so behaviour is unchanged until the user edits it.
//

import Foundation

enum NudgeSchedule {
    // MARK: - Storage keys

    static let gentleKey = "nudge.gentleMinutes"
    static let persistentKeys = [
        "nudge.persistentMinutes0",
        "nudge.persistentMinutes1",
        "nudge.persistentMinutes2",
    ]
    static let relentlessStartKey = "nudge.relentlessStartMinutes"
    static let relentlessEndKey = "nudge.relentlessEndMinutes"

    // MARK: - Defaults (minutes from midnight)

    static let gentleDefault = 9 * 60                          // 09:00
    static let persistentDefaults = [9 * 60, 15 * 60, 21 * 60] // 09:00, 15:00, 21:00
    static let relentlessStartDefault = 9 * 60                 // 09:00
    static let relentlessEndDefault = 21 * 60                  // 21:00

    // MARK: - Fire times (per task)

    /// The hour/minute components at which a nudge fires for a task, honouring the task's per-task
    /// override (`NudgePolicy.customTimes`) when set and otherwise falling back to the global
    /// schedule below.
    static func fireTimes(for policy: NudgePolicy) -> [DateComponents] {
        fireMinutes(for: policy).map(components(fromMinutes:))
    }

    /// The fire times for a task as minutes-from-midnight, sorted ascending. Uses the task's
    /// override when present, otherwise the global schedule.
    static func fireMinutes(for policy: NudgePolicy) -> [Int] {
        guard let custom = policy.customTimes else {
            return fireMinutes(for: policy.intensity)
        }
        switch policy.intensity {
        case .gentle:
            return [custom.gentleMinutes]
        case .persistent:
            return custom.persistentMinutes.sorted()
        case .relentless:
            guard custom.relentlessStartMinutes <= custom.relentlessEndMinutes else { return [] }
            return Array(stride(from: custom.relentlessStartMinutes,
                                through: custom.relentlessEndMinutes,
                                by: 60))
        }
    }

    /// The current global schedule captured as an override value, used to seed a task's custom
    /// times when the user first opts in to overriding them.
    static func currentTimes() -> NudgeTimes {
        NudgeTimes(
            gentleMinutes: read(gentleKey, default: gentleDefault),
            persistentMinutes: persistentKeys.enumerated().map { index, key in
                read(key, default: persistentDefaults[index])
            },
            relentlessStartMinutes: read(relentlessStartKey, default: relentlessStartDefault),
            relentlessEndMinutes: read(relentlessEndKey, default: relentlessEndDefault)
        )
    }

    // MARK: - Fire times (global schedule)

    /// The hour/minute components at which a nudge fires for the given intensity.
    /// Relentless fires on the same minute offset every hour across the waking window.
    static func fireTimes(for intensity: NudgeIntensity) -> [DateComponents] {
        switch intensity {
        case .gentle:
            return [components(fromMinutes: read(gentleKey, default: gentleDefault))]
        case .persistent:
            return persistentKeys.enumerated().map { index, key in
                components(fromMinutes: read(key, default: persistentDefaults[index]))
            }
        case .relentless:
            let start = read(relentlessStartKey, default: relentlessStartDefault)
            let end = read(relentlessEndKey, default: relentlessEndDefault)
            guard start <= end else { return [] }
            return stride(from: start, through: end, by: 60).map(components(fromMinutes:))
        }
    }

    /// The configured fire times for the given intensity, expressed as minutes-from-midnight and
    /// sorted ascending. Same source of truth as `fireTimes(for:)`, in the unit the timeline
    /// preview needs to position its markers.
    static func fireMinutes(for intensity: NudgeIntensity) -> [Int] {
        switch intensity {
        case .gentle:
            return [read(gentleKey, default: gentleDefault)]
        case .persistent:
            return persistentKeys.enumerated()
                .map { index, key in read(key, default: persistentDefaults[index]) }
                .sorted()
        case .relentless:
            let start = read(relentlessStartKey, default: relentlessStartDefault)
            let end = read(relentlessEndKey, default: relentlessEndDefault)
            guard start <= end else { return [] }
            return Array(stride(from: start, through: end, by: 60))
        }
    }

    // MARK: - Conversions for time pickers

    /// A `Date` today at the given minutes-from-midnight, for binding to a `DatePicker`.
    static func date(fromMinutes minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60,
                              minute: minutes % 60,
                              second: 0,
                              of: Date()) ?? Date()
    }

    /// The minutes-from-midnight of the given date's time-of-day.
    static func minutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    // MARK: - Private

    nonisolated private static func components(fromMinutes minutes: Int) -> DateComponents {
        DateComponents(hour: minutes / 60, minute: minutes % 60)
    }

    private static func read(_ key: String, default fallback: Int) -> Int {
        UserDefaults.standard.object(forKey: key) as? Int ?? fallback
    }
}
