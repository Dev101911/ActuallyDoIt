//
//  SettingsView.swift
//  ActuallyDidIt
//
//  The app's settings sheet, reached from the gear button on the Now screen. Currently holds
//  the accent-colour theme; structured so further sections (nudges, etc.) can slot in later.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AccentTheme.storageKey) private var accentTheme = AccentTheme.default
    @AppStorage(AppearanceTheme.storageKey) private var appearanceTheme = AppearanceTheme.default

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

                TipJarView()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
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
