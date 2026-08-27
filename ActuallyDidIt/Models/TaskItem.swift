//
//  TaskItem.swift
//  ActuallyDidIt
//
//  The core task model. (Named `TaskItem` rather than `Task` to avoid colliding with
//  Swift concurrency's `Task`.)
//
//  Designed to be CloudKit-compatible: every stored property has a default value and there are
//  no `@Attribute(.unique)` constraints, so the store can later sync via SwiftData + CloudKit
//  without a migration.
//

import Foundation
import SwiftData

@Model
final class TaskItem {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String?

    /// How long the user thinks this takes, in minutes. Powers the "Pick For Me" feature.
    var estimatedMinutes: Int = 15

    // Scheduling
    var dueDate: Date?
    /// When non-nil the task is a recurring **Chore**; when nil it is a one-off **ToDo**.
    var recurrenceRule: RecurrenceRule?

    /// Optional "alert before due" for due-date tasks: how long before `dueDate` to post a single
    /// reminder, in minutes. `nil` means no alert. For a date-only due date the value is a whole
    /// number of days (see `dueAlertFireDate`). Additive optional scalar so existing rows migrate
    /// cleanly.
    var dueAlertLeadMinutes: Int?

    /// When set to a future date the task (a **Chore**) is *paused* — e.g. while you're on holiday.
    /// A paused chore drops out of the actionable pool and stops nudging until this date passes.
    /// Additive optional scalar so existing rows migrate cleanly; only meaningful for chores.
    var pausedUntil: Date?

    // Nudge engine state
    var nudgePolicy: NudgePolicy = NudgePolicy.default
    var lastNudgedAt: Date?

    // Completion state
    var statusRaw: String = TaskStatus.pending.rawValue
    var completedAt: Date?
    var verificationMethodRaw: String = VerificationMethod.tapToConfirm.rawValue

    /// Non-nil marks this as the single current task (see the one-thing-at-a-time model).
    /// Only one task should have this set at any time; the invariant is enforced in app logic.
    var focusStartedAt: Date?

    var createdAt: Date = Date()

    init(title: String = "",
         notes: String? = nil,
         estimatedMinutes: Int = 15,
         dueDate: Date? = nil,
         dueAlertLeadMinutes: Int? = nil,
         recurrenceRule: RecurrenceRule? = nil,
         nudgePolicy: NudgePolicy = .default,
         verificationMethod: VerificationMethod = .tapToConfirm) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.estimatedMinutes = estimatedMinutes
        self.dueDate = dueDate
        self.dueAlertLeadMinutes = dueAlertLeadMinutes
        self.recurrenceRule = recurrenceRule
        self.nudgePolicy = nudgePolicy
        self.statusRaw = TaskStatus.pending.rawValue
        self.verificationMethodRaw = verificationMethod.rawValue
        self.createdAt = Date()
    }
}

// MARK: - Computed helpers

extension TaskItem {
    /// Typed accessor for the persisted status.
    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var verificationMethod: VerificationMethod {
        get { VerificationMethod(rawValue: verificationMethodRaw) ?? .tapToConfirm }
        set { verificationMethodRaw = newValue.rawValue }
    }

    /// A recurring Chore vs. a one-off ToDo.
    var isChore: Bool { recurrenceRule != nil }

    /// Whether the chore is currently paused — its resume date is still in the future.
    var isPaused: Bool {
        guard let pausedUntil else { return false }
        return pausedUntil > Date()
    }

    /// A short "Paused until 30 Aug" label while paused, or `nil` otherwise.
    var pausedUntilLabel: String? {
        guard isPaused, let pausedUntil else { return nil }
        return "Paused until \(pausedUntil.formatted(date: .abbreviated, time: .omitted))"
    }

    /// Whether this task's due date carries a specific time of day, as opposed to being pinned to
    /// the start of the day. Alerts are interpreted in minutes for timed due dates and in whole
    /// days for date-only ones.
    var dueDateHasTime: Bool {
        guard let dueDate else { return false }
        return Calendar.current.startOfDay(for: dueDate) != dueDate
    }

    /// When the "alert before due" reminder should fire, or `nil` when no alert is set.
    ///
    /// For a timed due date the lead is subtracted directly. For a date-only due date the lead is a
    /// whole number of days and the alert fires at 9 AM on the resulting day, so reminders land at a
    /// sensible hour rather than midnight.
    func dueAlertFireDate() -> Date? {
        guard let dueDate, let lead = dueAlertLeadMinutes else { return nil }
        let calendar = Calendar.current
        if dueDateHasTime {
            return dueDate.addingTimeInterval(TimeInterval(-lead * 60))
        }
        let day = calendar.date(byAdding: .day, value: -(lead / (24 * 60)),
                                to: calendar.startOfDay(for: dueDate)) ?? dueDate
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)
    }

    /// Whether the task is currently the user's single focus.
    var isCurrent: Bool { focusStartedAt != nil }

    /// True when the task is available to be worked on / suggested right now. A paused chore is
    /// deliberately unavailable until its pause ends.
    var isActionable: Bool {
        status == .pending && !isPaused
    }

    /// True when a pending task's due date has already passed (before today).
    /// A task due *today* counts as "due today", not overdue. Paused chores are never overdue.
    var isOverdue: Bool {
        guard status == .pending, !isPaused, let dueDate else { return false }
        return dueDate < Calendar.current.startOfDay(for: Date())
    }

    /// A short reason string explaining why a task is being surfaced.
    var surfacingReason: String {
        if let dueDate {
            if Calendar.current.isDateInToday(dueDate) { return "Due today" }
            if dueDate < Date() { return "Overdue" }
        }
        if isChore { return recurrenceRule?.summary ?? "Chore" }
        return "To do"
    }

    /// e.g. "15 min".
    var estimatedTimeLabel: String { "\(estimatedMinutes) min" }
}

// MARK: - Sorting

extension TaskItem {
    /// List ordering used by the task screens: overdue tasks first, then soonest due
    /// date/time. Tasks without a due date sort last.
    static func byOverdueThenDueDate(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.isOverdue != b.isOverdue { return a.isOverdue }
        let aDue = a.dueDate ?? .distantFuture
        let bDue = b.dueDate ?? .distantFuture
        return aDue < bDue
    }
}
