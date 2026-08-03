//
//  FocusActivityLiveActivity.swift
//  FocusActivity
//
//  The Lock Screen and Dynamic Island presentation for the currently focused task.
//  The `FocusActivityAttributes` type it renders is defined in the shared
//  `FocusActivityAttributes.swift`, which is a member of both this extension and the app.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct FocusActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            // Lock Screen / banner presentation.
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.accentColor.opacity(0.12))
                .activitySystemActionForegroundColor(Color.accentColor)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "target")
                        .font(.title2)
                        .foregroundStyle(.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerText(start: context.state.focusStartedAt)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 64)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.reason.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(context.state.title)
                            .font(.headline)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "target")
                    .foregroundStyle(.tint)
            } compactTrailing: {
                TimerText(start: context.state.focusStartedAt)
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "target")
                    .foregroundStyle(.tint)
            }
        }
    }
}

/// A live, self-updating elapsed timer counting up from when focus began.
private struct TimerText: View {
    let start: Date

    var body: some View {
        Text(start, style: .timer)
            .monospacedDigit()
            .multilineTextAlignment(.center)
    }
}

/// The Lock Screen layout: reason + title on the left, a running timer on the right.
private struct LockScreenView: View {
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.reason.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(state.title)
                    .font(.headline)
                    .lineLimit(2)

                Label("\(state.estimatedMinutes) min", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(spacing: 4) {
                Image(systemName: "target")
                    .foregroundStyle(.tint)
                TimerText(start: state.focusStartedAt)
                    .font(.title3)
                    .foregroundStyle(.primary)
            }
        }
        .padding()
    }
}

// MARK: - Previews

extension FocusActivityAttributes {
    fileprivate static var preview: FocusActivityAttributes {
        FocusActivityAttributes(taskID: UUID().uuidString)
    }
}

extension FocusActivityAttributes.ContentState {
    fileprivate static var laundry: FocusActivityAttributes.ContentState {
        .init(title: "Fold the laundry", reason: "Due today",
              estimatedMinutes: 15, focusStartedAt: Date().addingTimeInterval(-120))
    }

    fileprivate static var email: FocusActivityAttributes.ContentState {
        .init(title: "Reply to Sam's email", reason: "To do",
              estimatedMinutes: 5, focusStartedAt: Date())
    }
}

#Preview("Notification", as: .content, using: FocusActivityAttributes.preview) {
    FocusActivityLiveActivity()
} contentStates: {
    FocusActivityAttributes.ContentState.laundry
    FocusActivityAttributes.ContentState.email
}
