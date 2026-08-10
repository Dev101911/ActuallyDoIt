//
//  WidgetTaskIntents.swift
//  FocusActivity
//
//  App Intents backing the widget's interactive buttons. They run in the widget extension, open
//  the shared App Group store (without CloudKit — the app owns syncing), apply the same domain
//  rules the app uses via `TaskMutations`, then ask WidgetKit to refresh.
//

import AppIntents
import SwiftData
import WidgetKit

/// Marks the referenced task complete (re-arming it if it's a recurring Chore).
struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Task"

    @Parameter(title: "Task ID")
    var taskID: String

    init() {}
    init(taskID: String) { self.taskID = taskID }

    func perform() async throws -> some IntentResult {
        let container = try SharedStore.makeContainer(cloudKit: false)
        let context = ModelContext(container)

        if let task = SharedStore.task(withID: taskID, in: context) {
            TaskMutations.complete(task, in: context)
            try context.save()
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
