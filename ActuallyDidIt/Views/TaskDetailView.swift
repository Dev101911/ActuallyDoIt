//
//  TaskDetailView.swift
//  ActuallyDidIt
//
//  A read-only view of a task's full details, mirroring the layout of `AddEditTaskView`.
//  Presented as a sheet when a task row is tapped. An Edit button opens the editable form.
//

import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let task: TaskItem

    @State private var editingTask: TaskItem?

    /// Whether the stored due date carries a specific time (vs. being pinned to midnight).
    private var dueHasTime: Bool {
        guard let dueDate = task.dueDate else { return false }
        return Calendar.current.startOfDay(for: dueDate) != dueDate
    }

    /// A human-readable summary of the "before due" alert, or `nil` when none is set — how far ahead
    /// it fires, e.g. "1 day before".
    private var alertSummary: String? {
        guard let lead = task.dueAlertLeadMinutes else { return nil }
        return leadLabel(minutes: lead)
    }

    /// Turns a stored alert lead into the same wording used in the editor.
    private func leadLabel(minutes: Int) -> String? {
        let day = 24 * 60
        if dueHasTime {
            switch minutes {
            case 0: return "At time due"
            case day: return "1 day before"
            case let m where m % 60 == 0: return "\(m / 60) hour\(m / 60 == 1 ? "" : "s") before"
            default: return "\(minutes) minute\(minutes == 1 ? "" : "s") before"
            }
        } else {
            switch minutes {
            case 0: return "On the day"
            case 7 * day: return "1 week before"
            default:
                let days = minutes / day
                return "\(days) day\(days == 1 ? "" : "s") before"
            }
        }
    }

    /// A human-readable summary of when this task's nudges fire, honouring any per-task override.
    /// Relentless is summarised as an hourly window rather than listing every hour.
    private var nudgeTimesSummary: String {
        func label(_ minutes: Int) -> String {
            NudgeSchedule.date(fromMinutes: minutes).formatted(date: .omitted, time: .shortened)
        }
        let minutes = NudgeSchedule.fireMinutes(for: task.nudgePolicy)
        switch task.nudgePolicy.intensity {
        case .gentle, .persistent:
            return minutes.map(label).joined(separator: ", ")
        case .relentless:
            guard let first = minutes.first, let last = minutes.last else { return "—" }
            return "Hourly, \(label(first))–\(label(last))"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    LabeledContent("Title", value: task.title)
                    if let notes = task.notes, !notes.isEmpty {
                        LabeledContent("Notes") {
                            Text(notes)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                Section("Time needed") {
                    LabeledContent("Estimated time", value: task.estimatedTimeLabel)
                }

                if task.isChore, let rule = task.recurrenceRule {
                    Section("Chore (recurring)") {
                        LabeledContent("Repeats", value: rule.summary)
                    }
                }

                if !task.isChore, let dueDate = task.dueDate {
                    Section("Deadline") {
                        LabeledContent(
                            "Due",
                            value: dueDate.formatted(
                                date: .abbreviated,
                                time: dueHasTime ? .shortened : .omitted
                            )
                        )
                        if let alertSummary {
                            LabeledContent("Alert", value: alertSummary)
                        }
                    }
                }

                Section("Nudge intensity") {
                    LabeledContent("Intensity", value: task.nudgePolicy.intensity.label)
                    LabeledContent("Times", value: nudgeTimesSummary)
                }

                if !task.isCurrent {
                    Section {
                        Button {
                            TaskActions.promoteToCurrent(task, in: modelContext)
                            dismiss()
                        } label: {
                            Text("Set as doing now")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }
            }
            .navigationTitle("Task details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Edit") { editingTask = task }
                }
            }
            .sheet(item: $editingTask) { task in
                AddEditTaskView(task: task)
                    .interactiveDismissDisabled()
            }
        }
    }
}

#Preview {
    TaskDetailView(task: TaskItem(
        title: "Sample task",
        notes: "A few extra details about this task.",
        estimatedMinutes: 30,
        dueDate: Date()
    ))
    .modelContainer(SampleData.previewContainer)
}
