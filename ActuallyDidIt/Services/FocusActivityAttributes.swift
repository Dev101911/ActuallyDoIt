//
//  FocusActivityAttributes.swift
//  ActuallyDidIt
//
//  Describes the Live Activity that surfaces the single focused task on the Lock Screen and
//  in the Dynamic Island.
//
//  IMPORTANT: this file must be a member of BOTH the `ActuallyDidIt` app target and the
//  `FocusActivity` widget-extension target. A Live Activity's `ActivityAttributes` type has to
//  compile into both so the app can start/update it and the widget can render it.
//

import Foundation
import ActivityKit

struct FocusActivityAttributes: ActivityAttributes {
    /// The dynamic content shown by the activity. Kept intentionally small (well under the 4KB
    /// limit ActivityKit imposes on `ContentState`).
    struct ContentState: Codable, Hashable {
        /// The task's title.
        var title: String
        /// A short reason string (e.g. "Due today"), mirroring `TaskItem.surfacingReason`.
        var reason: String
        /// The user's own estimate, in minutes.
        var estimatedMinutes: Int
        /// When focus began — drives the live, self-updating elapsed timer in the UI.
        var focusStartedAt: Date
    }

    /// Stable identity of the focused task (`TaskItem.id.uuidString`), used to tell whether a
    /// running activity already represents the current task or needs replacing.
    var taskID: String
}
