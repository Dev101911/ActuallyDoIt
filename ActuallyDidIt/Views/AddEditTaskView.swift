//
//  AddEditTaskView.swift
//  ActuallyDidIt
//
//  Create or edit a task. A task with a recurrence is a Chore; without one it's a ToDo.
//
//  The editable fields and their seed/save logic live in `TaskEditor`, and the form UI lives in
//  `TaskFormFields`, so the same editing experience is shared between this create/edit modal and the
//  inline-editable `TaskDetailView`.
//

import SwiftUI
import SwiftData

/// Holds every editable field for a task, seeded from an existing task (or defaults for a new one),
/// and knows how to write those fields back onto a `TaskItem`. Shared by `AddEditTaskView` (create)
/// and `TaskDetailView` (inline edit).
@Observable
final class TaskEditor {
    /// The kind of task being edited, which decides what scheduling fields are shown.
    enum Kind: String, CaseIterable, Identifiable {
        case dueDate
        case chore
        case none

        var id: String { rawValue }

        var label: String {
            switch self {
            case .none: return "None"
            case .dueDate: return "Due date"
            case .chore: return "Chore"
            }
        }

        var detail: String {
            switch self {
            case .none: return "A simple to-do with no schedule and no Nudges."
            case .dueDate: return "A one-off task with a deadline."
            case .chore: return "A recurring task that repeats on a schedule."
            }
        }
    }

    var title: String
    var notes: String
    var estimatedMinutes: Int

    var kind: Kind

    var dueDate: Date

    /// Whether a "before due" alert is enabled, and how far ahead it fires. Due dates are date-only,
    /// so the lead is measured in whole days (see `TaskItem`); time-of-day reminders come from the
    /// per-task nudge times instead.
    var alertEnabled: Bool
    var alertLeadMinutes: Int

    var frequency: RecurrenceRule.Frequency
    var interval: Int
    var weekdays: Set<Int>
    var startDate: Date
    var hasEndDate: Bool
    var endDate: Date

    var intensity: NudgeIntensity

    /// The per-task nudge times. Seeded from the global schedule set in Settings, then editable
    /// inline for every task.
    var nudgeTimes: NudgeTimes

    init(task: TaskItem?) {
        title = task?.title ?? ""
        notes = task?.notes ?? ""
        estimatedMinutes = task?.estimatedMinutes ?? 15

        // Derive the task kind from what the stored task already has; new tasks default to a due date.
        if task?.recurrenceRule != nil {
            kind = .chore
        } else if task?.dueDate != nil {
            kind = .dueDate
        } else if task == nil {
            kind = .dueDate
        } else {
            kind = .none
        }

        dueDate = task?.dueDate ?? Date()
        alertEnabled = task?.dueAlertLeadMinutes != nil
        alertLeadMinutes = task?.dueAlertLeadMinutes ?? Self.defaultLeadMinutes
        frequency = task?.recurrenceRule?.frequency ?? .weekly
        interval = task?.recurrenceRule?.interval ?? 1
        weekdays = Set(task?.recurrenceRule?.weekdays ?? [])
        startDate = task?.recurrenceRule?.startDate ?? Date()
        hasEndDate = task?.recurrenceRule?.endDate != nil
        endDate = task?.recurrenceRule?.endDate ?? Date()
        intensity = task?.nudgePolicy.intensity ?? .gentle
        nudgeTimes = task?.nudgePolicy.customTimes ?? NudgeSchedule.currentTimes()
    }

    var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    let minuteOptions = [5, 10, 15, 30, 45, 60, 90, 120]

    /// Alert lead-time choices for a date-only due date, as (label, days-before expressed in minutes).
    static let leadOptions: [(label: String, minutes: Int)] = [
        ("On the day (9 AM)", 0),
        ("1 day before", 24 * 60),
        ("2 days before", 2 * 24 * 60),
        ("1 week before", 7 * 24 * 60)
    ]

    /// A sensible default lead time when the alert is first switched on.
    static let defaultLeadMinutes = 24 * 60

    /// The nudge policy as currently configured, carrying this task's own nudge times.
    var resolvedPolicy: NudgePolicy {
        NudgePolicy(intensity: intensity, customTimes: nudgeTimes)
    }

