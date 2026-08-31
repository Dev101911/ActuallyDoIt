//
//  ReviewPrompt.swift
//  ActuallyDoIt
//
//  Central home for App Store reviews: the app's store ID, the "write a review" deep link, and the
//  persisted state that drives a gentle, once-a-month ask.
//
//  Note: iOS gives apps no signal that a review was actually submitted. We treat "the user tapped
//  through to the App Store to review" (from the monthly prompt or the Settings button) as reviewed,
//  and never ask again after that.
//

import SwiftUI

enum ReviewPrompt {
    // TODO: Replace with the app's numeric App Store ID once it's published
    // (the digits from the App Store URL, e.g. apps.apple.com/app/id6480000000).
    static let appStoreID = "0000000000"

    /// Deep link that opens the App Store straight to the review composer.
    static var writeReviewURL: URL? {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }

    /// How long to wait between asks (and before the very first ask, measured from install).
    static let interval: TimeInterval = 30 * 24 * 60 * 60

    // MARK: - Persisted state (AppStorage keys)

    /// Set once the user has taken us up on reviewing — stops all future asks.
    static let hasReviewedKey = "review.hasReviewed"
    /// When the monthly prompt was last shown (`Date.timeIntervalSinceReferenceDate`, 0 == never).
    static let lastPromptKey = "review.lastPromptDate"
    /// First launch, used to anchor the first prompt roughly a month after install.
    static let firstLaunchKey = "review.firstLaunchDate"
}

// MARK: - Monthly prompt

/// Attaches the gentle once-a-month review ask to a view. Evaluates on appear: the first prompt lands
/// about a month after install, then monthly, and only until the user reviews (or declines for good).
private struct ReviewPromptModifier: ViewModifier {
    @Environment(\.openURL) private var openURL

    @AppStorage(ReviewPrompt.hasReviewedKey) private var hasReviewed = false
    @AppStorage(ReviewPrompt.lastPromptKey) private var lastPromptDate = 0.0
    @AppStorage(ReviewPrompt.firstLaunchKey) private var firstLaunchDate = 0.0

    @State private var showingPrompt = false

    func body(content: Content) -> some View {
        content
            .task { evaluate() }
            .alert("Enjoying ActuallyDoIt?", isPresented: $showingPrompt) {
                Button("Sure, I'll review") {
                    if let url = ReviewPrompt.writeReviewURL { openURL(url) }
                    hasReviewed = true
                }
                Button("Maybe later", role: .cancel) {}
                Button("Don't ask again") { hasReviewed = true }
            } message: {
                Text("If it's helping you get things done, a quick App Store review would mean a lot — it only takes a moment. 💜")
            }
    }

    /// Decides whether to surface the prompt this launch, and records that it fired.
    private func evaluate() {
        guard !hasReviewed else { return }

        let now = Date.now.timeIntervalSinceReferenceDate
        if firstLaunchDate == 0 {
            firstLaunchDate = now
        }

        // Count from the last prompt, falling back to install time for the first ask.
        let anchor = lastPromptDate == 0 ? firstLaunchDate : lastPromptDate
        guard now - anchor >= ReviewPrompt.interval else { return }

        // Consume this cycle regardless of the user's choice, so declining waits a full month.
        lastPromptDate = now
        showingPrompt = true
    }
}

extension View {
    /// Shows a gentle App Store review ask about once a month, until the user reviews or opts out.
    func monthlyReviewPrompt() -> some View {
        modifier(ReviewPromptModifier())
    }
}
