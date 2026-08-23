//
//  NudgeScheduler.swift
//  ActuallyDidIt
//
//  Turns each task's nudge intensity into local notifications. Mirrors the
//  `FocusActivityController` pattern: a single reconcile entry point rebuilds the full set of
//  scheduled reminders from the current store state, so nudges automatically stop the moment a
//  task is completed or deleted.
//
//  Every task that is pending and due today (or overdue) is nudged. Because iOS caps an app at 64
//  pending notifications, we schedule within a safe budget (`safeBudget`): first we guarantee each
//  due task at least one reminder in priority order, then we spend the remaining budget on the
//  extra reminders of the highest-priority tasks. If there are more due tasks than the budget can
//  cover, the overflow tasks are summarised in a single "N more due today" notification rather than
//  being silently dropped by iOS.
//
//  Reminders fire at the user-configurable times for each task's intensity (see
//  `NudgeSchedule.fireTimes(for:)`).
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

    /// The most reminders we'll ever have pending at once. iOS silently drops anything past 64, so
    /// we stay comfortably under it and leave headroom for the summary notification.
    private static let safeBudget = 60

    /// Asks the user for permission to post reminders. Safe to call on every launch.
    func requestAuthorization() async {
        do {
            try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            logger.error("Notification authorization failed: \(error.localizedDescription)")
        }
    }

    /// Rebuilds the set of scheduled nudges to match the current store state.
    /// Clears everything this scheduler previously scheduled, then re-adds the budgeted set of
    /// reminders for every eligible task.
    func reconcile(in context: ModelContext) {
        let requests = buildRequests(in: context)

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

    // MARK: - Request planning

    /// Computes the full set of notification requests for the current store state, honouring the
    /// notification budget. Pure and synchronous so the allocation logic is easy to reason about.
    private func buildRequests(in context: ModelContext) -> [UNNotificationRequest] {
        let calendar = Calendar.current
        let now = Date()

        let eligible = eligibleTasks(in: context).sorted(by: TaskPrioritizer.isHigherPriority)

        // Pair each task with the fire times still ahead of us today, dropping tasks whose reminder
        // windows have all passed — those can't be scheduled regardless of budget.
        let candidates = eligible
            .map { (task: $0, slots: futureFireSlots(for: $0, now: now, calendar: calendar)) }
            .filter { !$0.slots.isEmpty }

        guard !candidates.isEmpty else { return [] }

        // If we can't give every task at least one reminder, reserve a slot for the summary.
        var budget = Self.safeBudget
        let willDropTasks = candidates.count > budget
        if willDropTasks { budget -= 1 }

        let guaranteedCount = min(candidates.count, budget)
        let scheduled = candidates.prefix(guaranteedCount)
        let dropped = candidates.dropFirst(guaranteedCount)

        var requests: [UNNotificationRequest] = []

        // Pass 1: guarantee every scheduled task its earliest remaining reminder.
        for entry in scheduled {
            let first = entry.slots[0]
            requests.append(makeRequest(for: entry.task, fireDate: first.date, index: first.index, calendar: calendar))
        }

        // Pass 2: spend the remaining budget on extra reminders, highest priority first.
        fill: for entry in scheduled {
            for slot in entry.slots.dropFirst() {
                if requests.count >= budget { break fill }
                requests.append(makeRequest(for: entry.task, fireDate: slot.date, index: slot.index, calendar: calendar))
            }
        }

        // Summary: fold any tasks that got no slot at all into a single notification, fired at the
        // soonest moment one of them would have nudged.
        if !dropped.isEmpty {
            let earliest = dropped.compactMap { $0.slots.first?.date }.min() ?? now
            requests.append(summaryRequest(droppedCount: dropped.count, fireDate: earliest, calendar: calendar))
        }

        return requests
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

    /// The task's configured fire times that are still ahead of `now` today, paired with their
    /// original index so notification identifiers stay stable across reconciles.
    private func futureFireSlots(for task: TaskItem,
                                 now: Date,
                                 calendar: Calendar) -> [(index: Int, date: Date)] {
        NudgeSchedule.fireTimes(for: task.nudgePolicy.intensity).enumerated().compactMap { index, time in
            guard let fireDate = calendar.date(bySettingHour: time.hour ?? 0,
                                               minute: time.minute ?? 0,
                                               second: 0,
                                               of: now),
                  fireDate > now else { return nil }
            return (index, fireDate)
        }
    }

    /// A single reminder request for one of a task's fire times.
    private func makeRequest(for task: TaskItem,
                             fireDate: Date,
                             index: Int,
                             calendar: Calendar) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = nudgeBody(for: task)
        content.sound = .default

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let id = "\(Self.idPrefix)\(task.id.uuidString)-\(index)"

        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    /// One notification covering the tasks that couldn't fit in the budget.
    private func summaryRequest(droppedCount: Int,
                                fireDate: Date,
                                calendar: Calendar) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "More tasks due today"
        let plural = droppedCount == 1 ? "task" : "tasks"
        content.body = "\(droppedCount) more \(plural) due today — open ActuallyDidIt to see them."
        content.sound = .default

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        return UNNotificationRequest(identifier: "\(Self.idPrefix)summary", content: content, trigger: trigger)
    }

    /// Reminder body: the task's surfacing reason and estimate.
    private func nudgeBody(for task: TaskItem) -> String {
        "\(task.surfacingReason) · \(task.estimatedTimeLabel)"
    }

    /// Removes only the pending requests this scheduler owns.
    private func clearOwnedRequests() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