    /// The fire times to plot on the timeline preview, reflecting the current override state.
    var previewMarkers: [Int] { NudgeSchedule.fireMinutes(for: resolvedPolicy) }

    /// The recurrence, resolved due date and alert lead implied by the current fields.
    private func resolvedScheduling() -> (recurrence: RecurrenceRule?, due: Date?, alertLead: Int?) {
        switch kind {
        case .none:
            return (nil, nil, nil)
        case .dueDate:
            // Due dates are date-only; pin them to the start of the day.
            let due = Calendar.current.startOfDay(for: dueDate)
            return (nil, due, alertEnabled ? alertLeadMinutes : nil)
        case .chore:
            let days = frequency == .weekly ? Array(weekdays) : nil
            let rule = RecurrenceRule(frequency: frequency, interval: interval, weekdays: days,
                                      startDate: startDate, endDate: hasEndDate ? endDate : nil)
            // Seed the first occurrence so the chore starts nudging on (or after) its start day.
            return (rule, rule.firstDueDate(), nil)
        }
    }

    /// Writes the current fields onto an existing task. The trimmed title is only applied when
    /// non-empty, so an accidentally blanked field never wipes a task's title.
    func apply(to task: TaskItem) {
        let (recurrence, due, alertLead) = resolvedScheduling()
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedTitle.isEmpty { task.title = title }
        task.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        task.estimatedMinutes = estimatedMinutes
        task.dueDate = due
        task.dueAlertLeadMinutes = alertLead
        task.recurrenceRule = recurrence
        task.nudgePolicy = resolvedPolicy
    }

    /// Builds a brand-new task from the current fields.
    func makeTask() -> TaskItem {
        let (recurrence, due, alertLead) = resolvedScheduling()
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return TaskItem(
            title: title,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            estimatedMinutes: estimatedMinutes,
            dueDate: due,
            dueAlertLeadMinutes: alertLead,
            recurrenceRule: recurrence,
            nudgePolicy: resolvedPolicy
        )
    }
}

struct AddEditTaskView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Whether an existing task is being edited (vs. creating a new one).
    private let isEditing: Bool
    /// The task being edited, or nil when creating a new one.
    private let existingTask: TaskItem?

    @State private var editor: TaskEditor

    init(task: TaskItem? = nil) {
        self.existingTask = task
        self.isEditing = task != nil
        _editor = State(initialValue: TaskEditor(task: task))
    }

    var body: some View {
        NavigationStack {
            Form {
                TaskFormFields(editor: editor)
            }
            .navigationTitle(isEditing ? "Edit task" : "New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!editor.canSave)
                }
            }
        }
    }

    private func save() {
        if let task = existingTask {
            editor.apply(to: task)
        } else {
            modelContext.insert(editor.makeTask())
        }
        NudgeScheduler.shared.reconcile(in: modelContext)
        dismiss()
    }
}

/// The editable task fields — Task, Time needed, Type and Nudge intensity — shared by the create
/// modal and the inline-editable detail view.
struct TaskFormFields: View {
    @Bindable var editor: TaskEditor

    /// Time-of-day pickers for the selected intensity, matching the Settings "Nudge times" layout.
    @ViewBuilder private var nudgeTimePickers: some View {
        switch editor.intensity {
        case .gentle:
            DatePicker("Reminder", selection: timeBinding($editor.nudgeTimes.gentleMinutes),
                       displayedComponents: .hourAndMinute)
        case .persistent:
            DatePicker("First", selection: timeBinding(persistentBinding(0)),
                       displayedComponents: .hourAndMinute)
            DatePicker("Second", selection: timeBinding(persistentBinding(1)),
                       displayedComponents: .hourAndMinute)
            DatePicker("Third", selection: timeBinding(persistentBinding(2)),
                       displayedComponents: .hourAndMinute)
        case .relentless:
            DatePicker("Start", selection: timeBinding($editor.nudgeTimes.relentlessStartMinutes),
                       displayedComponents: .hourAndMinute)
            DatePicker("End", selection: timeBinding($editor.nudgeTimes.relentlessEndMinutes),
                       displayedComponents: .hourAndMinute)
        }
    }

    /// Bridges a minutes-from-midnight binding to the `Date` a `DatePicker` expects.
    private func timeBinding(_ source: Binding<Int>) -> Binding<Date> {
        Binding<Date>(
            get: { NudgeSchedule.date(fromMinutes: source.wrappedValue) },
            set: { source.wrappedValue = NudgeSchedule.minutes(from: $0) }
        )
    }

