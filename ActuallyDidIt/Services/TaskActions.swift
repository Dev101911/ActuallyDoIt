//
//  TaskActions.swift
//  ActuallyDidIt
//
//  Central place for mutations that must preserve domain invariants — in particular the
//  "one task in focus at a time" rule.
//
//  The store-level rules live in `TaskMutations` (shared with the widget extension). `TaskActions`
//  layers the app-only side effects on top: reconciling the Live Activity and nudges, and asking
//  WidgetKit to refresh the Home Screen widget so it reflects the change.
//

import Foundation
import SwiftData
import WidgetKit

enum TaskActions {

    /// Makes `task` the single current task, clearing focus from any other task first.
    static func promoteToCurrent(_ task: TaskItem, in context: ModelContext) {
        TaskMutations.setCurrent(task, in: context)
        FocusActivityController.shared.reconcile(in: context)
        NudgeScheduler.shared.reconcile(in: context)
        persistAndReloadWidgets(context)
    }

    /// Removes focus from every task except an optional one to keep.
    static func clearAllFocus(in context: ModelContext, except keep: TaskItem? = nil) {
        TaskMutations.clearAllFocus(in: context, except: keep)
        FocusActivityController.shared.reconcile(in: context)
        persistAndReloadWidgets(context)
    }

    /// Marks a task complete. For a Chore this re-arms the next occurrence instead of ending it.
    ///
    /// Note: verification is a later phase; for v1 this completes directly.
    static func complete(_ task: TaskItem, in context: ModelContext) {
        TaskMutations.complete(task, in: context)
        FocusActivityController.shared.reconcile(in: context)
        NudgeScheduler.shared.reconcile(in: context)
        persistAndReloadWidgets(context)
    }

    /// Reopens a completed task, moving it back to the pending pool.
    static func markUnfinished(_ task: TaskItem, in context: ModelContext) {
        task.status = .pending
        task.completedAt = nil
        NudgeScheduler.shared.reconcile(in: context)
        persistAndReloadWidgets(context)
    }

    /// Drops the task out of focus without completing it — used when the user can't do it right
    /// now. The task stays pending and eligible to be surfaced again.
    static func unfocus(_ task: TaskItem, in context: ModelContext) {
        task.focusStartedAt = nil
        FocusActivityController.shared.reconcile(in: context)
        NudgeScheduler.shared.reconcile(in: context)
        persistAndReloadWidgets(context)
    }

    /// Deletes a task. Routed through here (rather than calling `context.delete` directly) so
    /// that removing the currently focused task also ends its Live Activity.
    static func delete(_ task: TaskItem, in context: ModelContext) {
        context.delete(task)
        FocusActivityController.shared.reconcile(in: context)
        NudgeScheduler.shared.reconcile(in: context)
        persistAndReloadWidgets(context)
    }

    /// Flushes pending changes to the shared store, then asks WidgetKit to rebuild the Home Screen
    /// widget timelines. The explicit save matters because the widget runs in a *separate process*
    /// and reads the store from disk — without a save it would see stale data, since SwiftData's
    /// autosave is deferred.
    private static func persistAndReloadWidgets(_ context: ModelContext) {
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
