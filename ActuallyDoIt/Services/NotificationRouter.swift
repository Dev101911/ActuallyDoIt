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
    static let taskIDKey = "taskID"

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
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let raw = userInfo[Self.taskIDKey] as? String,
              let id = UUID(uuidString: raw) else { return }
        // Hand the id to the UI on a fresh main-actor turn rather than `await`-ing the mutation
        // inline. Awaiting here runs the state change as part of the notification-response
        // continuation, which on a cold launch UIKit drains inside its post-CATransaction commit /
        // state-restoration snapshot pass (`_updateStateRestorationArchive…` →
        // `_performBlockAfterCATransactionCommit…`). Presenting the routed task's sheet from within
        // that commit crashes. Scheduling a detached task lets the delegate return immediately and
        // defers the mutation — and the sheet presentation it drives — to a clean runloop turn.
        Task { @MainActor in self.selectedTaskID = id }
    }
}
