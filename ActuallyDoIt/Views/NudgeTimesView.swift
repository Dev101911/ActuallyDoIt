//
//  NudgeTimesView.swift
//  ActuallyDoIt
//
//  Lets the user set the times of day that nudges fire for each intensity level. Reached from the
//  Settings sheet. Editing any time immediately re-reconciles the scheduler so pending reminders
//  pick up the change.
//

import SwiftUI

struct NudgeTimesView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage(NudgeSchedule.gentleKey) private var gentle = NudgeSchedule.gentleDefault
    @AppStorage(NudgeSchedule.persistentKeys[0]) private var persistentFirst = NudgeSchedule.persistentDefaults[0]
    @AppStorage(NudgeSchedule.persistentKeys[1]) private var persistentSecond = NudgeSchedule.persistentDefaults[1]
    @AppStorage(NudgeSchedule.persistentKeys[2]) private var persistentThird = NudgeSchedule.persistentDefaults[2]
    @AppStorage(NudgeSchedule.relentlessStartKey) private var relentlessStart = NudgeSchedule.relentlessStartDefault
    @AppStorage(NudgeSchedule.relentlessEndKey) private var relentlessEnd = NudgeSchedule.relentlessEndDefault

    var body: some View {
        Form {
            Section {
                DatePicker("Reminder", selection: timeBinding($gentle), displayedComponents: .hourAndMinute)
            } header: {
                Text("Gentle")
            } footer: {
                Text("One reminder each day.")
            }

            Section {
                DatePicker("First", selection: timeBinding($persistentFirst), displayedComponents: .hourAndMinute)
                DatePicker("Second", selection: timeBinding($persistentSecond), displayedComponents: .hourAndMinute)
                DatePicker("Third", selection: timeBinding($persistentThird), displayedComponents: .hourAndMinute)
            } header: {
                Text("Persistent")
            } footer: {
                Text("Three reminders spread through the day.")
            }

            Section {
                DatePicker("Start", selection: timeBinding($relentlessStart), displayedComponents: .hourAndMinute)
                DatePicker("End", selection: timeBinding($relentlessEnd), displayedComponents: .hourAndMinute)
            } header: {
                Text("Relentless")
            } footer: {
                Text("A reminder every hour between these waking hours, until the task is done.")
            }
        }
        .navigationTitle("Nudge times")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Bridges a minutes-from-midnight `@AppStorage` value to the `Date` a `DatePicker` expects,
    /// and re-reconciles the scheduler whenever the user picks a new time.
    private func timeBinding(_ source: Binding<Int>) -> Binding<Date> {
        Binding<Date>(
            get: { NudgeSchedule.date(fromMinutes: source.wrappedValue) },
            set: { newValue in
                source.wrappedValue = NudgeSchedule.minutes(from: newValue)
                NudgeScheduler.shared.reconcile(in: modelContext)
            }
        )
    }
}

#Preview {
    NavigationStack {
        NudgeTimesView()
    }
}
