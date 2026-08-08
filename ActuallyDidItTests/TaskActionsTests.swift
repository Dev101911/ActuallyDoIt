//
//  TaskActionsTests.swift
//  ActuallyDidItTests
//
//  Covers the domain invariants enforced by `TaskActions` — most importantly the
//  "one task in focus at a time" rule and correct completion behaviour for ToDos vs. Chores.
//  Runs against an in-memory store so no data touches disk.
//

import Testing
import SwiftData
import Foundation
@testable import ActuallyDidIt

@MainActor
@Suite("TaskActions invariants")
struct TaskActionsTests {

    /// A throwaway in-memory container so each test starts from an empty store.
    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    @Test("Promoting a task to current clears focus from any other task")
    func promoteEnforcesSingleFocus() throws {
        let context = try makeContext()
        let first = TaskItem(title: "First")
        let second = TaskItem(title: "Second")
        context.insert(first)
        context.insert(second)

        TaskActions.promoteToCurrent(first, in: context)
        #expect(first.isCurrent)
        #expect(!second.isCurrent)

        TaskActions.promoteToCurrent(second, in: context)
        #expect(second.isCurrent)
        #expect(!first.isCurrent, "Promoting a second task must drop focus from the first")
    }

    @Test("Completing a one-off ToDo marks it completed and drops focus")
    func completeTodoFinishesIt() throws {
        let context = try makeContext()
        let todo = TaskItem(title: "One-off")
        context.insert(todo)
        TaskActions.promoteToCurrent(todo, in: context)

        TaskActions.complete(todo, in: context)

        #expect(todo.status == .completed)
        #expect(todo.completedAt != nil)
        #expect(!todo.isCurrent)
    }

    @Test("Completing a Chore reschedules it to the next occurrence and stays pending")
    func completeChoreReschedules() throws {
        let context = try makeContext()
        let start = Date()
        let chore = TaskItem(title: "Water plants",
                             dueDate: start,
                             recurrenceRule: RecurrenceRule(frequency: .daily, interval: 3))
        context.insert(chore)

        TaskActions.complete(chore, in: context)

        #expect(chore.status == .pending, "A completed Chore re-arms rather than finishing")
        let expectedNext = Calendar.current.date(byAdding: .day, value: 3, to: start)
        #expect(chore.dueDate == expectedNext)
    }

    @Test("Marking a task unfinished returns it to the pending pool")
    func markUnfinishedReopens() throws {
        let context = try makeContext()
        let todo = TaskItem(title: "Reopen me")
        context.insert(todo)
        TaskActions.complete(todo, in: context)
        #expect(todo.status == .completed)

        TaskActions.markUnfinished(todo, in: context)
        #expect(todo.status == .pending)
        #expect(todo.completedAt == nil)
    }

    @Test("Unfocusing keeps the task pending and actionable")
    func unfocusLeavesTaskActionable() throws {
        let context = try makeContext()
        let todo = TaskItem(title: "Not now")
        context.insert(todo)
        TaskActions.promoteToCurrent(todo, in: context)

        TaskActions.unfocus(todo, in: context)
        #expect(!todo.isCurrent)
        #expect(todo.status == .pending)
        #expect(todo.isActionable)
    }

    @Test("Deleting a task removes it from the store")
    func deleteRemovesTask() throws {
        let context = try makeContext()
        let todo = TaskItem(title: "Delete me")
        context.insert(todo)

        TaskActions.delete(todo, in: context)

        let remaining = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(remaining.isEmpty)
    }
}
