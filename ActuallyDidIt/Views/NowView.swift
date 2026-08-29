//
//  NowView.swift
//  ActuallyDidIt
//
//  The home screen. Leads with the single task you're "Doing now", followed by a short,
//  curated "Up next" preview of the most pressing tasks — never the whole backlog. The full
//  list lives behind the opt-in Library.
//

import SwiftUI
import SwiftData

struct NowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NotificationRouter.self) private var notificationRouter

    @Query private var allTasks: [TaskItem]

    @AppStorage(TutorialView.storageKey) private var hasSeenTutorial = false

    @State private var showingLibrary = false
    @State private var showingAdd = false
    @State private var showingPickForMe = false
    @State private var showingSettings = false
    @State private var showingTutorial = false
    /// The task to open, set when the user taps a task's notification.
    @State private var routedTask: TaskItem?

    private var currentTask: TaskItem? {
        allTasks.first { $0.isCurrent }
    }

    /// Overdue + due-today actionable tasks — the time-critical "Today" group.
    private var dueToday: [TaskItem] {
        TaskPrioritizer.dueToday(from: allTasks)
    }

    /// Forward-looking preview, excluding anything already shown under "Today".
    private var upNext: [TaskItem] {
        TaskPrioritizer.upNext(from: allTasks, excludingIDs: Set(dueToday.map(\.id)), limit: 3)
            .sorted(by: TaskItem.byOverdueThenDueDate)
    }

    /// Every task due today or earlier (overdue + today), regardless of status — powers the
    /// day-progress ring so it reflects all outstanding and completed work for today.
    private var todayScheduled: [TaskItem] {
        let todayStart = Calendar.current.startOfDay(for: Date())
        return allTasks.filter { task in
            guard let due = task.dueDate else { return false }
            return Calendar.current.startOfDay(for: due) <= todayStart
        }
    }

    private var todayDoneCount: Int {
        todayScheduled.filter { $0.status == .completed }.count
    }

    /// Everything finished today — a "look what you got done" recap at the bottom of Now,
    /// newest first. Includes finished chores: completing a chore re-arms it to `.pending` for its
    /// next occurrence but keeps `completedAt` set, so it still counts as done for today.
    private var completedToday: [TaskItem] {
        allTasks
            .filter { task in
                guard let completedAt = task.completedAt,
                      Calendar.current.isDateInToday(completedAt) else { return false }
                return task.status == .completed || task.isChore
            }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    /// Whether to show the Today section at all: something pending, or everything done today.
    private var showTodaySection: Bool {
        !dueToday.isEmpty || !todayScheduled.isEmpty
    }

    private var isEmpty: Bool {
        currentTask == nil && dueToday.isEmpty && upNext.isEmpty && todayScheduled.isEmpty
            && completedToday.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if isEmpty {
                    EmptyNowView(
                        onPickForMe: { showingPickForMe = true },
                        onBrowse: { showingLibrary = true }
                    )
                    .padding()
                } else {
                    List {
                        if let currentTask {
                            Section {
                                DoingNowSection(task: currentTask)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            } header: {
                                Text("Doing now")
                            }
                        }

                        if showTodaySection {
                            Section {
                                if dueToday.isEmpty {
                                    // Everything due today is done — a quiet win, not empty rows.
                                    Label("All done for today", systemImage: "checkmark.circle.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(dueToday) { task in
                                        TaskListRow(task: task)
                                    }
                                }
                            } header: {
                                HStack {
                                    Text("Today")
                                    Spacer()
                                    if !todayScheduled.isEmpty {
                                        DayProgressBadge(done: todayDoneCount, total: todayScheduled.count)
                                    }
                                }
                            }
                        }

                        if !upNext.isEmpty {
                            Section {
                                ForEach(upNext) { task in
                                    TaskListRow(task: task)
                                }
                            } header: {
                                Text(currentTask != nil ? "Up next" : "Suggested next")
                            }
                        }

                        if !completedToday.isEmpty {
                            Section {
                                ForEach(completedToday) { task in
                                    CompletedTaskRow(task: task)
                                }
                            } header: {
                                Text("Completed today")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Now")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingLibrary = true
                    } label: {
                        Label("All tasks", systemImage: "list.bullet")
                    }
                }
                // Pick for me lives quietly in the toolbar now — only for choosing a focus, so it's
                // disabled while one is already set.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingPickForMe = true
                    } label: {
                        Label("Pick for me", systemImage: "dice")
                    }
                    .disabled(currentTask != nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add task", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingLibrary) { LibraryView().interactiveDismissDisabled() }
            .sheet(isPresented: $showingAdd) { AddEditTaskView().interactiveDismissDisabled() }
            .sheet(isPresented: $showingPickForMe) { PickForMeSheet().interactiveDismissDisabled() }
            .sheet(isPresented: $showingSettings) { SettingsView().interactiveDismissDisabled() }
            .sheet(item: $routedTask) { task in
                TaskDetailView(task: task)
            }
            .fullScreenCover(isPresented: $showingTutorial) { TutorialView() }
            .task {
                // Auto-present the tour once, on first launch.
                if !hasSeenTutorial { showingTutorial = true }
            }
            // Open the tapped task's detail. Handle both an id set before the view appeared (a
            // notification that cold-launched the app) and later taps while it's on screen.
            .task { openRoutedTask(notificationRouter.selectedTaskID) }
            .onChange(of: notificationRouter.selectedTaskID) { _, id in
                openRoutedTask(id)
            }
        }
    }

    /// Presents the detail view for the task matching `id`, then clears the router so the same task
    /// can be reopened by a later tap. Does nothing if the task no longer exists (e.g. completed or
    /// deleted since the notification fired).
    private func openRoutedTask(_ id: UUID?) {
        guard let id, let task = allTasks.first(where: { $0.id == id }) else { return }
        routedTask = task
        notificationRouter.selectedTaskID = nil
    }
}

// MARK: - Doing now

private struct DoingNowSection: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AccentTheme.storageKey) private var accentTheme = AccentTheme.default
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(task.surfacingReason.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(accentTheme.color)

            Text(task.title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.leading)

            Label(task.estimatedTimeLabel, systemImage: "clock")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let notes = task.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            StandardButton("Done", role: .primary) {
                TaskActions.complete(task, in: modelContext)
            }
            .padding(.top, 4)

            // Demoted to a quiet text button so "Done" is unambiguously the primary action.
            Button {
                TaskActions.unfocus(task, in: modelContext)
            } label: {
                Text("Can't do this now")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(accentTheme.color.opacity(0.10), in: .rect(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(accentTheme.color.opacity(0.20), lineWidth: 1)
        )
    }
}

// MARK: - Completed today

/// A recap row for a task finished today: a checked box (tap to reopen) and the struck-through
/// title. Mirrors the Library's completed rows so the checkbox behaves consistently everywhere.
private struct CompletedTaskRow: View {
    @Environment(\.modelContext) private var modelContext
    let task: TaskItem

    var body: some View {
        HStack(spacing: 8) {
            TaskCheckbox(isChecked: true) {
                TaskActions.markUnfinished(task, in: modelContext)
            }
            TaskRowView(task: task, isCompleted: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Today progress

/// A compact "done / total" ring for the tasks scheduled today, shown in the Today section header.
/// Glanceable day-load without competing with the "Doing now" hero.
private struct DayProgressBadge: View {
    @AppStorage(AccentTheme.storageKey) private var accentTheme = AccentTheme.default
    let done: Int
    let total: Int

    private var fraction: Double {
        total > 0 ? Double(done) / Double(total) : 0
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("\(done)/\(total)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .stroke(accentTheme.color.opacity(0.20), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(accentTheme.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's progress")
        .accessibilityValue("\(done) of \(total) done")
    }
}

// MARK: - Shared

/// Shown when nothing is actionable — an invitation, never a backlog.
private struct EmptyNowView: View {
    var onPickForMe: () -> Void
    var onBrowse: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Nothing on your plate")
                    .font(.title2.weight(.semibold))
                Text("Pick one thing to focus on — just one.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                StandardButton("Pick for me", systemImage: "dice", role: .secondary, action: onPickForMe)
                StandardButton("Choose a task", systemImage: "list.bullet", role: .secondary, action: onBrowse)
            }
        }
    }
}

#Preview {
    NowView()
        .modelContainer(SampleData.previewContainer)
        .environment(NotificationRouter())
}
