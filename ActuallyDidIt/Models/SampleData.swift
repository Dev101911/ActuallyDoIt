//
//  SampleData.swift
//  ActuallyDidIt
//
//  Mock data for testing in the simulator and SwiftUI previews.
//
//  Seeding runs in DEBUG builds only, and only when the store is empty, so it never duplicates
//  data or ships in a release build.
//

import Foundation
import SwiftData

enum SampleData {

    /// Freshly-built sample tasks. New instances are created on each call because a SwiftData
    /// `@Model` object can only belong to one context.
    static func makeTasks() -> [TaskItem] {
        let calendar = Calendar.current
        let today = Date()
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: today) ?? today
        }

        // MARK: One-off ToDos (no recurrence)
        let emailLandlord = TaskItem(
            title: "Email the landlord about the leak",
            notes: "Mention the kitchen tap and ask for a plumber.",
            estimatedMinutes: 15,
            dueDate: today,
            nudgePolicy: NudgePolicy(intensity: .persistent)
        )

        let bookDentist = TaskItem(
            title: "Book a dentist appointment",
            estimatedMinutes: 10,
            dueDate: day(-1), // overdue
            nudgePolicy: NudgePolicy(intensity: .relentless)
        )

        let renewPassport = TaskItem(
            title: "Renew passport",
            notes: "Photos are in the drawer.",
            estimatedMinutes: 45,
            dueDate: day(14)
        )

        let quickTidyInbox = TaskItem(
            title: "Reply to 3 emails",
            estimatedMinutes: 5
        )

        let readChapter = TaskItem(
            title: "Read one chapter of the report",
            estimatedMinutes: 30
        )

        let bigDeepClean = TaskItem(
            title: "Sort out the spare room",
            notes: "Boxes, old clothes, the lot.",
            estimatedMinutes: 120,
            nudgePolicy: NudgePolicy(intensity: .gentle)
        )

        // MARK: Recurring Chores
        let bins = TaskItem(
            title: "Take out the bins",
            estimatedMinutes: 5,
            dueDate: today,
            recurrenceRule: RecurrenceRule(frequency: .weekly, interval: 1),
            nudgePolicy: NudgePolicy(intensity: .persistent)
        )

        let waterPlants = TaskItem(
            title: "Water the plants",
            estimatedMinutes: 10,
            dueDate: day(1),
            recurrenceRule: RecurrenceRule(frequency: .everyNDays, interval: 3)
        )

        let dishes = TaskItem(
            title: "Wash the dishes",
            estimatedMinutes: 15,
            dueDate: today,
            recurrenceRule: RecurrenceRule(frequency: .daily, interval: 1)
        )

        let payRent = TaskItem(
            title: "Pay rent",
            estimatedMinutes: 5,
            dueDate: day(5),
            recurrenceRule: RecurrenceRule(frequency: .monthly, interval: 1),
            nudgePolicy: NudgePolicy(intensity: .relentless)
        )

        // A chore paused while away (e.g. on holiday), to show the paused state.
        let vacuum = TaskItem(
            title: "Vacuum the flat",
            estimatedMinutes: 20,
            dueDate: day(9),
            recurrenceRule: RecurrenceRule(frequency: .weekly, interval: 1)
        )
        vacuum.pausedUntil = day(9)

        // MARK: Already-completed ToDos (populate the Completed section)
        let paidBill = TaskItem(
            title: "Pay the electricity bill",
            estimatedMinutes: 5
        )
        paidBill.status = .completed
        paidBill.completedAt = day(-1)

        let calledMum = TaskItem(
            title: "Call Mum",
            estimatedMinutes: 20
        )
        calledMum.status = .completed
        calledMum.completedAt = day(-2)

        return [
            emailLandlord, bookDentist, renewPassport, quickTidyInbox, readChapter,
            bigDeepClean, bins, waterPlants, dishes, payRent, vacuum,
            paidBill, calledMum
        ]
    }

    /// Inserts the sample tasks into the given context if it has no tasks yet.
    @MainActor
    static func seedIfEmpty(_ context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<TaskItem>())) ?? 0
        guard existing == 0 else { return }
        for task in makeTasks() {
            context.insert(task)
        }
    }

    /// An in-memory container pre-populated with sample data, for SwiftUI previews.
    @MainActor
    static var previewContainer: ModelContainer = {
        let container = try! ModelContainer(
            for: TaskItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        for task in makeTasks() {
            container.mainContext.insert(task)
        }
        return container
    }()
}
