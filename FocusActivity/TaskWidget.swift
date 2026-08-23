//
//  TaskWidget.swift
//  FocusActivity
//
//  The "Today's Tasks" Home Screen widget, in Small, Medium and Large: the current task (with a
//  Complete button) plus the up-next list. Reads the shared App Group store (see `SharedStore`)
//  and ranks up-next tasks with `TaskPrioritizer`.
//

import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

// MARK: - Snapshot model

/// A small view of a task for the timeline entry (the `@Model` object itself must not escape the
/// fetch context).
struct TaskSnapshot: Identifiable {
    let id: String
    let title: String
    let reason: String
    let estimatedMinutes: Int
    let focusStartedAt: Date?
}

// MARK: - Timeline entry

struct TaskEntry: TimelineEntry {
    let date: Date
    let current: TaskSnapshot?
    let upNext: [TaskSnapshot]

    static let placeholder = TaskEntry(
        date: Date(),
        current: TaskSnapshot(id: "0", title: "Fold the laundry", reason: "Currently Doing",
                              estimatedMinutes: 15, focusStartedAt: Date().addingTimeInterval(-120)),
        upNext: [
            TaskSnapshot(id: "1", title: "Reply to Sam's email", reason: "Due today",
                         estimatedMinutes: 5, focusStartedAt: nil),
            TaskSnapshot(id: "2", title: "Water the plants", reason: "To do",
                         estimatedMinutes: 10, focusStartedAt: nil),
            TaskSnapshot(id: "3", title: "Book dentist", reason: "Overdue",
                         estimatedMinutes: 10, focusStartedAt: nil),
        ]
    )
}

// MARK: - Provider

struct TaskProvider: TimelineProvider {
    /// Up-next rows fetched; individual layouts slice this down per family.
    private let upNextLimit = 6

    func placeholder(in context: Context) -> TaskEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) {
        completion(context.isPreview ? .placeholder : loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        let entry = loadEntry()
        // The elapsed timer is self-updating; content otherwise only changes when the app or a
        // widget button mutates the store (which reloads timelines explicitly). A periodic refresh
        // keeps "Due today"/"Overdue" reasons honest across the day.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date) ?? entry.date.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> TaskEntry {
        guard let container = try? SharedStore.makeContainer(cloudKit: false) else {
            return TaskEntry(date: Date(), current: nil, upNext: [])
        }
        let context = ModelContext(container)
        let all = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []

        let current = all.first { $0.focusStartedAt != nil }.map { task in
            TaskSnapshot(id: task.id.uuidString, title: task.title, reason: "Currently Doing",
                         estimatedMinutes: task.estimatedMinutes, focusStartedAt: task.focusStartedAt)
        }

        let upNext = TaskPrioritizer.upNext(from: all, limit: upNextLimit).map { task in
            TaskSnapshot(id: task.id.uuidString, title: task.title, reason: task.surfacingReason,
                         estimatedMinutes: task.estimatedMinutes, focusStartedAt: nil)
        }

        return TaskEntry(date: Date(), current: current, upNext: upNext)
    }
}

// MARK: - Entry view

struct TasksWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TaskEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:  TasksSmallView(entry: entry)
            case .systemMedium: TasksMediumView(entry: entry)
            default:            TasksLargeView(entry: entry)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "actuallydidit://now"))
    }
}

private struct TasksSmallView: View {
    let entry: TaskEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let current = entry.current {
                CurrentTaskBlock(current: current)
            } else if entry.upNext.isEmpty {
                EmptyState()
            } else {
                ReasonLabel(text: "Up next")
                ForEach(entry.upNext.prefix(2)) { task in
                    Text(task.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TasksMediumView: View {
    let entry: TaskEntry

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                if let current = entry.current {
                    CurrentTaskBlock(current: current)
                } else {
                    NothingInFocus()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            UpNextList(tasks: entry.upNext, limit: 3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TasksLargeView: View {
    let entry: TaskEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let current = entry.current {
                CurrentTaskBlock(current: current)
            } else {
                NothingInFocus()
            }
            Divider()
            UpNextList(tasks: entry.upNext, limit: 5)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Shared subviews

private struct CurrentTaskBlock: View {
    let current: TaskSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ReasonLabel(text: current.reason)
            Text(current.title)
                .font(.headline)
                .lineLimit(3)
            if let start = current.focusStartedAt {
                Text(start, style: .timer)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            CompleteButton(taskID: current.id)
        }
        .focusCard()
    }
}

private extension View {
    /// The app's "focus task" treatment: a soft accent-tinted card with a hairline accent
    /// border, mirroring the Doing-now card on the main screen.
    func focusCard() -> some View {
        padding(10)
            .background(
                Color.accentColor.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.20), lineWidth: 1)
            )
    }
}

private struct UpNextList: View {
    let tasks: [TaskSnapshot]
    let limit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("UP NEXT")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if tasks.isEmpty {
                Text("All clear 🎉")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tasks.prefix(limit)) { task in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(task.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text("\(task.reason) · \(task.estimatedMinutes) min")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

private struct ReasonLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tint)
    }
}

private struct CompleteButton: View {
    let taskID: String
    var body: some View {
        Button(intent: CompleteTaskIntent(taskID: taskID)) {
            Label("Complete", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(.accentColor)
    }
}

private struct NothingInFocus: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ReasonLabel(text: "Nothing in focus")
            Text("Pick something to do")
                .font(.headline)
                .lineLimit(2)
        }
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "checkmark.circle")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("All clear 🎉")
                .font(.headline)
            Text("Nothing to do right now")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Widget

struct TasksWidget: Widget {
    let kind = "TasksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskProvider()) { entry in
            TasksWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Today's Tasks")
        .description("Your current task and what's up next.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Previews

#Preview("Tasks – Small", as: .systemSmall) {
    TasksWidget()
} timeline: {
    TaskEntry.placeholder
}

#Preview("Tasks – Medium", as: .systemMedium) {
    TasksWidget()
} timeline: {
    TaskEntry.placeholder
}

#Preview("Tasks – Large", as: .systemLarge) {
    TasksWidget()
} timeline: {
    TaskEntry.placeholder
}
