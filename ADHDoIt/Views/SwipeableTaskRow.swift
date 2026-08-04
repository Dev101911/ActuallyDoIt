//
//  SwipeableTaskRow.swift
//  ADHDoIt
//
//  A reusable `List` row for a `TaskItem` carrying the app's standard interactions:
//  a tap (used to offer "set as current"), a leading full-swipe **Done** (complete) and a
//  trailing full-swipe **Delete**. The visible content and an optional trailing accessory
//  (e.g. an overflow menu) are supplied by the caller, so different screens share the behaviour
//  while keeping their own row appearance. Based on the Library view's task row.
//

import SwiftUI
import SwiftData

struct SwipeableTaskRow<Content: View, Accessory: View>: View {
    @Environment(\.modelContext) private var modelContext

    let task: TaskItem
    var onTap: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var accessory: () -> Accessory

    @State private var confirmingDelete = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onTap) {
                content()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            accessory()
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                TaskActions.complete(task, in: modelContext)
            } label: {
                Label("Done", systemImage: "checkmark")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Delete this task?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                TaskActions.delete(task, in: modelContext)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(task.title)
        }
    }
}

extension SwipeableTaskRow where Accessory == EmptyView {
    /// Convenience for rows without a trailing accessory.
    init(task: TaskItem,
         onTap: @escaping () -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(task: task, onTap: onTap, content: content, accessory: { EmptyView() })
    }
}

/// The app's standard task row, shared by the Now and Library screens so they look and behave
/// identically: a `TaskRowView` with a "current" star, an overflow menu (Mark as done / Edit /
/// Delete), and the tap + swipe behaviour of `SwipeableTaskRow`.
struct TaskListRow: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage(AccentTheme.storageKey) private var accentTheme = AccentTheme.default

    let task: TaskItem
    /// Called after the task is set as the focus task (e.g. to dismiss a presenting sheet).
    var onSetAsFocus: () -> Void = {}

    @State private var editingTask: TaskItem?
    @State private var showingDetail = false
    @State private var confirmingDelete = false

    var body: some View {
        SwipeableTaskRow(task: task, onTap: { showingDetail = true }) {
            HStack {
                TaskRowView(task: task)
                Spacer(minLength: 0)
            }
        } accessory: {
            menu
        }
        .listRowBackground(task.isCurrent ? accentTheme.color.opacity(0.12) : nil)
        .sheet(item: $editingTask) { task in
            AddEditTaskView(task: task)
        }
        .sheet(isPresented: $showingDetail) {
            TaskDetailView(task: task)
        }
        .confirmationDialog(
            "Delete this task?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                TaskActions.delete(task, in: modelContext)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(task.title)
        }
    }

    private var menu: some View {
        Menu {
            if !task.isCurrent {
                Button {
                    TaskActions.promoteToCurrent(task, in: modelContext)
                    onSetAsFocus()
                } label: {
                    Label("Set as doing now", systemImage: "target")
                }
            }
            Button {
                TaskActions.complete(task, in: modelContext)
            } label: {
                Label("Mark as done", systemImage: "checkmark.circle")
            }
            Button {
                editingTask = task
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
    }
}
