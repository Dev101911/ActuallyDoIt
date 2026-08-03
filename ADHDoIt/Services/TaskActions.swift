//
//  TaskActions.swift
//  ADHDoIt
//
//  Central place for mutations that must preserve domain invariants — in particular the
//  "one task in focus at a time" rule.
//

import Foundation
import SwiftData

enum TaskActions {

    /// Default cooldown applied after a task is skipped, so the same thing isn't re-suggested
    /// immediately.
    static let skipCooldown: TimeInterval = 60 * 30 // 30 minutes

    /// Default snooze duration.
    static let defaultSnooze: TimeInterval = 60 * 15 // 15 minutes

    /// Makes `task` the single current task, clearing focus from any other task first.
    static func promoteToCurrent(_ task: TaskItem, in context: ModelContext) {
        clearAllFocus(in: context, except: task)
        task.focusStartedAt = Date()
        // Bringing a task into focus lifts any lingering snooze/cooldown.
        task.snoozedUntil = nil
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
            task.snoozedUntil = nil
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

    /// Snoozes the current task for the given interval and drops it out of focus.
    static func snooze(_ task: TaskItem,
                       for interval: TimeInterval = defaultSnooze,
                       in context: ModelContext) {
        task.snoozedUntil = Date().addingTimeInterval(interval)
        task.focusStartedAt = nil
        FocusActivityController.shared.reconcile(in: context)
        NudgeScheduler.shared.reconcile(in: context)
    }

    /// Skips the current task: drops focus and applies a short cooldown so it isn't immediately
    /// re-suggested.
    static func skip(_ task: TaskItem,
                     cooldown: TimeInterval = skipCooldown,
                     in context: ModelContext) {
        task.snoozedUntil = Date().addingTimeInterval(cooldown)
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
