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

                    PauseChoreSection(task: task)
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
                        StandardButton("Set as doing now", role: .secondary) {
                            TaskActions.promoteToCurrent(task, in: modelContext)
                            dismiss()
                        }
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
                ForEach(PauseDuration.presets) { preset in
                    Button {
                        TaskActions.pause(task, until: preset.resumeDate(), in: modelContext)
                    } label: {
                        Label("Pause for \(preset.label)", systemImage: "pause.circle")
                    }
                }

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
