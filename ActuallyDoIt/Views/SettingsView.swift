//
//  SettingsView.swift
//  ActuallyDoIt
//
//  The app's settings sheet, reached from the gear button on the Now screen. Currently holds
//  the accent-colour theme; structured so further sections (nudges, etc.) can slot in later.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AccentTheme.storageKey) private var accentTheme = AccentTheme.default
    @AppStorage(AppearanceTheme.storageKey) private var appearanceTheme = AppearanceTheme.default
    @AppStorage(ReviewPrompt.hasReviewedKey) private var hasReviewed = false

    @State private var showingTutorial = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Theme", selection: $appearanceTheme) {
                        ForEach(AppearanceTheme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Accent colour", selection: $accentTheme) {
                        ForEach(AccentTheme.allCases) { theme in
                            Label {
                                Text(theme.label)
                            } icon: {
                                Circle()
                                    .fill(theme.color)
                                    .frame(width: 20, height: 20)
                            }
                            .tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Accent colour sets the app's tint and the highlight on your focused task.")
                }

                Section {
                    NavigationLink {
                        NudgeTimesView()
                    } label: {
                        Label("Nudge time defaults", systemImage: "bell.badge")
                    }
                } header: {
                    Text("Nudges")
                } footer: {
                    Text("Set when reminders fire for each nudge level.")
                }

                Section {
                    Button {
                        showingTutorial = true
                    } label: {
                        Label("How it works", systemImage: "questionmark.circle")
                    }

                    Button {
                        if let url = ReviewPrompt.writeReviewURL {
                            openURL(url)
                        }
                        // Reviewing from here also stops the gentle monthly prompt.
                        hasReviewed = true
                    } label: {
                        Label("Rate ActuallyDoIt", systemImage: "star")
                    }
                } header: {
                    Text("Help")
                } footer: {
                    Text("Replay the quick tour, or leave a review on the App Store.")
                }

                Section {
                    NavigationLink {
                        TipJarView()
                    } label: {
                        Label("Support the developer", systemImage: "heart")
                    }
                } footer: {
                    Text("ActuallyDoIt is made by one person. If it's helping you, a tip keeps it going — thank you! 💜")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showingTutorial) { TutorialView() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
