//
//  NudgeScheduler.swift
//  ActuallyDidIt
//
//  Turns each task's nudge intensity into local notifications. Mirrors the
//  `FocusActivityController` pattern: a single reconcile entry point rebuilds the full set of
//  scheduled reminders from the current store state, so nudges automatically stop the moment a
//  task is completed or deleted.
//
//  Only tasks that are pending and due today (or overdue) are nudged, and only the single
//  highest-priority one at a time — this keeps us well under iOS's 64 pending-notification limit.
//  The reminders fire inside a daytime window defined per intensity (see
//  `NudgeIntensity.dailyFireHours`).
//

import Foundation
import SwiftData
import UserNotifications
import os

@MainActor
final class NudgeScheduler {
    static let shared = NudgeScheduler()
    private init() {}

    private let logger = Logger(subsystem: "com.devinharmse.ActuallyDidIt", category: "NudgeScheduler")
    private let center = UNUserNotificationCenter.current()

    /// Every notification request this scheduler owns is prefixed with this, so we can rebuild our
    /// own set without disturbing notifications scheduled elsewhere.
    private static let idPrefix = "nudge-"

    /// Asks the user for permission to post reminders. Safe to call on every launch.
    func requestAuthorization() async {
        do {
            try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            logger.error("Notification authorization failed: \(error.localizedDescription)")
        }
    }

    /// Rebuilds the set of scheduled nudges to match the current store state.
    /// Clears everything this scheduler previously scheduled, then re-adds reminders for the single
    /// highest-priority eligible task.
    func reconcile(in context: ModelContext) {
        let eligible = eligibleTasks(in: context).sorted(by: TaskPrioritizer.isHigherPriority)
        let requests = eligible.first.map { top in
            makeRequests(for: top, othersRemaining: eligible.count - 1)
        } ?? []

        Task {
            await clearOwnedRequests()
            for request in requests {
                do {
                    try await center.add(request)
                } catch {
                    logger.error("Failed to schedule nudge: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Eligibility

    /// Pending tasks that are due today or overdue and not currently being worked on.
    private func eligibleTasks(in context: ModelContext) -> [TaskItem] {
        let pendingRaw = TaskStatus.pending.rawValue
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.statusRaw == pendingRaw }
        )
        let all = (try? context.fetch(descriptor)) ?? []
        let now = Date()
        let calendar = Calendar.current

        return all.filter { task in
            guard !task.isCurrent else { return false }               // actively being done
            guard let due = task.dueDate else { return false }         // only dated tasks nudge
            return calendar.isDateInToday(due) || due < now            // due today or overdue
        }
    }

    // MARK: - Building requests

    /// One notification request per fire-hour that is still in the future today.
    /// `othersRemaining` is the number of other tasks also due today, surfaced in the body.
    private func makeRequests(for task: TaskItem, othersRemaining: Int) -> [UNNotificationRequest] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let body = nudgeBody(for: task, othersRemaining: othersRemaining)

        return task.nudgePolicy.intensity.dailyFireHours.compactMap { hour in
            guard let fireDate = calendar.date(byAdding: .hour, value: hour, to: startOfToday),
                  fireDate > now else { return nil }

            let content = UNMutableNotificationContent()
            content.title = task.title
            content.body = body
            content.sound = .default

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let id = "\(Self.idPrefix)\(task.id.uuidString)-\(hour)"

            return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        }
    }

    /// Reminder body: the task's surfacing reason and estimate, plus a count of other tasks still
    /// due for the day.
    private func nudgeBody(for task: TaskItem, othersRemaining: Int) -> String {
        var body = "\(task.surfacingReason) · \(task.estimatedTimeLabel)"
        if othersRemaining > 0 {
            let plural = othersRemaining == 1 ? "task" : "tasks"
            body += " · \(othersRemaining) more \(plural) today"
        }
        return body
    }

    /// Removes only the pending requests this scheduler owns.
    private func clearOwnedRequests() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
