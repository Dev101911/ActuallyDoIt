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
                    }
                }

                Section("Nudge intensity") {
                    LabeledContent("Intensity", value: task.nudgePolicy.intensity.label)
                    Text(task.nudgePolicy.intensity.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
