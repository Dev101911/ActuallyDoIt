//
//  TaskMutationsTests.swift
//  ActuallyDidItTests
//
//  Covers the pure, side-effect-free store mutations in `TaskMutations` — the layer shared by the
//  app (`TaskActions`) and the widget's App Intents. Runs against an in-memory store so no data
//  touches disk, and asserts only on store state (no Live Activity / notification side effects).
//

import Testing
import SwiftData
import Foundation
@testable import ActuallyDidIt

@MainActor
@Suite("TaskMutations invariants")
struct TaskMutationsTests {

    /// A throwaway in-memory container so each test starts from an empty store.
    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    @Test("setCurrent enforces a single focused task")
    func setCurrentEnforcesSingleFocus() throws {
        let context = try makeContext()
        let first = TaskItem(title: "First")
        let second = TaskItem(title: "Second")
        context.insert(first)
        context.insert(second)

        TaskMutations.setCurrent(first, in: context)
        #expect(first.isCurrent)
        #expect(!second.isCurrent)

        TaskMutations.setCurrent(second, in: context)
        #expect(second.isCurrent)
        #expect(!first.isCurrent, "Focusing a second task must drop focus from the first")
    }

    @Test("clearAllFocus drops focus from every task except the one kept")
    func clearAllFocusRespectsKeep() throws {
        let context = try makeContext()
        let kept = TaskItem(title: "Keep")
        let other = TaskItem(title: "Other")
        context.insert(kept)
        context.insert(other)
        TaskMutations.setCurrent(kept, in: context)
        other.focusStartedAt = Date()

        TaskMutations.clearAllFocus(in: context, except: kept)
        #expect(kept.isCurrent)
        #expect(!other.isCurrent)
    }

    @Test("complete marks a one-off ToDo completed and drops focus")
    func completeTodoFinishesIt() throws {
        let context = try makeContext()
        let todo = TaskItem(title: "One-off")
        context.insert(todo)
        TaskMutations.setCurrent(todo, in: context)

        TaskMutations.complete(todo, in: context)

        #expect(todo.status == .completed)
        #expect(todo.completedAt != nil)
        #expect(!todo.isCurrent)
    }

    @Test("complete reschedules a Chore and keeps it pending")
    func completeChoreReschedules() throws {
        let context = try makeContext()
        let start = Date()
        let chore = TaskItem(title: "Water plants",
                             dueDate: start,
                             recurrenceRule: RecurrenceRule(frequency: .daily, interval: 3))
        context.insert(chore)

        TaskMutations.complete(chore, in: context)

        #expect(chore.status == .pending, "A completed Chore re-arms rather than finishing")
        let expectedNext = Calendar.current.date(byAdding: .day, value: 3, to: start)
        #expect(chore.dueDate == expectedNext)
    }

    @Test("pause marks a Chore paused and drops focus")
    func pauseMarksChorePaused() throws {
        let context = try makeContext()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let resume = calendar.date(byAdding: .day, value: 7, to: today)!
        let chore = TaskItem(title: "Vacuum",
                             dueDate: today,
                             recurrenceRule: RecurrenceRule(frequency: .weekly, interval: 1))
        context.insert(chore)
        TaskMutations.setCurrent(chore, in: context)

        TaskMutations.pause(chore, until: resume, in: context)

        #expect(chore.isPaused)
        #expect(!chore.isCurrent, "Pausing drops the chore out of focus")
        #expect(!chore.isActionable, "A paused chore is not actionable")
    }

    @Test("pause rolls a due-during-pause chore forward to the resume day")
    func pauseRollsDueForward() throws {
        let context = try makeContext()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let resume = calendar.date(byAdding: .day, value: 7, to: today)!
        // Due today — during the pause window — so it should be pushed to the resume day.
        let chore = TaskItem(title: "Vacuum",
                             dueDate: today,
                             recurrenceRule: RecurrenceRule(frequency: .daily, interval: 1))
        context.insert(chore)

        TaskMutations.pause(chore, until: resume, in: context)

        #expect(chore.dueDate == resume, "The next occurrence lands on the resume day")
    }

    @Test("pause leaves an already-later due date untouched")
    func pauseKeepsLaterDueDate() throws {
        let context = try makeContext()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let resume = calendar.date(byAdding: .day, value: 3, to: today)!
        let laterDue = calendar.date(byAdding: .day, value: 10, to: today)!
        let chore = TaskItem(title: "Vacuum",
                             dueDate: laterDue,
                             recurrenceRule: RecurrenceRule(frequency: .weekly, interval: 1))
        context.insert(chore)

        TaskMutations.pause(chore, until: resume, in: context)

        #expect(chore.dueDate == laterDue, "A due date already past the pause is left alone")
    }

    @Test("resume clears the pause and re-anchors the due date to today")
    func resumeClearsPause() throws {
        let context = try makeContext()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let resume = calendar.date(byAdding: .day, value: 7, to: today)!
        let chore = TaskItem(title: "Vacuum",
                             dueDate: today,
                             recurrenceRule: RecurrenceRule(frequency: .daily, interval: 1))
        context.insert(chore)
        TaskMutations.pause(chore, until: resume, in: context)

        TaskMutations.resume(chore, in: context)

        #expect(!chore.isPaused)
        #expect(chore.isActionable)
        #expect(chore.dueDate == today, "Resuming a daily chore brings it back due today")
    }

    @Test("completing a paused Chore clears the pause")
    func completeClearsPause() throws {
        let context = try makeContext()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let resume = calendar.date(byAdding: .day, value: 7, to: today)!
        let chore = TaskItem(title: "Vacuum",
                             dueDate: today,
                             recurrenceRule: RecurrenceRule(frequency: .weekly, interval: 1))
        context.insert(chore)
        TaskMutations.pause(chore, until: resume, in: context)

        TaskMutations.complete(chore, in: context)

        #expect(chore.pausedUntil == nil)
        #expect(!chore.isPaused)
    }
}
