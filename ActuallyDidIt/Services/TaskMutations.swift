//
//  TaskMutations.swift
//  ActuallyDidIt
//
//  Pure, side-effect-free store mutations that enforce the task domain invariants (in particular
//  the "one task in focus at a time" rule and Chore re-arming on completion).
//
//  This layer exists so the exact same rules run whether a change originates in the app (via
//  `TaskActions`, which wraps these and adds Live Activity / notification side effects) or in the
//  widget extension (via the widget App Intents, which can't touch app-only services). It touches
//  only the `ModelContext`.
//
//  IMPORTANT: this file must be a member of BOTH the `ActuallyDidIt` app target and the
//  `FocusActivityExtension` target.
//

import Foundation
import SwiftData

enum TaskMutations {

    /// Makes `task` the single current task, clearing focus from any other task first.
    nonisolated static func setCurrent(_ task: TaskItem, in context: ModelContext) {
        clearAllFocus(in: context, except: task)
        task.focusStartedAt = Date()
    }

    /// Removes focus from every task except an optional one to keep.
    nonisolated static func clearAllFocus(in context: ModelContext, except keep: TaskItem? = nil) {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.focusStartedAt != nil }
        )
        let focused = (try? context.fetch(descriptor)) ?? []
        for item in focused where item !== keep {
            item.focusStartedAt = nil
        }
    }

    /// Pauses a Chore until `date` — it stops nudging and drops out of the actionable pool until
    /// then (used for holidays). If an occurrence would otherwise fall during the pause, the due
    /// date is advanced to the next occurrence on or after the resume day, so the chore returns
    /// cleanly on schedule rather than as a pile of overdue work.
    nonisolated static func pause(_ task: TaskItem, until date: Date, in context: ModelContext) {
        task.pausedUntil = date
        task.focusStartedAt = nil

        if let rule = task.recurrenceRule {
            let resumeDay = Calendar.current.startOfDay(for: date)
            if let due = task.dueDate, due < resumeDay {
                task.dueDate = rule.firstDueDate(from: resumeDay)
            }
        }
    }

    /// Resumes a paused Chore immediately, re-anchoring its next occurrence to the soonest one on
    /// or after today so it returns to the active list on schedule rather than overdue or stuck at
    /// the (now-cancelled) pause date.
    nonisolated static func resume(_ task: TaskItem, in context: ModelContext) {
        task.pausedUntil = nil
        if let rule = task.recurrenceRule {
            task.dueDate = rule.firstDueDate(from: Date())
        }
    }

    /// Marks a task complete. For a Chore this re-arms the next occurrence instead of ending it.
    nonisolated static func complete(_ task: TaskItem, in context: ModelContext) {
        task.focusStartedAt = nil
        // Completing a chore clears any pause so the next occurrence isn't treated as paused.
        task.pausedUntil = nil

        if let rule = task.recurrenceRule, let next = rule.nextDate(after: task.dueDate ?? Date()) {
            // Chore with more occurrences to come: reschedule rather than finish.
            task.dueDate = next
            task.status = .pending
            task.completedAt = Date()
        } else {
            // A one-off ToDo, or a chore that has reached its end date: finish it.
            task.status = .completed
            task.completedAt = Date()
        }
    }
}
