//
//  FocusActivityController.swift
//  ActuallyDoIt
//
//  Reconciles the Live Activity that surfaces the focused task on the Lock Screen with the
//  "one task in focus at a time" state in the store. Every focus-changing mutation in
//  `TaskActions` calls `reconcile(in:)`, which starts, updates, or ends the activity to match
//  whichever task (if any) is currently focused.
//

import Foundation
import SwiftData
import ActivityKit
import os

@MainActor
final class FocusActivityController {
    static let shared = FocusActivityController()
    private init() {}

    private let logger = Logger(subsystem: "com.devinharmse.ActuallyDoIt", category: "FocusActivity")

    /// The activity this process currently manages, if any.
    private var activity: Activity<FocusActivityAttributes>?

    /// Brings the Live Activity in line with the currently focused task:
    /// starts one when a task gains focus, updates it when the focused task's details change,
    /// and ends it when nothing is focused.
    func reconcile(in context: ModelContext) {
        guard let task = fetchFocused(in: context) else {
            endActivity()
            return
        }

        let state = FocusActivityAttributes.ContentState(
            title: task.title,
            reason: "Currently Doing",
            estimatedMinutes: task.estimatedMinutes,
            focusStartedAt: task.focusStartedAt ?? Date()
        )

        if let activity, activity.attributes.taskID == task.id.uuidString {
            update(activity, with: state)
        } else {
            // Different task (or none tracked yet): replace any existing activity.
            endActivity()
            start(taskID: task.id.uuidString, state: state)
        }
    }

    /// Re-adopts an activity that is still running from a previous launch, then reconciles it
    /// with the store so a now-stale activity is ended.
    func restore(in context: ModelContext) {
        activity = Activity<FocusActivityAttributes>.activities.first
        reconcile(in: context)
    }

    // MARK: - Helpers

    private func fetchFocused(in context: ModelContext) -> TaskItem? {
        var descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.focusStartedAt != nil }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func start(taskID: String, state: FocusActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.info("Live Activities are disabled; not starting one.")
            return
        }
        do {
            activity = try Activity.request(
                attributes: FocusActivityAttributes(taskID: taskID),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            logger.error("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    private func update(_ activity: Activity<FocusActivityAttributes>,
                        with state: FocusActivityAttributes.ContentState) {
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private func endActivity() {
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
