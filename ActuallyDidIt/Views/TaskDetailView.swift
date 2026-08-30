//
//  TaskDetailView.swift
//  ActuallyDidIt
//
//  An inline-editable view of a task's full details. Presented as a sheet when a task row is tapped.
//  Fields edit in place — there is no separate edit screen — and changes are written back to the task
//  (and nudges rescheduled) when the sheet closes. Shares its editing UI with `AddEditTaskView` via
//  `TaskFormFields`.
//

import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let task: TaskItem

    @State private var editor: TaskEditor

    init(task: TaskItem) {
        self.task = task
        _editor = State(initialValue: TaskEditor(task: task))
    }

    var body: some View {
        NavigationStack {
            Form {
                TaskFormFields(editor: editor)

                // Pause controls act on the persisted task immediately, so they key off the task's
                // saved state rather than the in-progress edits above.
                if task.isChore {
                    PauseChoreSection(task: task)
                }

                if task.status != .completed {
                    Section {
                        // Both buttons live in one cell so the List's first/last-cell corner
                        // rounding doesn't clip an individual button's corners asymmetrically.
                        VStack(spacing: 12) {
                            if !task.isCurrent {
                                StandardButton("Set as doing now", role: .secondary) {
                                    // `onDisappear` commits the edits and reschedules when the sheet closes.
                                    TaskActions.promoteToCurrent(task, in: modelContext)
                                    dismiss()
                                }
                            }

                            StandardButton("Mark as complete", role: .primary) {
                                // Commit any edits first so completion acts on the latest state, then
                                // complete. `onDisappear` still runs but re-applies the same values.
                                editor.apply(to: task)
                                TaskActions.complete(task, in: modelContext)
                                dismiss()
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                    }
                }
            }
            .navigationTitle("Task details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onDisappear(perform: commit)
        }
    }

    /// Write the current edits back onto the task and reschedule its nudges.
    private func commit() {
        editor.apply(to: task)
        NudgeScheduler.shared.reconcile(in: modelContext)
    }
}

// MARK: - Pause

/// The Pause controls shown for a Chore in the detail view: the current paused status when paused,
/// or quick "how long are you away" durations plus a custom resume date when it isn't.
private struct PauseChoreSection: View {
    @Environment(\.modelContext) private var modelContext
    let task: TaskItem

    /// The custom resume date, defaulting to a week out at the start of that day.
    @State private var customResumeDate = Calendar.current.date(
        byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: Date())
    ) ?? Date()

    /// The earliest a chore may resume — tomorrow.
    private var earliestResume: Date {
        Calendar.current.date(byAdding: .day, value: 1,
                              to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    var body: some View {
        if task.isPaused, let pausedUntil = task.pausedUntil {
            Section("Paused") {
                Label {
                    Text("Resumes \(pausedUntil.formatted(date: .abbreviated, time: .omitted))")
                } icon: {
                    Image(systemName: "pause.circle.fill")
                }
                .foregroundStyle(.secondary)

                StandardButton("Resume now", role: .secondary) {
                    TaskActions.resume(task, in: modelContext)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        } else {
            Section {
                DatePicker("Resume on", selection: $customResumeDate,
                           in: earliestResume..., displayedComponents: .date)
                Button {
                    TaskActions.pause(task,
                                      until: Calendar.current.startOfDay(for: customResumeDate),
                                      in: modelContext)
                } label: {
                    Label("Pause until this date", systemImage: "pause.circle")
                }
            } header: {
                Text("Pause")
            } footer: {
                Text("Pauses reminders while you're away — for example, on holiday. The chore returns on the day you choose.")
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
