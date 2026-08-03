//
//  NowView.swift
//  ADHDoIt
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

    @AppStorage(AccentTheme.storageKey) private var accentTheme = AccentTheme.default

    @State private var showingLibrary = false
    @State private var showingAdd = false
    @State private var showingPickForMe = false
    @State private var showingSettings = false

    private var currentTask: TaskItem? {
        allTasks.first { $0.isCurrent }
    }

    private var upNext: [TaskItem] {
        TaskPrioritizer.upNext(from: allTasks, limit: 3)
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
                                    .listRowBackground(accentTheme.color.opacity(0.12))
                            } header: {
                                SectionHeader(title: "Doing now", systemImage: "target")
                            }
                        }

                        if !upNext.isEmpty {
                            Section {
                                ForEach(upNext) { task in
                                    TaskListRow(task: task)
                                }
                            } header: {
                                SectionHeader(title: currentTask != nil ? "Up next" : "Suggested next",
                                              systemImage: "arrow.down.to.line")
                            }
                        }

                        // Pick for me is only for choosing a focus — disabled while one is set.
                        Section {
                            Button {
                                showingPickForMe = true
                            } label: {
                                Label("Pick for me", systemImage: "dice")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
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
            .sheet(isPresented: $showingLibrary) { LibraryView() }
            .sheet(isPresented: $showingAdd) { AddEditTaskView() }
            .sheet(isPresented: $showingPickForMe) { PickForMeSheet() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
        }
    }
}

// MARK: - Doing now

private struct DoingNowSection: View {
    @Environment(\.modelContext) private var modelContext
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(task.surfacingReason.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(task.title)
                .font(.title.weight(.bold))
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

            Button {
                TaskActions.snooze(task, in: modelContext)
            } label: {
                Text("Snooze")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Shared

private struct SectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.secondary)
    }
}

/// Shown when nothing is actionable — an invitation, never a backlog.
private struct EmptyNowView: View {
    var onPickForMe: () -> Void
    var onBrowse: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

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
