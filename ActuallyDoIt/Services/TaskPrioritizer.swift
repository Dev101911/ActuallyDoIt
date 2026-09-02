//
//  TaskPrioritizer.swift
//  ActuallyDoIt
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

    /// The actionable tasks due tomorrow — the "Tomorrow" heads-up group. Excludes the current
    /// task. Includes chores whose next occurrence falls tomorrow. Sorted soonest-due first.
    static func dueTomorrow(from tasks: [TaskItem], now: Date = Date()) -> [TaskItem] {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return [] }
        return tasks
            .filter { task in
                guard task.isActionable, !task.isCurrent, let due = task.dueDate else { return false }
                return calendar.isDate(due, inSameDayAs: tomorrow)
            }
            .sorted(by: TaskItem.byOverdueThenDueDate)
    }

    /// The top actionable tasks to preview, ranked by urgency. Excludes the current task and any
    /// tasks in `excludingIDs` (used to keep "Up next" from repeating what's already under "Today"
    /// or "Tomorrow").
    static func upNext(from tasks: [TaskItem], excludingIDs: Set<UUID> = [], limit: Int = 3) -> [TaskItem] {
        tasks
            .filter { task in
                guard task.isActionable, !task.isCurrent, !excludingIDs.contains(task.id) else {
                    return false
                }
                // Chores stay hidden until their occurrence is actually due — a weekly chore
                // shouldn't fill "Up next" all week, only once it's due today (or overdue).
                if task.isChore, !task.isDueTodayOrOverdue { return false }
                return true
            }
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
