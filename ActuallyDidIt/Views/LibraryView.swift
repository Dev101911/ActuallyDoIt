//
//  LibraryView.swift
//  ActuallyDidIt
//
//  The opt-in "everything" screen. Splits tasks into ToDos (one-off) and Chores (recurring),
//  plus a collapsed-by-default Completed section. Tapping a task asks to set it as the current
//  focus; swiping marks it Done; the trailing menu holds Edit / Delete.
//

import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \TaskItem.createdAt, order: .reverse)
    private var allTasks: [TaskItem]

    @State private var showingAdd = false
    @State private var taskPendingDelete: TaskItem?

    // Section expansion state: active work is expanded, done work is tucked away.
    @State private var todosExpanded = true
    @State private var choresExpanded = true
    @State private var completedExpanded = false

    private var openTasks: [TaskItem] {
        allTasks.filter { $0.status != .completed }
    }
    private var todos: [TaskItem] { openTasks.filter { !$0.isChore } }
    private var chores: [TaskItem] { openTasks.filter { $0.isChore } }
    private var completed: [TaskItem] {
        allTasks
            .filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            List {
                if openTasks.isEmpty && completed.isEmpty {
                    ContentUnavailableView(
                        "No tasks yet",
                        systemImage: "tray",
                        description: Text("Add something you want to get done.")
                    )
                }

                if !todos.isEmpty {
                    Section(isExpanded: $todosExpanded) {
                        ForEach(todos) { openTaskRow($0) }
                    } header: {
                        Text("To Do")
                    }
                }

                if !chores.isEmpty {
                    Section(isExpanded: $choresExpanded) {
                        ForEach(chores) { openTaskRow($0) }
                    } header: {
                        Text("Chores")
                    }
                }

                if !completed.isEmpty {
                    Section(isExpanded: $completedExpanded) {
                        ForEach(completed) { completedTaskRow($0) }
                    } header: {
                        Text("Completed (\(completed.count))")
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("All tasks")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add task", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddEditTaskView()
                    .interactiveDismissDisabled()
            }
            .confirmationDialog(
                "Delete this task?",
                isPresented: Binding(
                    get: { taskPendingDelete != nil },
                    set: { if !$0 { taskPendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: taskPendingDelete
            ) { task in
                Button("Delete", role: .destructive) {
                    TaskActions.delete(task, in: modelContext)
                }
                Button("Cancel", role: .cancel) {}
            } message: { task in
                Text(task.title)
            }
        }
    }

    // MARK: - Rows

    private func openTaskRow(_ task: TaskItem) -> some View {
        TaskListRow(task: task, onSetAsFocus: { dismiss() })
    }

    private func completedTaskRow(_ task: TaskItem) -> some View {
        HStack(spacing: 8) {
            TaskRowView(task: task, isCompleted: true)
            Spacer(minLength: 0)
            Menu {
                Button {
                    TaskActions.markUnfinished(task, in: modelContext)
                } label: {
                    Label("Mark as unfinished", systemImage: "arrow.uturn.backward")
                }
                Button(role: .destructive) {
                    taskPendingDelete = task
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                menuLabel
            }
        }
    }

    private var menuLabel: some View {
        Image(systemName: "ellipsis")
            .foregroundStyle(.secondary)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
    }
}

/// The text/detail block for a task row. Callers add trailing accessories (star, menu).
/// Completed tasks are shown struck through and muted.
struct TaskRowView: View {
    let task: TaskItem
    var isCompleted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title)
                .font(.body)
                .strikethrough(isCompleted)
                .foregroundStyle(isCompleted ? .secondary : .primary)

            if isCompleted {
                if let completedAt = task.completedAt {
                    Label("Done \(completedAt.formatted(date: .abbreviated, time: .omitted))",
                          systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    Label(task.estimatedTimeLabel, systemImage: "clock")
                    if task.isChore, let summary = task.recurrenceRule?.summary {
                        Label(summary, systemImage: "repeat")
                    } else if let due = task.dueDate {
                        Label(due.formatted(date: .abbreviated, time: .omitted),
                              systemImage: "calendar")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    LibraryView()
        .modelContainer(SampleData.previewContainer)
}
