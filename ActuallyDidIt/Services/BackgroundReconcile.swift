//
//  BackgroundReconcile.swift
//  ActuallyDidIt
//
//  Runs `NudgeScheduler.reconcile` opportunistically in the background via `BGAppRefreshTask`, so
//  the rolling notification set is refreshed at the day rollover even when the user hasn't opened
//  the app.
//
//  This is a best-effort layer, not a guarantee: iOS decides if and when to grant background time
//  based on battery, network, and how often the app is launched, and it never runs if the user
//  force-quits the app or disables Background App Refresh. The morning digests scheduled by
//  `NudgeScheduler` remain the reliable fallback that prompts the user to reopen the app.
//
//  We only need this roughly once a day: the one thing that decays over time is the day rollover
//  (a new day's nudges need scheduling and the digests re-arming), so each run re-arms the next
//  request for the next early morning.
//

import BackgroundTasks
import SwiftData
import os

enum BackgroundReconcile {
    /// Must match the entry in the app's `BGTaskSchedulerPermittedIdentifiers` (Info.plist).
    static let taskIdentifier = "com.devinharmse.ActuallyDidIt.reconcile"

    /// The hour of day we aim to run at — early enough to land before the 08:30 digest and the
    /// 09:00 default nudge, so a granted run replaces the fallback digest with a fresh one.
    private static let targetHour = 6

    private static let logger = Logger(subsystem: "com.devinharmse.ActuallyDidIt",
                                        category: "BackgroundReconcile")

    /// Registers the reconcile handler. Must be called before the app finishes launching (from the
    /// App's `init`); registering later makes `BGTaskScheduler` reject the identifier.
    static func register(container: ModelContainer) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask, container: container)
        }
    }

    /// Submits (or replaces) the pending request for the next early morning. Safe to call
    /// repeatedly — the scheduler keeps only the latest pending request per identifier.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = nextEarlyMorning()
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.error("Could not schedule background reconcile: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private static func handle(_ task: BGAppRefreshTask, container: ModelContainer) {
        // Re-arm first, so an early expiry or failure mid-run doesn't stop future runs.
        schedule()

        let work = Task { @MainActor in
            await NudgeScheduler.shared.performReconcile(in: container.mainContext)
        }

        // If iOS reclaims our runtime, cancel the work; the completion below still fires exactly
        // once with the cancellation reflected in the reported success.
        task.expirationHandler = { work.cancel() }

        Task {
            _ = await work.value
            task.setTaskCompleted(success: !work.isCancelled)
        }
    }

    /// The next occurrence of `targetHour:00` local time, strictly in the future. `earliestBeginDate`
    /// is only a floor — the system may run us later — so this is a sensible "not before" hint.
    private static func nextEarlyMorning() -> Date {
        let calendar = Calendar.current
        let components = DateComponents(hour: targetHour, minute: 0)
        return calendar.nextDate(after: Date(),
                                 matching: components,
                                 matchingPolicy: .nextTime)
            ?? Date(timeIntervalSinceNow: 24 * 60 * 60)
    }
}
