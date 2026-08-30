//
//  TutorialView.swift
//  ActuallyDidIt
//
//  A first-run, swipe-through tour of the app. Each page pairs a lightweight SwiftUI illustration
//  (rendered from the app's own building blocks, so it always matches the current theme) with a
//  short explanation of one feature. Auto-presented once on first launch and replayable from
//  Settings — see `storageKey`.
//

import SwiftUI

struct TutorialView: View {
    /// `@AppStorage` flag recording that the user has seen the tour at least once. First launch
    /// reads this to decide whether to auto-present.
    static let storageKey = "hasSeenTutorial"

    @Environment(\.dismiss) private var dismiss
    @AppStorage(TutorialView.storageKey) private var hasSeenTutorial = false

    @State private var selection = 0

    private let steps = TutorialStep.allCases

    var body: some View {
        VStack(spacing: 0) {
            // Skip is always available so the tour never traps the user.
            HStack {
                Spacer()
                Button("Skip") { finish() }
                    .font(.subheadline)
                    .padding()
            }

            TabView(selection: $selection) {
                ForEach(Array(steps.enumerated()), id: \.element) { index, step in
                    TutorialPageView(step: step)
                        .tag(index)
                        .padding(.horizontal, 28)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            PageIndicator(count: steps.count, current: selection)
                .padding(.vertical, 20)

            StandardButton(isLastStep ? "Get started" : "Continue", role: .primary, action: advance)
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
        }
    }

    private var isLastStep: Bool { selection >= steps.count - 1 }

    private func advance() {
        if isLastStep {
            finish()
        } else {
            withAnimation { selection += 1 }
        }
    }

    private func finish() {
        hasSeenTutorial = true
        dismiss()
    }
}

// MARK: - Page

private struct TutorialPageView: View {
    let step: TutorialStep

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)

            step.illustration
                .frame(maxWidth: .infinity)
                .frame(height: 240)

            VStack(spacing: 12) {
                Text(step.title)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(step.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct PageIndicator: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .frame(width: index == current ? 20 : 8, height: 8)
                    .animation(.snappy, value: current)
            }
        }
    }
}

// MARK: - Steps

private enum TutorialStep: CaseIterable, Hashable {
    case welcome
    case doingNow
    case pickForMe
    case library
    case nudges
    case widgets

    var title: String {
        switch self {
        case .welcome:           return "One thing at a time"
        case .doingNow:          return "Doing now"
        case .pickForMe:         return "Can't decide? Pick for me"
        case .library:           return "Everything in its place"
        case .nudges:            return "Nudges that fit the task"
        case .widgets:           return "Always a glance away"
        }
    }

    var message: String {
        switch self {
        case .welcome:
            return "Forget tasks, or swipe reminders away and never come back? ActuallyDidIt keeps resurfacing the one thing to do next — and nudges you until you've actually done it. Here's the quick tour."
        case .doingNow:
            return "The Now screen puts a single task front and centre. Tap Done when you finish it, or “Can't do this now” to step away without losing your place."
        case .pickForMe:
            return "Frozen by a full list? Tap Pick for me and the app picks a sensible task to start. “Up next” always previews what's most pressing — never the whole backlog."
        case .library:
            return "Your full backlog lives in All tasks — one-off to-dos and recurring chores (daily, weekly, or monthly), out of sight until you need it. Tag tasks like Home or Work, then filter the Now screen to just those tags."
        case .nudges:
            return "Give each task its own intensity — Gentle, Persistent, or Relentless — and set exactly when its reminders fire, right there in the task. Away for a while? Pause a chore and its nudges rest until you're back."
        case .widgets:
            return "Add the widget or Lock Screen Live Activity to keep your current task in view — and tick it done without even opening the app."
        }
    }

    @ViewBuilder
    var illustration: some View {
        switch self {
        case .welcome:           WelcomeIllustration()
        case .doingNow:          DoingNowIllustration()
        case .pickForMe:         PickForMeIllustration()
        case .library:           LibraryIllustration()
        case .nudges:            NudgesIllustration()
        case .widgets:           WidgetsIllustration()
        }
    }
}

// MARK: - Illustrations
//
// Small mock UI rendered from SwiftUI primitives. They evoke each screen rather than reproducing
// it exactly, and pick up the user's accent tint automatically via `Color.accentColor` / `.tint`.

/// A rounded, tinted panel that hosts each illustration's mock content.
private struct IllustrationCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: 300)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 1)
            )
    }
}

private struct MockLine: View {
    var widthFraction: CGFloat
    var emphasized = false

    var body: some View {
        Capsule()
            .fill(emphasized ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
            .frame(height: emphasized ? 10 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .scaleEffect(x: widthFraction, anchor: .leading)
    }
}

private struct WelcomeIllustration: View {
    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 120))
            .foregroundStyle(.tint)
            .symbolRenderingMode(.hierarchical)
    }
}

private struct DoingNowIllustration: View {
    var body: some View {
        IllustrationCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("DOING NOW")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)

                Text("Reply to Sam's email")
                    .font(.title3.weight(.bold))

                Label("About 10 min", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.tint))
                    .padding(.top, 4)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.20), lineWidth: 1)
            )
        }
    }
}

private struct PickForMeIllustration: View {
    var body: some View {
        IllustrationCard {
            VStack(spacing: 16) {
                Image(systemName: "dice.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(0..<3, id: \.self) { index in
                        MockLine(widthFraction: [0.9, 0.6, 0.75][index])
                    }
                }
            }
        }
    }
}

private struct LibraryIllustration: View {
    var body: some View {
        IllustrationCard {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(0..<4, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        MockLine(widthFraction: [0.8, 0.55, 0.9, 0.65][index], emphasized: index == 0)
                        MockLine(widthFraction: [0.4, 0.3, 0.5, 0.35][index])
                    }
                }
            }
        }
    }
}

private struct NudgesIllustration: View {
    private let levels = ["Gentle", "Persistent", "Relentless"]

    var body: some View {
        IllustrationCard {
            VStack(spacing: 14) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 10) {
                    ForEach(Array(levels.enumerated()), id: \.element) { index, level in
                        HStack {
                            Text(level)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            HStack(spacing: 3) {
                                ForEach(0...index, id: \.self) { _ in
                                    Image(systemName: "bell.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.accentColor.opacity(0.10))
                        )
                    }
                }
            }
        }
    }
}

private struct WidgetsIllustration: View {
    var body: some View {
        HStack(spacing: 16) {
            // Home Screen widget
            VStack(alignment: .leading, spacing: 8) {
                Text("NOW")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tint)
                MockLine(widthFraction: 0.9, emphasized: true)
                MockLine(widthFraction: 0.6)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
            .padding(14)
            .frame(width: 120, height: 120)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )

            // Live Activity pill
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "target")
                        .foregroundStyle(.tint)
                    MockLine(widthFraction: 0.7, emphasized: true)
                }
                MockLine(widthFraction: 0.5)
            }
            .padding(14)
            .frame(width: 130)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }
}

#Preview {
    TutorialView()
}
