//
//  PickForMeSheet.swift
//  ActuallyDidIt
//
//  Removes decision paralysis: the user says how much time they have, and the app immediately
//  picks a single fitting task, sets it as the current focus, and closes — no confirmation.
//

import SwiftUI
import SwiftData

struct PickForMeSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allTasks: [TaskItem]

    /// Set when a chosen time window had no fitting task, so we can show an empty state.
    @State private var noMatchMinutes: Int?

    private let timeOptions = [5, 15, 30, 60]

    /// Actionable tasks that fit within the chosen time budget.
    private func candidates(within minutes: Int) -> [TaskItem] {
        allTasks.filter { $0.isActionable && !$0.isCurrent && $0.estimatedMinutes <= minutes }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let noMatchMinutes {
                    noMatchView(minutes: noMatchMinutes)
                } else {
                    timePicker
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Pick for me")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Steps

    private var timePicker: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("How much time do you have?")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                ForEach(timeOptions, id: \.self) { minutes in
                    Button {
                        choose(minutes)
                    } label: {
                        Text("\(minutes) minutes")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            Spacer()
        }
    }

    private func noMatchView(minutes: Int) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "hourglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Nothing fits in \(minutes) minutes")
                .font(.title3.weight(.semibold))
            Text("Try a longer window, or take a break — that counts too.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Try a different time") {
                noMatchMinutes = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    // MARK: - Logic

    private func choose(_ minutes: Int) {
        if let chosen = candidates(within: minutes).randomElement() {
            TaskActions.promoteToCurrent(chosen, in: modelContext)
            dismiss()
        } else {
            noMatchMinutes = minutes
        }
    }
}

#Preview {
    PickForMeSheet()
        .modelContainer(SampleData.previewContainer)
}