    /// A binding into one of the three Persistent reminder times.
    private func persistentBinding(_ index: Int) -> Binding<Int> {
        Binding<Int>(
            get: { editor.nudgeTimes.persistentMinutes[index] },
            set: { editor.nudgeTimes.persistentMinutes[index] = $0 }
        )
    }

    var body: some View {
        Section("Task") {
            TextField("What needs doing?", text: $editor.title)
            TextField("Notes (optional)", text: $editor.notes, axis: .vertical)
                .lineLimit(1...4)
        }

        Section("Time needed") {
            Picker("Estimated time", selection: $editor.estimatedMinutes) {
                ForEach(editor.minuteOptions, id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }
        }

        Section("Type") {
            Picker("Type", selection: $editor.kind) {
                ForEach(TaskEditor.Kind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            switch editor.kind {
            case .none:
                Text(editor.kind.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .dueDate:
                DatePicker("Due", selection: $editor.dueDate, displayedComponents: .date)

                Toggle("Alert", isOn: $editor.alertEnabled)
                if editor.alertEnabled {
                    Picker("Alert", selection: $editor.alertLeadMinutes) {
                        ForEach(TaskEditor.leadOptions, id: \.minutes) { option in
                            Text(option.label).tag(option.minutes)
                        }
                    }
                }

            case .chore:
                Picker("Frequency", selection: $editor.frequency) {
                    ForEach(RecurrenceRule.Frequency.allCases, id: \.self) { freq in
                        Text(freq.label).tag(freq)
                    }
                }
                Stepper("Every \(editor.interval)", value: $editor.interval, in: 1...30)

                DatePicker("Starting from", selection: $editor.startDate, displayedComponents: .date)

                Toggle("End date", isOn: $editor.hasEndDate)
                if editor.hasEndDate {
                    DatePicker("Ending on", selection: $editor.endDate, in: editor.startDate...,
                               displayedComponents: .date)
                }

                if editor.frequency == .weekly {
                    WeekdaySelector(selection: $editor.weekdays)
                }
            }
        }

        if editor.kind != .none {
            Section("Nudge intensity") {
                Picker("Intensity", selection: $editor.intensity) {
                    ForEach(NudgeIntensity.allCases, id: \.self) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.segmented)

                Text(editor.intensity.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                NudgeTimeline(markers: editor.previewMarkers)
                    .padding(.vertical, 4)

                nudgeTimePickers
            }
        }
    }
}

/// A compact timeline showing when nudges fall across the day, using the times the user has
/// configured for each intensity in Settings, so the selected intensity is easy to picture.
private struct NudgeTimeline: View {
    /// The fire times to plot (minutes from midnight), sorted ascending.
    let markers: [Int]

    private let dotSize: CGFloat = 8

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
            .animation(.snappy, value: markers)

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

/// A row of circular day toggles for choosing which weekdays a weekly chore repeats on.
/// Days are ordered starting from the user's locale's first weekday, and selection is stored as
/// `Calendar` weekday numbers (1 = Sunday … 7 = Saturday).
private struct WeekdaySelector: View {
    @Binding var selection: Set<Int>

    private let calendar = Calendar.current

    /// Weekday numbers ordered from the locale's first weekday.
    private var orderedWeekdays: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    private func symbol(for weekday: Int) -> String {
        calendar.veryShortWeekdaySymbols[weekday - 1]
    }

    private func fullName(for weekday: Int) -> String {
        calendar.weekdaySymbols[weekday - 1]
    }

    private func toggle(_ weekday: Int) {
        if selection.contains(weekday) {
            selection.remove(weekday)
        } else {
            selection.insert(weekday)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("On these days")
                .font(.subheadline)

            HStack(spacing: 6) {
                ForEach(orderedWeekdays, id: \.self) { weekday in
                    let isOn = selection.contains(weekday)
                    Button {
                        toggle(weekday)
                    } label: {
                        Text(symbol(for: weekday))
                            .font(.footnote.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: Circle())
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(fullName(for: weekday))
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AddEditTaskView()
        .modelContainer(for: TaskItem.self, inMemory: true)
}
