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

    /// The kind of task being created, which decides what scheduling fields are shown.
    private enum TaskKind: String, CaseIterable, Identifiable {
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

    @State private var title: String
    @State private var notes: String
    @State private var estimatedMinutes: Int

    @State private var kind: TaskKind

    @State private var dueDate: Date
    @State private var includeTime: Bool

    /// Whether a "before due" alert is enabled, and how far ahead it fires. The lead is measured in
    /// minutes for a timed due date and in whole days for a date-only one (see `TaskItem`).
    @State private var alertEnabled: Bool
    @State private var alertLeadMinutes: Int

    @State private var frequency: RecurrenceRule.Frequency
    @State private var interval: Int
    @State private var weekdays: Set<Int>
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date

    @State private var intensity: NudgeIntensity

    /// The per-task nudge times. Seeded from the global schedule set in Settings, then editable
    /// inline for every task.
    @State private var nudgeTimes: NudgeTimes

    init(task: TaskItem? = nil) {
        self.existingTask = task
        _title = State(initialValue: task?.title ?? "")
        _notes = State(initialValue: task?.notes ?? "")
        _estimatedMinutes = State(initialValue: task?.estimatedMinutes ?? 15)

        // Derive the task kind from what the stored task already has; new tasks default to a due date.
        let initialKind: TaskKind
        if task?.recurrenceRule != nil {
            initialKind = .chore
        } else if task?.dueDate != nil {
            initialKind = .dueDate
        } else if task == nil {
            initialKind = .dueDate
        } else {
            initialKind = .none
        }
        _kind = State(initialValue: initialKind)

        _dueDate = State(initialValue: task?.dueDate ?? Date())
        // Treat a stored due date that isn't pinned to midnight as having a specific time.
        let storedIncludeTime = task?.dueDate.map { Calendar.current.startOfDay(for: $0) != $0 } ?? false
        _includeTime = State(initialValue: storedIncludeTime)
        _alertEnabled = State(initialValue: task?.dueAlertLeadMinutes != nil)
        _alertLeadMinutes = State(initialValue: task?.dueAlertLeadMinutes
                                  ?? Self.defaultLeadMinutes(includeTime: storedIncludeTime))
        _frequency = State(initialValue: task?.recurrenceRule?.frequency ?? .weekly)
        _interval = State(initialValue: task?.recurrenceRule?.interval ?? 1)
        _weekdays = State(initialValue: Set(task?.recurrenceRule?.weekdays ?? []))
        _startDate = State(initialValue: task?.recurrenceRule?.startDate ?? Date())
        _hasEndDate = State(initialValue: task?.recurrenceRule?.endDate != nil)
        _endDate = State(initialValue: task?.recurrenceRule?.endDate ?? Date())
        _intensity = State(initialValue: task?.nudgePolicy.intensity ?? .gentle)
        _nudgeTimes = State(initialValue: task?.nudgePolicy.customTimes ?? NudgeSchedule.currentTimes())
    }

    private var isEditing: Bool { existingTask != nil }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    private let minuteOptions = [5, 10, 15, 30, 45, 60, 90, 120]

    /// Alert lead-time choices for a due date *with* a time, as (label, minutes-before).
    private static let timedLeadOptions: [(label: String, minutes: Int)] = [
        ("At time due", 0),
        ("15 minutes before", 15),
        ("30 minutes before", 30),
        ("1 hour before", 60),
        ("2 hours before", 120),
        ("1 day before", 24 * 60)
    ]

    /// Alert lead-time choices for a date-only due date, as (label, days-before expressed in minutes).
    private static let dateLeadOptions: [(label: String, minutes: Int)] = [
        ("On the day (9 AM)", 0),
        ("1 day before", 24 * 60),
        ("2 days before", 2 * 24 * 60),
        ("1 week before", 7 * 24 * 60)
    ]

    /// The lead options appropriate to whether the due date carries a time.
    private var leadOptions: [(label: String, minutes: Int)] {
        includeTime ? Self.timedLeadOptions : Self.dateLeadOptions
    }

    /// A sensible default lead time when the alert is first switched on.
    private static func defaultLeadMinutes(includeTime: Bool) -> Int {
        includeTime ? 30 : 24 * 60
    }

    /// The nudge policy as currently configured, carrying this task's own nudge times.
    private var resolvedPolicy: NudgePolicy {
        NudgePolicy(intensity: intensity, customTimes: nudgeTimes)
    }

    /// The fire times to plot on the timeline preview, reflecting the current override state.
    private var previewMarkers: [Int] { NudgeSchedule.fireMinutes(for: resolvedPolicy) }

    /// Time-of-day pickers for the selected intensity, matching the Settings "Nudge times" layout.
    @ViewBuilder private var nudgeTimePickers: some View {
        switch intensity {
        case .gentle:
            DatePicker("Reminder", selection: timeBinding($nudgeTimes.gentleMinutes),
                       displayedComponents: .hourAndMinute)
        case .persistent:
            DatePicker("First", selection: timeBinding(persistentBinding(0)),
                       displayedComponents: .hourAndMinute)
            DatePicker("Second", selection: timeBinding(persistentBinding(1)),
                       displayedComponents: .hourAndMinute)
            DatePicker("Third", selection: timeBinding(persistentBinding(2)),
                       displayedComponents: .hourAndMinute)
        case .relentless:
            DatePicker("Start", selection: timeBinding($nudgeTimes.relentlessStartMinutes),
                       displayedComponents: .hourAndMinute)
            DatePicker("End", selection: timeBinding($nudgeTimes.relentlessEndMinutes),
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
            get: { nudgeTimes.persistentMinutes[index] },
            set: { nudgeTimes.persistentMinutes[index] = $0 }
        )
    }

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

                Section("Type") {
                    Picker("Type", selection: $kind) {
                        ForEach(TaskKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch kind {
                    case .none:
                        Text(kind.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                    case .dueDate:
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                        Toggle("Include time", isOn: $includeTime)
                        if includeTime {
                            DatePicker("Time", selection: $dueDate, displayedComponents: .hourAndMinute)
                        }

                        Toggle("Alert", isOn: $alertEnabled)
                        if alertEnabled {
                            Picker("Alert", selection: $alertLeadMinutes) {
                                ForEach(leadOptions, id: \.minutes) { option in
                                    Text(option.label).tag(option.minutes)
                                }
                            }
                        }

                    case .chore:
                        Picker("Frequency", selection: $frequency) {
                            ForEach(RecurrenceRule.Frequency.allCases, id: \.self) { freq in
                                Text(freq.label).tag(freq)
                            }
                        }
                        Stepper("Every \(interval)", value: $interval, in: 1...30)

                        DatePicker("Starting from", selection: $startDate, displayedComponents: .date)

                        Toggle("End date", isOn: $hasEndDate)
                        if hasEndDate {
                            DatePicker("Ending on", selection: $endDate, in: startDate...,
                                       displayedComponents: .date)
                        }

                        if frequency == .weekly {
                            WeekdaySelector(selection: $weekdays)
                        }
                    }
                }

                if kind != .none {
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

                        NudgeTimeline(markers: previewMarkers)
                            .padding(.vertical, 4)

                        nudgeTimePickers
                    }
                }
            }
            .onChange(of: includeTime) { _, newValue in
                // The lead time is measured differently for timed vs date-only due dates, so reset
                // it to a valid default for the new mode.
                alertLeadMinutes = Self.defaultLeadMinutes(includeTime: newValue)
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
        let policy = resolvedPolicy
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let recurrence: RecurrenceRule?
        let resolvedDue: Date?
        // Only due-date tasks carry a "before due" alert.
        var resolvedAlertLead: Int?
        switch kind {
        case .none:
            recurrence = nil
            resolvedDue = nil
        case .dueDate:
            recurrence = nil
            // Without a specific time, pin the due date to the start of the day.
            resolvedDue = includeTime ? dueDate : Calendar.current.startOfDay(for: dueDate)
            resolvedAlertLead = alertEnabled ? alertLeadMinutes : nil
        case .chore:
            let days = frequency == .weekly ? Array(weekdays) : nil
            let rule = RecurrenceRule(frequency: frequency, interval: interval, weekdays: days, startDate: startDate, endDate: hasEndDate ? endDate : nil)
            recurrence = rule
            // Seed the first occurrence so the chore starts nudging on (or after) its start day.
            resolvedDue = rule.firstDueDate()
        }

        if let task = existingTask {
            task.title = title
            task.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            task.estimatedMinutes = estimatedMinutes
            task.dueDate = resolvedDue
            task.dueAlertLeadMinutes = resolvedAlertLead
            task.recurrenceRule = recurrence
            task.nudgePolicy = policy
        } else {
            let task = TaskItem(
                title: title,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                estimatedMinutes: estimatedMinutes,
                dueDate: resolvedDue,
                dueAlertLeadMinutes: resolvedAlertLead,
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
