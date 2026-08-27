//
//  TaskPrioritizer.swift
//  ActuallyDidIt
//
//  Ranks tasks for the "Up next" preview on the Now screen: soonest-due and highest-intensity
//  work floats to the top. Kept small and pure so it stays easy to reason about (and test).
//

import Foundation

enum TaskPrioritizer {

    /// The overdue and due-today actionable tasks — the time-critical group shown under "Today".
    /// Overdue tasks sort first, then soonest due. Excludes the current task.
    static func dueToday(from tasks: [TaskItem], now: Date = Date()) -> [TaskItem] {
        let calendar = Calendar.current
        return tasks
            .filter { task in
                guard task.isActionable, !task.isCurrent, let due = task.dueDate else { return false }
                return task.isOverdue || calendar.isDate(due, inSameDayAs: now)
            }
            .sorted(by: TaskItem.byOverdueThenDueDate)
    }

    /// The top actionable tasks to preview, ranked by urgency. Excludes the current task and any
    /// tasks in `excludingIDs` (used to keep "Up next" from repeating what's already under "Today").
    static func upNext(from tasks: [TaskItem], excludingIDs: Set<UUID> = [], limit: Int = 3) -> [TaskItem] {
        tasks
            .filter { $0.isActionable && !$0.isCurrent && !excludingIDs.contains($0.id) }
            .sorted(by: isHigherPriority)
            .prefix(limit)
            .map { $0 }
    }

    /// Sort predicate: soonest due date first, then higher nudge intensity, then quicker tasks.
    static func isHigherPriority(_ a: TaskItem, _ b: TaskItem) -> Bool {
        let aDue = a.dueDate ?? .distantFuture
        let bDue = b.dueDate ?? .distantFuture
        if aDue != bDue { return aDue < bDue }

        let aRank = a.nudgePolicy.intensity.rank
        let bRank = b.nudgePolicy.intensity.rank
        if aRank != bRank { return aRank > bRank }

        return a.estimatedMinutes < b.estimatedMinutes
    }
}
