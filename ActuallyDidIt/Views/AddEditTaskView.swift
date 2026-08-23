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

                    NudgeTimeline(intensity: intensity)
                        .padding(.vertical, 4)
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

/// A compact timeline showing when nudges fall across the day, using the times the user has
/// configured for each intensity in Settings, so the selected intensity is easy to picture.
private struct NudgeTimeline: View {
    let intensity: NudgeIntensity

    private let dotSize: CGFloat = 8

    /// The configured fire times (minutes from midnight), sorted ascending.
    private var markers: [Int] { NudgeSchedule.fireMinutes(for: intensity) }

    /// The window the timeline spans, from the earliest to the latest nudge.
    private var window: (lo: Int, hi: Int) {
        let lo = markers.min() ?? 0
        let hi = markers.max() ?? lo
        return (lo, hi)
    }

    /// Normalised position (0…1) of a marker within the window. A single marker sits centred.
    private func position(for minutes: Int) -> Double {
        let (lo, hi) = window
        guard hi > lo else { return 0.5 }
        return Double(minutes - lo) / Double(hi - lo)
    }

    private func label(forMinutes minutes: Int) -> String {
        NudgeSchedule.date(fromMinutes: minutes)
            .formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let radius = dotSize / 2
                let usableWidth = max(geo.size.width - dotSize, 0)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                        .frame(height: 4)

                    ForEach(markers, id: \.self) { minutes in
                        Circle()
                            .fill(.tint)
                            .frame(width: dotSize, height: dotSize)
                            .position(x: radius + position(for: minutes) * usableWidth,
                                      y: geo.size.height / 2)
                    }
                }
                .frame(height: geo.size.height)
            }
            .frame(height: dotSize)
            .animation(.snappy, value: intensity)

            if markers.count == 1 {
                Text(label(forMinutes: window.lo))
                    .frame(maxWidth: .infinity)
            } else if markers.count > 1 {
                ZStack {
                    HStack {
                        Text(label(forMinutes: window.lo))
                        Spacer()
                        Text(label(forMinutes: window.hi))
                    }

                    // Label the middle dot too when there are exactly three (Persistent).
                    if markers.count == 3 {
                        GeometryReader { geo in
                            let radius = dotSize / 2
                            let usableWidth = max(geo.size.width - dotSize, 0)
                            Text(label(forMinutes: markers[1]))
                                .position(x: radius + position(for: markers[1]) * usableWidth,
                                          y: geo.size.height / 2)
                        }
                    }
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
}

#Preview {
    AddEditTaskView()
        .modelContainer(for: TaskItem.self, inMemory: true)
}
