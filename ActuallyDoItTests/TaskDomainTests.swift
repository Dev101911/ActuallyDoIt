//
//  TaskDomainTests.swift
//  ActuallyDoItTests
//
//  Pure model logic: TaskItem's computed helpers and RecurrenceRule's date maths. No store needed.
//

import Testing
import Foundation
@testable import ActuallyDoIt

@Suite("TaskItem helpers")
struct TaskItemHelperTests {

    @Test("A task with a recurrence rule is a Chore; without one it is a ToDo")
    func choreVsTodo() {
        let todo = TaskItem(title: "One-off")
        let chore = TaskItem(title: "Repeat", recurrenceRule: RecurrenceRule(frequency: .weekly))
        #expect(!todo.isChore)
        #expect(chore.isChore)
    }

    @Test("isCurrent tracks focusStartedAt")
    func isCurrentTracksFocus() {
        let task = TaskItem(title: "Focus")
        #expect(!task.isCurrent)
        task.focusStartedAt = Date()
        #expect(task.isCurrent)
    }

    @Test("Only pending tasks are actionable")
    func actionableWhenPending() {
        let task = TaskItem(title: "Do it")
        #expect(task.isActionable)
        task.status = .completed
        #expect(!task.isActionable)
    }

    @Test("Status and verification accessors mirror their raw storage")
    func typedAccessorsMirrorRawValues() {
        let task = TaskItem(title: "Accessors")
        task.status = .awaitingVerification
        #expect(task.statusRaw == TaskStatus.awaitingVerification.rawValue)
        task.verificationMethod = .delayedRecheck
        #expect(task.verificationMethodRaw == VerificationMethod.delayedRecheck.rawValue)
    }

    @Test("Unknown raw values fall back to safe defaults")
    func rawValueFallbacks() {
        let task = TaskItem(title: "Legacy row")
        task.statusRaw = "somethingRemovedInAFutureVersion"
        task.verificationMethodRaw = "gone"
        #expect(task.status == .pending)
        #expect(task.verificationMethod == .tapToConfirm)
    }

    @Test("An overdue task surfaces as Overdue; a future-dated one as its reason")
    func surfacingReason() {
        let overdue = TaskItem(title: "Late", dueDate: Date().addingTimeInterval(-86_400))
        #expect(overdue.surfacingReason == "Overdue")

        let chore = TaskItem(title: "Weekly", recurrenceRule: RecurrenceRule(frequency: .weekly))
        #expect(chore.surfacingReason == "Weekly")
    }

    @Test("estimatedTimeLabel reads as minutes")
    func estimatedTimeLabel() {
        #expect(TaskItem(title: "x", estimatedMinutes: 30).estimatedTimeLabel == "30 min")
    }
}

@Suite("Task tags")
struct TaskTagTests {

    @Test("normalize trims whitespace and rejects empty input")
    func normalize() {
        #expect(TaskItem.normalize("  Work  ") == "Work")
        #expect(TaskItem.normalize("   ") == nil)
        #expect(TaskItem.normalize("") == nil)
    }

    @Test("allTags de-dupes case-insensitively and sorts alphabetically")
    func allTags() {
        let tasks = [
            TaskItem(title: "a", tags: ["Work", "Home"]),
            TaskItem(title: "b", tags: ["work", "Admin"]),
            TaskItem(title: "c", tags: []),
        ]
        // "work"/"Work" collapse to the first-seen "Work"; result is sorted.
        #expect(TaskItem.allTags(from: tasks) == ["Admin", "Home", "Work"])
    }

    @Test("An empty filter matches every task")
    func emptyFilterMatchesEverything() {
        #expect(TaskItem(title: "untagged").matchesTagFilter([]))
        #expect(TaskItem(title: "tagged", tags: ["Work"]).matchesTagFilter([]))
    }

    @Test("A non-empty filter matches tasks sharing any selected tag (OR), case-insensitively")
    func filterUsesOrSemantics() {
        let task = TaskItem(title: "x", tags: ["Home"])
        #expect(task.matchesTagFilter(["Work", "home"]))   // matches on Home (case-insensitive)
        #expect(!task.matchesTagFilter(["Work", "Admin"])) // shares none
    }
}

@Suite("RecurrenceRule")
struct RecurrenceRuleTests {

    @Test("Interval is clamped to at least 1")
    func intervalClamped() {
        #expect(RecurrenceRule(frequency: .daily, interval: 0).interval == 1)
        #expect(RecurrenceRule(frequency: .daily, interval: -5).interval == 1)
    }

    @Test("nextDate advances by the correct calendar unit and interval",
          arguments: [
            (RecurrenceRule.Frequency.daily, Calendar.Component.day, 1),
            (.everyNDays, .day, 4),
            (.weekly, .weekOfYear, 2),
            (.monthly, .month, 3),
          ])
    func nextDateAdvances(frequency: RecurrenceRule.Frequency,
                          component: Calendar.Component,
                          interval: Int) throws {
        let base = Date()
        let rule = RecurrenceRule(frequency: frequency, interval: interval)
        let expected = Calendar.current.date(byAdding: component, value: interval, to: base)
        #expect(rule.nextDate(after: base) == expected)
    }

    @Test("Summaries read naturally for singular and plural intervals")
    func summaries() {
        #expect(RecurrenceRule(frequency: .daily, interval: 1).summary == "Daily")
        #expect(RecurrenceRule(frequency: .daily, interval: 3).summary == "Every 3 days")
        #expect(RecurrenceRule(frequency: .weekly, interval: 1).summary == "Weekly")
        #expect(RecurrenceRule(frequency: .weekly, interval: 2).summary == "Every 2 weeks")
        #expect(RecurrenceRule(frequency: .monthly, interval: 1).summary == "Monthly")
    }
}
