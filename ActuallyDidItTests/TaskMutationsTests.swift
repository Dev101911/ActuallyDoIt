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
}
