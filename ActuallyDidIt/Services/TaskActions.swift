//
//  TaskActions.swift
//  ActuallyDidIt
//
//  Central place for mutations that must preserve domain invariants — in particular the
//  "one task in focus at a time" rule.
//

import Foundation
import SwiftData

enum TaskActions {

    /// Makes `task` the single current task, clearing focus from any other task first.
    static func promoteToCurrent(_ task: TaskItem, in context: ModelContext) {
        clearAllFocus(in: context, except: task)
        task.focusStartedAt = Date()
        FocusActivityController.shared.reconcile(in: context)
        NudgeScheduler.shared.reconcile(in: context)
    }

    /// Removes focus from every task except an optional one to keep.
    static func clearAllFocus(in context: ModelContext, except keep: TaskItem? = nil) {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.focusStartedAt != nil }
        )
        let focused = (try? context.fetch(descriptor)) ?? []
        for item in focused where item !== keep {
            item.focusStartedAt = nil
        }
        FocusActivityController.shared.reconcile(in: context)
    }

    /// Marks a task complete. For a Chore this re-arms the next occurrence instead of ending it.
    ///
    /// Note: verification is a later phase; for v1 this completes directly.
    static func complete(_ task: TaskItem, in context: ModelContext) {
        task.focusStartedAt = nil

        if let rule = task.recurrenceRule {
            // Chore: reschedule rather than finish.
            let base = task.dueDate ?? Date()
            task.dueDate = rule.nextDate(after: base)
            task.status = .pending
            task.completedAt = Date()
        } else {
            task.status = .completed
            task.completedAt = Date()
        }

        FocusActivityController.shared.reconcile(in: context)
        NudgeScheduler.shared.reconcile(in: context)
    }

    /// Reopens a completed task, moving it back to the pending pool.
    static func markUnfinished(_ task: TaskItem, in context: ModelContext) {
        task.status = .pending
        task.completedAt = nil
        NudgeScheduler.shared.reconcile(in: context)
    }

    /// Drops the task out of focus without completing it — used when the user can't do it right
    /// now. The task stays pending and eligible to be surfaced again.
    static func unfocus(_ task: TaskItem, in context: ModelContext) {
        task.focusStartedAt = nil
        FocusActivityController.shared.reconcile(in: context)
        NudgeScheduler.shared.reconcile(in: context)
    }

    /// Deletes a task. Routed through here (rather than calling `context.delete` directly) so
    /// that removing the currently focused task also ends its Live Activity.
    static func delete(_ task: TaskItem, in context: ModelContext) {
        context.delete(task)
        FocusActivityController.shared.reconcile(in: context)
        NudgeScheduler.shared.reconcile(in: context)
    }
}
