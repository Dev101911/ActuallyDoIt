//
//  ContentView.swift
//  ActuallyDidIt
//
//  Created by Devin Harmse on 03/08/2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        NowView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: TaskItem.self, inMemory: true)
        .environment(NotificationRouter())
}
