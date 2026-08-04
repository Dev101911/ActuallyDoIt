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

    // Nudge engine state
    var nudgePolicy: NudgePolicy = NudgePolicy.default
    var lastNudgedAt: Date?
    /// While set to a future date the task is suppressed (snoozed or in a post-skip cooldown).
    var snoozedUntil: Date?

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
         recurrenceRule: RecurrenceRule? = nil,
         nudgePolicy: NudgePolicy = .default,
         verificationMethod: VerificationMethod = .tapToConfirm) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.estimatedMinutes = estimatedMinutes
        self.dueDate = dueDate
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

    /// Whether the task is currently the user's single focus.
    var isCurrent: Bool { focusStartedAt != nil }

    /// True when the task is available to be worked on / suggested right now.
    var isActionable: Bool {
        guard status == .pending else { return false }
        if let snoozedUntil, snoozedUntil > Date() { return false }
        return true
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
