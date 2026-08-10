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

    /// Marks a task complete. For a Chore this re-arms the next occurrence instead of ending it.
    nonisolated static func complete(_ task: TaskItem, in context: ModelContext) {
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
    }
}
