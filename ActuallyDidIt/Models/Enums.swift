//
//  Enums.swift
//  ActuallyDidIt
//
//  Supporting value types for the task domain.
//

import Foundation
import SwiftUI
import UIKit

/// The lifecycle state of a task.
///
/// A task is never marked `completed` directly from a dismissed reminder; it passes through
/// `awaitingVerification` first (see the completion-verification flow in the plan).
enum TaskStatus: String, Codable, CaseIterable {
    case pending
    case awaitingVerification
    case completed
}

/// How a task's completion is confirmed before it counts as done.
enum VerificationMethod: String, Codable, CaseIterable {
    case tapToConfirm       // simple "Yes, I really did it" tap
    case delayedRecheck     // re-ask a few minutes later

    var label: String {
        switch self {
        case .tapToConfirm: return "Tap to confirm"
        case .delayedRecheck: return "Re-check later"
        }
    }
}

/// How aggressively the nudge engine re-reminds the user about a task.
enum NudgeIntensity: String, Codable, CaseIterable {
    case gentle
    case persistent
    case relentless

    var label: String {
        switch self {
        case .gentle: return "Gentle"
        case .persistent: return "Persistent"
        case .relentless: return "Relentless"
        }
    }

    /// One-line explanation of the reminder cadence, shown under the picker.
    var detail: String {
        switch self {
        case .gentle: return "One reminder in the morning."
        case .persistent: return "Three reminders spread through the day."
        case .relentless: return "A reminder every hour, 9am–9pm, until it's done."
        }
    }

    /// Higher rank = more urgent. Used when ranking tasks for the "Up next" list.
    var rank: Int {
        switch self {
        case .gentle: return 0
        case .persistent: return 1
        case .relentless: return 2
        }
    }
}

/// A user-selectable accent colour for the app. Backed by `String` so it stores directly in
/// `@AppStorage`, and limited to a curated set of presets to match the app's minimal feel.
/// This is the single source of truth behind both the app-wide `.tint` and the "Doing now"
/// row highlight, so those two always stay in sync.
enum AccentTheme: String, Codable, CaseIterable, Identifiable {
    case blue
    case teal
    case indigo
    case pink
    case orange
    case red
    case green
    case mono

    /// The default used when no preference has been saved yet.
    static let `default`: AccentTheme = .green

    /// The `@AppStorage` key shared by every view that reads the theme.
    static let storageKey = "accentTheme"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .teal: return .teal
        case .indigo: return .indigo
        case .pink: return .pink
        case .orange: return .orange
        case .red: return .red
        case .green: return .green
        case .mono: return .primary
        }
    }

    var label: String {
        switch self {
        case .blue: return "Blue"
        case .teal: return "Teal"
        case .indigo: return "Indigo"
        case .pink: return "Pink"
        case .orange: return "Orange"
        case .red: return "Red"
        case .green: return "Green"
        case .mono: return "Monochrome"
        }
    }
}

/// The user's preferred light/dark appearance. Backed by `String` for `@AppStorage`.
/// `.system` follows the device setting; the other cases force a scheme via
/// `.preferredColorScheme`.
enum AppearanceTheme: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    /// The default used when no preference has been saved yet.
    static let `default`: AppearanceTheme = .system

    /// The `@AppStorage` key shared by every view that reads the appearance.
    static let storageKey = "appearanceTheme"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// The window override style. `.unspecified` reliably reverts to the device setting,
    /// unlike `preferredColorScheme(nil)` which can fail to clear a previously forced scheme.
    var uiStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}
