//
//  TipJarView.swift
//  ActuallyDidIt
//
//  The "Support the developer" row shown in Settings. It stays out of the way as a single row
//  and only reveals the tip options when tapped, so the tip jar never feels pushy. All the
//  StoreKit work lives in TipStore.
//

import SwiftUI
import StoreKit

struct TipJarView: View {
    @State private var store = TipStore()
    @State private var isExpanded = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                if store.products.isEmpty {
                    HStack {
                        Text("Loading…")
                            .foregroundStyle(.secondary)
                        Spacer()
                        ProgressView()
                    }
                } else {
                    ForEach(store.products) { product in
                        Button {
                            Task { await store.purchase(product) }
                        } label: {
                            HStack {
                                Text(emoji(for: product))
                                Text(product.displayName)
                                Spacer()
                                Text(product.displayPrice)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .disabled(store.purchaseInProgress)
                    }
                }
            } label: {
                Label("Support the developer", systemImage: "heart")
            }
        } footer: {
            Text("ActuallyDidIt is made by one person. If it's helping you, a tip keeps it going — thank you! 💜")
        }
        .task(id: isExpanded) {
            // Only reach out to the App Store once the user shows interest by expanding.
            if isExpanded && store.products.isEmpty {
                await store.loadProducts()
            }
        }
        .alert("Thank you! 💜", isPresented: $store.showThankYou) {
            Button("You're welcome") { }
        } message: {
            Text("Your support genuinely means a lot and helps keep ActuallyDidIt going.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    /// Falls back to a generic emoji if a product identifier isn't one we recognise.
    private func emoji(for product: Product) -> String {
        TipProduct(rawValue: product.id)?.emoji ?? "💜"
    }
}
