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

    /// The most real reminders we'll ever have pending at once. iOS silently drops anything past 64,
    /// so we budget the cap as: up to 61 reminders (and "before due" alerts), 2 morning digests, and
    /// the 64th slot reserved for the overflow summary notification.
    private static let safeBudget = 61

    /// Daily "check your list" digests fire at this time of day (minutes from midnight).
    private static let digestFireMinutes = 8 * 60 + 30   // 08:30

    /// Digests use their own identifier prefix so they survive the reconcile rebuild (which only
    /// tears down `idPrefix` requests) — that's what lets us leave an already-scheduled digest in
    /// place rather than recreating it every foreground.
    private static let digestIDPrefix = "digest-"

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
        Task { await performReconcile(in: context) }
    }

    /// The awaitable reconcile body. Foreground callers use the fire-and-forget `reconcile(in:)`
    /// above; a background task calls this directly so it can wait for the notification set to
    /// finish being written before marking itself complete.
    func performReconcile(in context: ModelContext) async {
        let requests = buildRequests(in: context)
        let digests = desiredDigestRequests(in: context, now: Date(), calendar: .current)

        await clearOwnedRequests()
        for request in requests {
            do {
                try await center.add(request)
            } catch {
                logger.error("Failed to schedule nudge: \(error.localizedDescription)")
            }
        }
        await reconcileDigests(desired: digests)
    }

    // MARK: - Request planning

    /// Computes the full set of notification requests for the current store state, honouring the
    /// notification budget. Pure and synchronous so the allocation logic is easy to reason about.
    private func buildRequests(in context: ModelContext) -> [UNNotificationRequest] {
        let calendar = Calendar.current
        let now = Date()

        // "Before due" alerts are scheduled first and independently of the due-today nudge logic:
        // they can fire days ahead, and each dated task gets at most one. They spend from the same
        // notification budget so the total stays under the iOS cap.
        let alerts = alertRequests(in: context, now: now, calendar: calendar)

        let eligible = eligibleTasks(in: context).sorted(by: TaskPrioritizer.isHigherPriority)

        // Pair each task with the fire times still ahead of us today, dropping tasks whose reminder
        // windows have all passed — those can't be scheduled regardless of budget.
        let candidates = eligible
            .map { (task: $0, slots: futureFireSlots(for: $0, now: now, calendar: calendar)) }
            .filter { !$0.slots.isEmpty }

        guard !candidates.isEmpty else { return alerts }

        // Spend the 63-reminder budget on alerts first, then nudges. Any tasks that don't fit are
        // folded into the overflow summary, which lives in the reserved 64th slot rather than being
        // carved out of the 63.
        let budget = max(Self.safeBudget - alerts.count, 0)

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

        return alerts + requests
    }

    /// One "before due" alert request per pending dated task whose alert time is still ahead of us.
    /// Independent of the due-today nudge window, so it can fire days in advance.
    private func alertRequests(in context: ModelContext,
                               now: Date,
                               calendar: Calendar) -> [UNNotificationRequest] {
        let pendingRaw = TaskStatus.pending.rawValue
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.statusRaw == pendingRaw }
        )
        let all = (try? context.fetch(descriptor)) ?? []

        return all.compactMap { task in
            guard !task.isCurrent,
                  !task.isPaused,
                  task.dueAlertLeadMinutes != nil,
                  let fireDate = task.dueAlertFireDate(),
                  fireDate > now else { return nil }
            return makeAlertRequest(for: task, fireDate: fireDate, calendar: calendar)
        }
    }

    /// The "before due" alert notification for a single task.
    private func makeAlertRequest(for task: TaskItem,
                                  fireDate: Date,
                                  calendar: Calendar) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = alertBody(for: task)
        content.sound = .default
        content.userInfo = [NotificationRouter.taskIDKey: task.id.uuidString]

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let id = "\(Self.idPrefix)alert-\(task.id.uuidString)"

        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    /// Alert body: when the task is actually due.
    private func alertBody(for task: TaskItem) -> String {
        guard let due = task.dueDate else { return "Due soon" }
        let when = task.dueDateHasTime
            ? due.formatted(date: .abbreviated, time: .shortened)
            : due.formatted(date: .abbreviated, time: .omitted)
        return "Due \(when)"
    }

    // MARK: - Morning digests

    /// The two digests we want pending: tomorrow (day+1) and the day after (day+2), each at 08:30.
    /// These gently prompt the user to reopen the app — which triggers another `reconcile` and keeps
    /// the rolling notification set fresh — with a brief count of what's due that morning.
    private func desiredDigestRequests(in context: ModelContext,
                                       now: Date,
                                       calendar: Calendar) -> [UNNotificationRequest] {
        [1, 2].compactMap { dayOffset in
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now),
                  let fireDate = calendar.date(bySettingHour: Self.digestFireMinutes / 60,
                                               minute: Self.digestFireMinutes % 60,
                                               second: 0,
                                               of: day) else { return nil }
            return digestRequest(for: fireDate, in: context, calendar: calendar)
        }
    }

    /// A single morning-digest request for the given fire date.
    private func digestRequest(for fireDate: Date,
                               in context: ModelContext,
                               calendar: Calendar) -> UNNotificationRequest {
        let count = dueCount(on: fireDate, in: context, calendar: calendar)

        let content = UNMutableNotificationContent()
        content.title = "Good morning"
        content.body = digestBody(dueCount: count)
        content.sound = .default

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let id = Self.digestIDPrefix + dayKey(for: fireDate, calendar: calendar)

        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    /// Gentle "look at your list" copy, with a count when there's anything on the plate.
    private func digestBody(dueCount count: Int) -> String {
        switch count {
        case 0: return "Take a look at what's on your list for today."
        case 1: return "You have 1 task due — take a look at what's on your list for today."
        default: return "You have \(count) tasks due — take a look at what's on your list for today."
        }
    }

    /// How many pending, not-currently-active tasks are due on or before the given day (i.e. due
    /// that day or already overdue). Computed from the current store snapshot, so recurring chores
    /// are only counted at their present occurrence — a good-enough hint, not a promise.
    private func dueCount(on day: Date, in context: ModelContext, calendar: Calendar) -> Int {
        guard let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: day) else { return 0 }
        let pendingRaw = TaskStatus.pending.rawValue
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.statusRaw == pendingRaw }
        )
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter { task in
            guard !task.isCurrent, !task.isPaused, let due = task.dueDate else { return false }
            return due <= endOfDay
        }.count
    }

    /// A stable per-calendar-day identifier suffix, so a given day's digest keeps the same id across
    /// reconciles and we can tell whether it's already scheduled.
    private func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// Ensures exactly the two desired digests are pending: prunes any stale digest that's no longer
    /// a target (e.g. yesterday's, once a day rolls over) and adds only the targets not already
    /// scheduled — leaving existing ones untouched so we don't recreate them on every foreground.
    private func reconcileDigests(desired: [UNNotificationRequest]) async {
        let pending = await center.pendingNotificationRequests()
        let pendingIDs = Set(pending.map(\.identifier))
        let desiredIDs = Set(desired.map(\.identifier))

        let staleIDs = pendingIDs.filter { $0.hasPrefix(Self.digestIDPrefix) && !desiredIDs.contains($0) }
        if !staleIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(staleIDs))
        }

        for request in desired where !pendingIDs.contains(request.identifier) {
            do {
                try await center.add(request)
            } catch {
                logger.error("Failed to schedule digest: \(error.localizedDescription)")
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
            guard !task.isPaused else { return false }                 // paused chore (e.g. holiday)
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
        NudgeSchedule.fireTimes(for: task.nudgePolicy).enumerated().compactMap { index, time in
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
        content.userInfo = [NotificationRouter.taskIDKey: task.id.uuidString]

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

    /// Immediately cancels every notification this scheduler owns for a single task — its
    /// reminders and its "before due" alert — both those still pending *and* any that have already
    /// fired and are sitting in Notification Center.
    ///
    /// This is the targeted counterpart to `reconcile`: because the notification identifiers are
    /// deterministic (derived from the task id and its nudge policy) it needs no async fetch and
    /// takes effect at once. That matters when a task is completed or deleted right before the app
    /// is suspended, when the fire-and-forget `reconcile` rebuild might not get to run — the task
    /// stops nudging regardless. Clearing the delivered copies also pulls stale alerts out of the
    /// pull-down shade so a finished task doesn't keep showing there.
    func cancelNotifications(for task: TaskItem) {
        let id = task.id.uuidString
        var identifiers = ["\(Self.idPrefix)alert-\(id)"]
        let slotCount = NudgeSchedule.fireTimes(for: task.nudgePolicy).count
        identifiers += (0..<slotCount).map { "\(Self.idPrefix)\(id)-\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    /// Removes only the pending requests this scheduler owns.
    private func clearOwnedRequests() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
