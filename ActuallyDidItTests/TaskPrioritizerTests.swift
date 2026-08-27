//
//  TaskPrioritizerTests.swift
//  ActuallyDidItTests
//
//  Verifies the ranking that drives the "Up next" preview and which task the nudge engine picks.
//

import Testing
import Foundation
@testable import ActuallyDidIt

@Suite("TaskPrioritizer ranking")
struct TaskPrioritizerTests {

    private func task(_ title: String,
                      due: Date? = nil,
                      intensity: NudgeIntensity = .gentle,
                      minutes: Int = 15) -> TaskItem {
        TaskItem(title: title,
                 estimatedMinutes: minutes,
                 dueDate: due,
                 nudgePolicy: NudgePolicy(intensity: intensity))
    }

    @Test("Soonest due date ranks first")
    func soonestDueWins() {
        let now = Date()
        let later = now.addingTimeInterval(3600)
        let undated = task("No date")
        let soon = task("Soon", due: now)
        let farther = task("Later", due: later)

        let ranked = TaskPrioritizer.upNext(from: [undated, farther, soon])
        #expect(ranked.map(\.title) == ["Soon", "Later", "No date"])
    }

    @Test("With equal due dates, higher nudge intensity ranks first")
    func intensityBreaksDueTie() {
        let due = Date()
        let gentle = task("Gentle", due: due, intensity: .gentle)
        let relentless = task("Relentless", due: due, intensity: .relentless)

        let ranked = TaskPrioritizer.upNext(from: [gentle, relentless])
        #expect(ranked.first?.title == "Relentless")
    }

    @Test("With equal due date and intensity, the quicker task ranks first")
    func shorterEstimateBreaksTie() {
        let due = Date()
        let quick = task("Quick", due: due, minutes: 5)
        let slow = task("Slow", due: due, minutes: 45)

        let ranked = TaskPrioritizer.upNext(from: [slow, quick])
        #expect(ranked.first?.title == "Quick")
    }

    @Test("The current task and completed tasks are excluded")
    func excludesCurrentAndCompleted() {
        let current = task("Doing now", due: Date())
        current.focusStartedAt = Date()
        let done = task("Done", due: Date())
        done.status = .completed
        let pending = task("Pending", due: Date())

        let ranked = TaskPrioritizer.upNext(from: [current, done, pending])
        #expect(ranked.map(\.title) == ["Pending"])
    }

    @Test("The result respects the requested limit")
    func honoursLimit() {
        let tasks = (0..<5).map { task("T\($0)", due: Date().addingTimeInterval(Double($0))) }
        #expect(TaskPrioritizer.upNext(from: tasks, limit: 2).count == 2)
    }

    @Test("upNext skips tasks in excludingIDs")
    func excludesRequestedIDs() {
        let now = Date()
        let a = task("A", due: now)
        let b = task("B", due: now.addingTimeInterval(60))

        let ranked = TaskPrioritizer.upNext(from: [a, b], excludingIDs: [a.id])
        #expect(ranked.map(\.title) == ["B"])
    }

    @Test("dueToday returns overdue then due-today, and nothing later")
    func dueTodayGrouping() {
        let calendar = Calendar.current
        let now = Date()
        let overdue = task("Overdue", due: calendar.date(byAdding: .day, value: -1, to: now))
        let today = task("Today", due: now)
        let tomorrow = task("Tomorrow", due: calendar.date(byAdding: .day, value: 1, to: now))
        let undated = task("Undated")

        let grouped = TaskPrioritizer.dueToday(from: [today, undated, tomorrow, overdue], now: now)
        #expect(grouped.map(\.title) == ["Overdue", "Today"])
    }

    @Test("dueToday excludes the current and completed tasks")
    func dueTodayExcludesCurrentAndCompleted() {
        let now = Date()
        let current = task("Doing now", due: now)
        current.focusStartedAt = now
        let done = task("Done", due: now)
        done.status = .completed
        let pending = task("Pending", due: now)

        let grouped = TaskPrioritizer.dueToday(from: [current, done, pending], now: now)
        #expect(grouped.map(\.title) == ["Pending"])
    }
}
