//
//  TipJarView.swift
//  ActuallyDoIt
//
//  The "Support the developer" screen, pushed from a row in Settings. It lists the available tips
//  and handles the purchase flow. All the StoreKit work lives in TipStore.
//

import SwiftUI
import StoreKit

struct TipJarView: View {
    @State private var store = TipStore()

    var body: some View {
        Form {
            Section {
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
            } footer: {
                Text("ActuallyDoIt is made by one person. If it's helping you, a tip keeps it going — thank you! 💜")
            }
        }
        .navigationTitle("Support the developer")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.products.isEmpty {
                await store.loadProducts()
            }
        }
        .alert("Thank you! 💜", isPresented: $store.showThankYou) {
            Button("You're welcome") { }
        } message: {
            Text("Your support genuinely means a lot and helps keep ActuallyDoIt going.")
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

#Preview {
    NavigationStack {
        TipJarView()
    }
}
