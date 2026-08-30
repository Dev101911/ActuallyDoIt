//
//  SwipeableTaskRow.swift
//  ActuallyDidIt
//
//  A reusable `List` row for a `TaskItem` carrying the app's standard interactions:
//  a leading **checkbox** (tap to complete), a tap on the content (used to offer "set as
//  current"), and a trailing full-swipe **Delete**. The visible content and an optional trailing
//  accessory (e.g. an overflow menu) are supplied by the caller, so different screens share the
//  behaviour while keeping their own row appearance. Based on the Library view's task row.
//

import SwiftUI
import SwiftData

/// A tappable rounded-square checkbox used to complete (or reopen) a task from a list row.
/// Empty when unchecked; fills with the accent colour and a checkmark when checked, with a
/// spring pop and a light haptic on each tap.
///
/// Because completing a task removes its row from a status-filtered list, the box flips to its
/// new state *optimistically* and animates, then commits the caller's `action` after a short
/// beat — so you actually see the check (or uncheck) land before the row leaves.
struct TaskCheckbox: View {
    @AppStorage(AccentTheme.storageKey) private var accentTheme = AccentTheme.default

    var isChecked: Bool
    var action: () -> Void

    /// A transient optimistic override of `isChecked`, set on tap so the check/uncheck visibly
    /// lands before the row commits (and usually leaves the list). Cleared once the action
    /// commits and whenever `isChecked` changes — so a row whose `@State` is recycled by the
    /// `List` can never get stuck showing a stale check that no longer matches the task.
    @State private var optimisticChecked: Bool?
    /// Guards against a second tap firing the action again during the commit delay.
    @State private var isCommitting = false
    /// Bumped on every tap so `sensoryFeedback` fires even when committing removes the row.
    @State private var tapCount = 0

    private let boxSize: CGFloat = 24
    /// How long the check/uncheck animation gets to land before the change is committed.
    private let commitDelay: Duration = .seconds(0.35)

    /// The state actually drawn: the optimistic override while a tap settles, otherwise the live
    /// `isChecked` — so with no tap in flight the box always reflects the source of truth.
    private var displayChecked: Bool { optimisticChecked ?? isChecked }

    var body: some View {
        Button(action: tapped) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(displayChecked ? accentTheme.color : .clear)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        displayChecked ? accentTheme.color : Color.secondary.opacity(0.5),
                        lineWidth: 2
                    )

                if displayChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: boxSize, height: boxSize)
            // Widen the tap target well beyond the visible box.
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: tapCount)
        // Once the underlying task's state actually changes, drop any optimistic override so the
        // drawn state follows the source of truth.
        .onChange(of: isChecked) { _, _ in optimisticChecked = nil }
        .accessibilityLabel(displayChecked ? "Mark as unfinished" : "Mark as done")
        .accessibilityAddTraits(displayChecked ? [.isButton, .isSelected] : .isButton)
    }

    private func tapped() {
        guard !isCommitting else { return }
        isCommitting = true
        tapCount += 1
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            optimisticChecked = !displayChecked
        }
        // Let the animation play, then commit — the row typically leaves the list at this point.
        Task {
            try? await Task.sleep(for: commitDelay)
            action()
            // Hand back to the live `isChecked`; the row usually leaves the list now, but if it
            // stays (or its state is later recycled) it won't be stuck on the optimistic value.
            optimisticChecked = nil
            isCommitting = false
        }
    }
}

struct SwipeableTaskRow<Content: View, Accessory: View>: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AccentTheme.storageKey) private var accentTheme = AccentTheme.default

    let task: TaskItem
    var onTap: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 8) {
            TaskCheckbox(isChecked: false) {
                TaskActions.complete(task, in: modelContext)
            }

            Button(action: onTap) {
                content()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            accessory()
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !task.isCurrent {
                Button {
                    TaskActions.promoteToCurrent(task, in: modelContext)
                } label: {
                    Label("Doing now", systemImage: "target")
                }
                .tint(accentTheme.color)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                TaskActions.delete(task, in: modelContext)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
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
            if task.isChore {
                if task.isPaused {
                    Button {
                        TaskActions.resume(task, in: modelContext)
                    } label: {
                        Label("Resume chore", systemImage: "play.circle")
                    }
                } else {
                    Button {
                        TaskActions.pause(task, until: PauseDuration.default.resumeDate(),
                                          in: modelContext)
                    } label: {
                        Label("Pause for a week", systemImage: "pause.circle")
                    }
                }
            }
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
    }
}
