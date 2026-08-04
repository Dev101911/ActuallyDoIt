//
//  TipStore.swift
//  ActuallyDidIt
//
//  Loads and purchases the "support the developer" tips. Tips are consumable in-app
//  purchases, so there's nothing to unlock or restore — a purchase is simply a one-off
//  thank-you. StoreKit 2 handles the receipt/verification; we just finish the transaction.
//

import Foundation
import StoreKit

/// The tip products offered in Settings, smallest to largest.
///
/// The raw values must match the product identifiers configured in App Store Connect (and in
/// the bundled `Tips.storekit` file used for local testing).
enum TipProduct: String, CaseIterable, Identifiable {
    case small = "com.devinharmse.ActuallyDidIt.tip.small"
    case medium = "com.devinharmse.ActuallyDidIt.tip.medium"
    case large = "com.devinharmse.ActuallyDidIt.tip.large"

    var id: String { rawValue }

    /// Emoji shown alongside the tip so the list reads at a glance.
    var emoji: String {
        switch self {
        case .small: "☕️"
        case .medium: "🍕"
        case .large: "🎉"
        }
    }
}

@MainActor
@Observable
final class TipStore {

    /// Products loaded from the App Store, ordered smallest to largest.
    private(set) var products: [Product] = []

    /// True while a purchase is in flight, so the UI can disable the buttons.
    private(set) var purchaseInProgress = false

    /// Set after a successful tip so the UI can say thank you.
    var showThankYou = false

    /// Surfaced to the user when loading or purchasing fails.
    var errorMessage: String?

    private let productIDs = TipProduct.allCases.map(\.rawValue)

    /// Fetches the tip products from the App Store, sorted to match `TipProduct`'s order.
    func loadProducts() async {
        do {
            let fetched = try await Product.products(for: productIDs)
            products = fetched.sorted { lhs, rhs in
                let order = productIDs
                return (order.firstIndex(of: lhs.id) ?? 0) < (order.firstIndex(of: rhs.id) ?? 0)
            }
        } catch {
            errorMessage = "Couldn't load tips. Please try again later."
        }
    }

    /// Purchases a tip. Because tips are consumable there's nothing to persist — we verify the
    /// transaction and finish it so StoreKit doesn't keep redelivering it.
    func purchase(_ product: Product) async {
        guard !purchaseInProgress else { return }
        purchaseInProgress = true
        defer { purchaseInProgress = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                showThankYou = true
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "The purchase couldn't be completed."
        }
    }

    /// Unwraps a StoreKit verification result, throwing if the signature check failed.
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    private enum StoreError: Error {
        case failedVerification
    }
}
