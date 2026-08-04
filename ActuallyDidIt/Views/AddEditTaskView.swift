//
//  AddEditTaskView.swift
//  ActuallyDidIt
//
//  Create or edit a task. A task with a recurrence is a Chore; without one it's a ToDo.
//

import SwiftUI
import SwiftData

struct AddEditTaskView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// The task being edited, or nil when creating a new one.
    private let existingTask: TaskItem?

    @State private var title: String
    @State private var notes: String
    @State private var estimatedMinutes: Int

    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var includeTime: Bool

    @State private var isRecurring: Bool
    @State private var frequency: RecurrenceRule.Frequency
    @State private var interval: Int

    @State private var intensity: NudgeIntensity

    init(task: TaskItem? = nil) {
        self.existingTask = task
        _title = State(initialValue: task?.title ?? "")
        _notes = State(initialValue: task?.notes ?? "")
        _estimatedMinutes = State(initialValue: task?.estimatedMinutes ?? 15)
        _hasDueDate = State(initialValue: task?.dueDate != nil)
        _dueDate = State(initialValue: task?.dueDate ?? Date())
        // Treat a stored due date that isn't pinned to midnight as having a specific time.
        _includeTime = State(initialValue: task?.dueDate.map { Calendar.current.startOfDay(for: $0) != $0 } ?? false)
        _isRecurring = State(initialValue: task?.recurrenceRule != nil)
        _frequency = State(initialValue: task?.recurrenceRule?.frequency ?? .weekly)
        _interval = State(initialValue: task?.recurrenceRule?.interval ?? 1)
        _intensity = State(initialValue: task?.nudgePolicy.intensity ?? .gentle)
    }

    private var isEditing: Bool { existingTask != nil }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    private let minuteOptions = [5, 10, 15, 30, 45, 60, 90, 120]

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("What needs doing?", text: $title)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section("Time needed") {
                    Picker("Estimated time", selection: $estimatedMinutes) {
                        ForEach(minuteOptions, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                }

                Section("Chore (recurring)") {
                    Toggle("Repeats", isOn: $isRecurring)
                    if isRecurring {
                        Picker("Frequency", selection: $frequency) {
                            ForEach(RecurrenceRule.Frequency.allCases, id: \.self) { freq in
                                Text(freq.label).tag(freq)
                            }
                        }
                        Stepper("Every \(interval)", value: $interval, in: 1...30)
                    }
                }

                if !isRecurring {
                    Section("Deadline") {
                        Toggle("Has a due date", isOn: $hasDueDate)
                        if hasDueDate {
                            Toggle("Include time", isOn: $includeTime)
                            DatePicker(
                                "Due",
                                selection: $dueDate,
                                displayedComponents: includeTime ? [.date, .hourAndMinute] : .date
                            )
                        }
                    }
                }

                Section("Nudge intensity") {
                    Picker("Intensity", selection: $intensity) {
                        ForEach(NudgeIntensity.allCases, id: \.self) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(intensity.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isEditing ? "Edit task" : "New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let recurrence = isRecurring ? RecurrenceRule(frequency: frequency, interval: interval) : nil
        let policy = NudgePolicy(intensity: intensity)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDue: Date?
        if !isRecurring && hasDueDate {
            // Without a specific time, pin the due date to the start of the day.
            resolvedDue = includeTime ? dueDate : Calendar.current.startOfDay(for: dueDate)
        } else {
            resolvedDue = nil
        }

        if let task = existingTask {
            task.title = title
            task.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            task.estimatedMinutes = estimatedMinutes
            task.dueDate = resolvedDue
            task.recurrenceRule = recurrence
            task.nudgePolicy = policy
        } else {
            let task = TaskItem(
                title: title,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                estimatedMinutes: estimatedMinutes,
                dueDate: resolvedDue,
                recurrenceRule: recurrence,
                nudgePolicy: policy
            )
            modelContext.insert(task)
        }

        NudgeScheduler.shared.reconcile(in: modelContext)
        dismiss()
    }
}

#Preview {
    AddEditTaskView()
        .modelContainer(for: TaskItem.self, inMemory: true)
}
