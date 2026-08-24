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

    @Query private var allTasks: [TaskItem]

    @AppStorage(TutorialView.storageKey) private var hasSeenTutorial = false

    @State private var showingLibrary = false
    @State private var showingAdd = false
    @State private var showingPickForMe = false
    @State private var showingSettings = false
    @State private var showingTutorial = false

    private var currentTask: TaskItem? {
        allTasks.first { $0.isCurrent }
    }

    private var upNext: [TaskItem] {
        TaskPrioritizer.upNext(from: allTasks, limit: 3)
            .sorted(by: TaskItem.byOverdueThenDueDate)
    }

    private var isEmpty: Bool {
        currentTask == nil && upNext.isEmpty
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

                        if !upNext.isEmpty {
                            Section {
                                ForEach(upNext) { task in
                                    TaskListRow(task: task)
                                }
                            } header: {
                                Text(currentTask != nil ? "Up next" : "Suggested next")
                            }
                        }

                        // Pick for me is only for choosing a focus — disabled while one is set.
                        Section {
                            Button {
                                showingPickForMe = true
                            } label: {
                                Label("Pick for me", systemImage: "dice")
                                    .frame(maxWidth: .infinity)
                                    // Keep the dice icon the same white as the title.
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            // A disabled `.borderedProminent` button dims automatically, so it's
                            // clear the button isn't tappable when a task is already in focus.
                            .disabled(currentTask != nil)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
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
            .fullScreenCover(isPresented: $showingTutorial) { TutorialView() }
            .task {
                // Auto-present the tour once, on first launch.
                if !hasSeenTutorial { showingTutorial = true }
            }
        }
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

            Button {
                TaskActions.complete(task, in: modelContext)
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
                Button(action: onPickForMe) {
                    Label("Pick for me", systemImage: "dice")
                        .frame(maxWidth: .infinity)
                        // Keep the dice icon the same white as the title.
                        .foregroundStyle(.white)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: onBrowse) {
                    Label("Choose a task", systemImage: "list.bullet")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }
}

#Preview {
    NowView()
        .modelContainer(SampleData.previewContainer)
}
