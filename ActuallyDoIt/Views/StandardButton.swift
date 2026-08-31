//
//  StandardButton.swift
//  ActuallyDoIt
//
//  A single, reusable full-width button so every call site shares the same styling.
//  Modelled on the "Pick for me" button: large, full width, with an optional leading icon.
//  Use `.primary` for the prominent action (formerly "Pick for me") and `.secondary`
//  for the quieter, bordered action (formerly the "Choose a task" style).
//

import SwiftUI

/// The two visual weights a `StandardButton` can take.
enum StandardButtonRole {
    /// Filled, prominent — the main action on a screen.
    case primary
    /// Bordered, quieter — a supporting action.
    case secondary
}

/// A standardised, full-width button with an optional leading icon.
struct StandardButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AccentTheme.storageKey) private var accentTheme = AccentTheme.default

    let title: String
    var systemImage: String?
    var role: StandardButtonRole
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        role: StandardButtonRole = .primary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .modifier(RoleStyle(role: role, colorScheme: colorScheme, accent: accentTheme.color))
    }

    @ViewBuilder
    private var label: some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        // Primary fills with the tint, so its title/icon must stay white to read clearly.
        // Secondary inherits the tint colour (the current AccentTheme) like the old style.
        .modifier(PrimaryForeground(isPrimary: role == .primary))
    }
}

/// Forces white on the primary (filled) button; leaves the secondary button's title
/// to inherit the tint colour, matching the original bordered style.
private struct PrimaryForeground: ViewModifier {
    let isPrimary: Bool

    func body(content: Content) -> some View {
        if isPrimary {
            content.foregroundStyle(.white)
        } else {
            content
        }
    }
}

/// Selects the concrete button style for each role. The different styles return different
/// concrete types, so the choice is funnelled through this single modifier to keep
/// `StandardButton.body` one type.
///
/// In dark mode the primary button swaps its solid tint fill for a translucent accent fill
/// with a solid accent border, which sits more comfortably against dark backgrounds.
private struct RoleStyle: ViewModifier {
    let role: StandardButtonRole
    let colorScheme: ColorScheme
    let accent: Color

    func body(content: Content) -> some View {
        switch role {
        case .primary where colorScheme == .dark:
            content.buttonStyle(TintedOutlineButtonStyle(accent: accent))
        case .primary:
            content.buttonStyle(.borderedProminent)
        case .secondary:
            content.buttonStyle(SubtleSecondaryButtonStyle(accent: accent))
        }
    }
}

/// A quiet, on-theme secondary button: an opaque neutral fill nudged toward the accent,
/// with medium-weight accent text. Deliberately more subdued than SwiftUI's `.bordered`
/// style so it reads as a supporting action, not a prominent one.
private struct SubtleSecondaryButtonStyle: ButtonStyle {
    // A custom style doesn't dim automatically when disabled, so read the flag ourselves
    // to keep the "not tappable" affordance the built-in styles provide.
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    let accent: Color

    // Matches the capsule shape `.borderedProminent` uses at `.controlSize(.large)`.
    private let shape = Capsule()

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.medium)
            .foregroundStyle(accent)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(fill, in: shape)
            .contentShape(shape)
            .opacity(opacity(isPressed: configuration.isPressed))
    }

    /// An *opaque* fill so the button reads the same on any surface — the base level or an
    /// elevated sheet, whose background is lighter in dark mode. A translucent wash would
    /// composite with that surface and drift, which is especially obvious with the mono
    /// accent (pure white/black). The neutral base is nudged toward the accent to stay on-theme.
    private var fill: Color {
        let base = colorScheme == .dark ? Color(white: 0.17) : Color(white: 0.93)
        return base.mix(with: accent, by: 0.12)
    }

    private func opacity(isPressed: Bool) -> Double {
        if !isEnabled { return 0.4 }
        return isPressed ? 0.6 : 1
    }
}

/// A prominent button drawn as a translucent accent fill behind a solid accent border.
/// Used for the primary `StandardButton` in dark mode.
private struct TintedOutlineButtonStyle: ButtonStyle {
    let accent: Color

    // Matches the capsule shape `.borderedProminent` uses at `.controlSize(.large)`.
    private let shape = Capsule()

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(accent.opacity(0.25), in: shape)
            .overlay(shape.strokeBorder(accent, lineWidth: 1))
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

#Preview {
    VStack(spacing: 12) {
        StandardButton("Pick for me", systemImage: "dice", role: .primary) {}
        StandardButton("Choose a task", systemImage: "list.bullet", role: .secondary) {}
        StandardButton("Done", role: .primary) {}
    }
    .padding()
}
