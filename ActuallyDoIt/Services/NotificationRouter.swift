//
//  NotificationRouter.swift
//  ActuallyDoIt
//
//  Bridges notification taps into the app's UI. As the `UNUserNotificationCenter` delegate it
//  receives the user's response when they tap a nudge, pulls the task id out of the notification's
//  `userInfo`, and publishes it as `selectedTaskID`. The Now screen observes that and opens the
//  matching task's detail view.
//
//  The delegate must be assigned before the app finishes launching (so a tap that cold-launches the
//  app isn't missed); the router sets itself as the delegate on init, and the app creates it as a
//  stored property during `App.init`.
//

import Foundation
import UserNotifications

@Observable
@MainActor
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    /// The `userInfo` key under which each task-specific nudge carries its task id.
    nonisolated static let taskIDKey = "taskID"

    /// The task the user asked to open by tapping its notification. The UI clears this back to `nil`
    /// once it has presented the task, so repeated taps of the same task re-trigger presentation.
    var selectedTaskID: UUID?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Called when the user taps (or otherwise responds to) a delivered notification. Summary and
    /// digest notifications carry no task id, so those simply open the app to the Now screen.
    ///
    /// We deliberately implement the **completion-handler** variant rather than the `async` one. The
    /// `async` variant is `nonisolated`, so Swift runs *and completes* it on the generic cooperative
    /// executor — off the main thread. The instant the response is reported handled, UIKit runs a
    /// state-restoration snapshot pass (`_updateSnapshotAndStateRestoration…` →
    /// `_performBlockAfterCATransactionCommitSynchronizes…`) on whatever thread completed the task.
    /// That pass is main-thread-only; running it off the cooperative pool trips an
    /// NSInternalInconsistency assertion and aborts the app on a cold-launch notification tap.
    ///
    /// So we do *everything* — reading the id, mutating `selectedTaskID`, and calling the completion
    /// handler that lets UIKit start its snapshot — on a later main-thread runloop turn. `DispatchQueue`
    /// `.main.async` both moves that work onto the main thread and defers it past the launch-time
    /// CATransaction commit, so UIKit's snapshot pass runs on the main thread on a clean turn.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let taskID = (userInfo[Self.taskIDKey] as? String).flatMap(UUID.init(uuidString:))
        DispatchQueue.main.async {
            if let taskID {
                MainActor.assumeIsolated { self.selectedTaskID = taskID }
            }
            completionHandler()
        }
    }
}
