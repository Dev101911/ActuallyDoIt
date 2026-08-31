# ActuallyDoIt — Application Plan

## 1. Overview

**ActuallyDoIt** is an iOS reminders app designed specifically for people with ADHD. Unlike
conventional reminder apps that fire a single notification and fall silent, ActuallyDoIt is built
around two core principles:

1. **Persistent nudging** — it keeps poking the user until a task is actually addressed, rather
   than letting a reminder be dismissed and forgotten. For high-priority tasks it can escalate to
   **critical alerts** (which bypass silent mode and Do Not Disturb) and pin a **Live Activity**
   to the Lock Screen / Dynamic Island that cannot simply be swiped away.
2. **Completion verification** — it distinguishes between a reminder being *swiped away* and a
   task being *genuinely done*, asking for lightweight confirmation before considering a task
   complete.
3. **One thing at a time** — the app never confronts the user with a wall of everything they have
   to do. By default it surfaces a **single current task** to focus on; the full list exists but
   is something you *choose* to open, not the front door. This is the guiding constraint that
   overrides the other two: nudging, Live Activities, and the home screen all revolve around the
   one task in front of you right now.

The user's tasks sync across their devices via **CloudKit**, so a reminder set on the iPhone is
present on the iPad too, and the task list survives losing a device.

On top of the reminder engine, the app organises work into **ToDos** and **Chores**, and offers a
**"Pick For Me"** feature that removes the paralysis of choosing what to work on by randomly
selecting a *single* task that fits the time the user has available — reinforcing the
one-thing-at-a-time model.

### Design principle: reduce overwhelm

Everything in ActuallyDoIt is measured against one question: *does this help the user do the next
thing, or does it pile more onto their plate?* Concretely:

- The home screen leads with **one task**, not a list.
- Nudges and the Live Activity concern only the **current** task, never a backlog digest.
- Seeing the full list is a deliberate, opt-in action.
- Counts, badges, and "you have 37 things to do" pressure are avoided by default.

### Target platform & stack

| Concern            | Choice                                                        |
|--------------------|--------------------------------------------------------------|
| Platform           | iOS 18+ (iPhone first; iPad as a stretch goal)               |
| UI                 | SwiftUI                                                       |
| Persistence        | SwiftData (already scaffolded in the template)               |
| Sync               | CloudKit via SwiftData (`.automatic` iCloud sync)            |
| Notifications      | `UserNotifications` (incl. critical alerts)                  |
| Live presence      | ActivityKit + WidgetKit (Live Activities / Dynamic Island)   |
| Concurrency        | Swift `async`/`await` (no Combine, per project conventions)  |
| Architecture       | MV(VM-light) — SwiftUI views + `@Observable` service objects |

---

## 2. Core Concepts & Domain Model

The current template ships a single placeholder `Item` model. That will be replaced by a richer
domain.

### 2.1 Task types

The app splits tasks into two visual and behavioural categories, driven by **whether the task
recurs**:

- **ToDo** — a one-off task with no recurring schedule (e.g. "Email the landlord"). It exists
  until it is completed, then it is done.
- **Chore** — a recurring task tied to a repeating schedule (e.g. "Take out the bins" every
  Tuesday, "Water plants" every 3 days). When completed, it re-arms for its next occurrence.

> The distinction is derived from the presence of a `recurrenceRule`: no rule → ToDo, has a
> rule → Chore. This keeps a single underlying model while presenting two clear sections in the
> UI.

### 2.2 Data model (SwiftData)

```swift
@Model
final class Task {
    var id: UUID
    var title: String
    var notes: String?

    // Time budgeting — powers the "Pick For Me" feature.
    var estimatedMinutes: Int          // how long the user thinks it takes

    // Scheduling
    var dueDate: Date?                 // optional hard deadline
    var recurrenceRule: RecurrenceRule?  // nil => ToDo, non-nil => Chore

    // Nudge engine state
    var nudgePolicy: NudgePolicy       // how aggressively to re-remind
    var lastNudgedAt: Date?
    var snoozedUntil: Date?

    // Completion state
    var status: TaskStatus             // pending / awaitingVerification / completed / skipped
    var completedAt: Date?
    var verificationMethod: VerificationMethod

    // Focus — supports the "one thing at a time" model (§5).
    var focusStartedAt: Date?          // non-nil => this is the current task; only one at a time

    var createdAt: Date

    init(...) { ... }
}
```

Supporting value types (stored as `Codable` on the model or as enums):

```swift
enum TaskStatus: String, Codable {
    case pending
    case awaitingVerification   // user tapped "done" but hasn't confirmed
    case completed
    case skipped
}

enum VerificationMethod: String, Codable {
    case tapToConfirm       // simple "Yes, I really did it" tap
    case delayedRecheck     // re-ask a few minutes later
    case photo              // (stretch) attach a photo as proof
    case checklist          // (stretch) tick sub-steps
}

struct RecurrenceRule: Codable {
    enum Frequency: String, Codable { case daily, weekly, monthly, everyNDays }
    var frequency: Frequency
    var interval: Int              // e.g. every 2 weeks
    var weekdays: [Int]?           // for weekly rules
    var timeOfDay: DateComponents  // when it should surface each cycle
}

struct NudgePolicy: Codable {
    enum Intensity: String, Codable { case gentle, persistent, relentless }
    var intensity: Intensity
    var repeatInterval: TimeInterval   // gap between re-nudges
    var maxNudgesPerDay: Int
    var quietHours: ClosedRange<Int>?  // e.g. 22...7, no nudges overnight
}
```

> **CloudKit compatibility constraints (important):** Because the store syncs via CloudKit, the
> SwiftData model must follow CloudKit's rules — every non-optional property needs a **default
> value** (or must be optional), `@Attribute(.unique)` constraints are **not allowed**, and all
> relationships must be optional. Uniqueness (e.g. of `id`) is therefore enforced in app logic
> rather than by the schema. These constraints are designed in from the start so we don't have to
> migrate later.

---

## 3. Feature: The Persistent Reminder / Nudge Engine

This is the heart of the app. The goal: **a reminder should not be easy to ignore into oblivion.**

### 3.1 Behaviour

- **Nudging focuses on the single current task** (§5), not the whole backlog — the user is never
  hit by parallel nudge storms for everything they own.
- When the current task is due, schedule a local notification.
- If the user does not act (open, complete, or explicitly snooze), the engine **re-nudges** after
  `nudgePolicy.repeatInterval`, escalating tone/frequency by `intensity`.
- Nudges respect `quietHours` and `maxNudgesPerDay` so the app is insistent, not abusive.
- Snoozing is explicit and time-boxed (`snoozedUntil`) — there is no silent "swipe to dismiss
  forever."
- Other tasks becoming due don't each start nudging; at most they produce **one gentle "ready for
  your next task?" prompt** when nothing is currently in focus — a single invitation, not a list.

### 3.2 Implementation approach

iOS does not allow a truly always-running background process, so persistence is achieved by
**pre-scheduling a ladder of notifications** and reconciling them whenever the app is active:

1. **Notification ladder** — when a task becomes due, schedule several
   `UNNotificationRequest`s at increasing offsets (e.g. now, +15 min, +45 min, +2 h), all in the
   same `threadIdentifier` so they group. This provides persistence even while the app is
   backgrounded.
2. **Notification actions** — attach a `UNNotificationCategory` with actions:
   `Complete`, `Snooze 15 min`, `Snooze until this evening`, `Not now`. Handling them in the
   `UNUserNotificationCenterDelegate` updates task state and reschedules the ladder.
3. **Reconciliation on launch/foreground** — a `NudgeScheduler` service recomputes the correct
   pending notifications for the **current task**, cancelling stale ones and topping up the
   ladder. It does not fan out a ladder per open task; the backlog stays quiet until promoted.
4. **Escalation ladder by `intensity`:**
   - `gentle` → **active** interruption level (default; respects Focus and silent mode).
   - `persistent` → **time-sensitive** interruption level, which breaks through Focus modes and
     scheduled/summary delivery for tasks that matter now.
   - `relentless` → **critical** interruption level (`UNNotificationInterruptionLevel.critical`),
     which the system always presents, lights up the screen, and **bypasses the mute switch and
     Do Not Disturb**, using `UNNotificationSound.defaultCritical` (or a custom critical sound).

### 3.3 Permissions & entitlements

- Request notification authorization on first launch with a clear rationale screen.
- **Critical alerts require a special entitlement issued by Apple**
  (`com.apple.developer.usernotifications.critical-alerts`), obtained via Apple's request form,
  plus a separate `UNAuthorizationOptions.criticalAlert` authorization request to the user. Until
  that entitlement is granted, `relentless` mode gracefully falls back to time-sensitive.
- Because critical alerts override silent mode and DND, they are reserved for tasks the user has
  explicitly marked as high-stakes — over-using them erodes trust and risks App Review rejection.

> **Note for planning:** Re-confirm current `UserNotifications` behaviour (interruption levels,
> critical-alert entitlement flow) against Apple's latest docs during implementation via
> `DocumentationSearch`, since notification policy evolves between iOS releases.

### 3.4 Persistent on-screen presence with Live Activities

A standard notification is trivially dismissible — one swipe and it's gone. A **Live Activity**
(ActivityKit) is the opposite: it stays pinned to the **Lock Screen** and, on supported devices,
lives in the **Dynamic Island**, remaining visible until *the app* ends it. This makes it the
ideal anti-dismissal mechanism for ActuallyDoIt.

**How it prevents easy dismissal:**

- When a task is due (or the user starts working on one), ActuallyDoIt starts a Live Activity for that
  task. It persists across the Lock Screen and Dynamic Island — a glance-proof, always-there
  reminder that a task is outstanding, not a banner that scrolls out of the notification list.
- Even when a user *does* end a Live Activity, by default the system keeps it visible on the Lock
  Screen for a window after it ends — so it lingers rather than vanishing instantly. We tune this
  via the dismissal behaviour and only truly end the activity once the task is **verified**
  complete (see §4).
- The activity is re-established on app launch/foreground reconciliation if it went missing, so
  there is no clean "swipe it away forever" path while a task is still open.

**Interactive completion, in place:**

- Live Activities support **buttons and toggles via the App Intents framework** — so the Lock
  Screen / Dynamic Island presentation can carry **Complete**, **Snooze**, and **Not now**
  actions directly, without unlocking or opening the app.
- Tapping **Complete** from the Live Activity does **not** end it outright — it drives the same
  `awaitingVerification` flow (§4), so the sticky presence remains until the task is genuinely
  confirmed done.
- Using a `LiveActivityIntent` (App Intents) also allows starting/handling activities from the
  background rather than foreground-only.

**Design & technical notes:**

- Live Activities are built with a **Widget Extension** (WidgetKit + SwiftUI); ActivityKit only
  manages the lifecycle (`Activity.request` / `update` / `end`). This adds a new target to the
  project (see architecture, §7).
- Requires `NSSupportsLiveActivities` = `true` in the widget extension's Info.plist.
- Provide all required presentations: Lock Screen banner, Dynamic Island **compact
  leading/trailing**, **minimal**, and **expanded**.
- **Exactly one Live Activity is active at a time** — it represents the user's *current* task,
  reinforcing the one-thing-at-a-time principle. Starting focus on a new task ends the previous
  activity. (There is therefore no need to juggle `relevanceScore` across competing activities.)
- Use `staleDate` so a stalled current task shows as "needs attention" rather than silently going
  quiet.
- Local updates use `Activity.update(_:)`; escalated "alerting" updates can use an
  `AlertConfiguration` to re-surface the activity as a banner.
- **Constraints to respect:** the content-state payload is capped at ~4 KB; keep only display data
  there. visionOS does not support Live Activities. A user can still disable Live Activities in
  Settings, so the notification ladder (§3.2) remains the baseline; Live Activities are the
  *enhanced* persistence layer on top.

> **Note for planning:** ActivityKit evolves quickly (transient activities, channels, broadcast
> push, CarPlay/Apple Watch presentations). Re-check the latest ActivityKit docs via
> `DocumentationSearch` at implementation time.

---

## 4. Feature: Completion Verification

Dismissing a notification must **not** mark a task done. Completion is a deliberate act.

### 4.1 Flow

1. User indicates a task is done (in-app button or notification `Complete` action).
2. Task moves to `awaitingVerification` rather than straight to `completed`.
3. Depending on `verificationMethod`:
   - **tapToConfirm** — a confirmation prompt ("Did you *actually* finish this?") with an honest
     "Not yet" escape hatch that re-arms the nudge.
   - **delayedRecheck** — the app waits N minutes, then asks again; if the user confirms it
     stays done, otherwise it reopens. This catches the "I'll do it in a sec" trap.
   - **photo / checklist** — (stretch) require proof or completed sub-steps before `completed`.
4. Only after successful verification does `status = completed`, `completedAt` is set, and (for
   Chores) the next occurrence is scheduled.

### 4.2 Why this matters for ADHD

The verification step converts a reflexive swipe into a moment of intention, and the "Not yet"
path makes it psychologically safe to admit a task isn't done — which keeps it from silently
disappearing.

---

## 5. Main Screen: The "Now" View (one task at a time)

The home screen is deliberately **not** a task list. It is a calm, single-task focus view built
around the one-thing-at-a-time principle (§1). Its job is to answer one question: *what should I
do right now?*

### 5.1 The current task

- The home screen shows a **single "current" task**, large and centered — title, estimated time,
  and why it surfaced (e.g. "due today").
- Primary actions on the current task: **Done** (→ verification, §4), **Snooze**, **Skip for now**.
- If there is no current task, the screen shows a genuinely empty, encouraging state ("You're all
  caught up") — not a hidden backlog.
- **Choosing the current task:** the user picks one directly, or taps **Pick For Me** (§6) to have
  the app choose one that fits their available time. Only the current task is actively nudged and
  mirrored to the Live Activity (§3.4).

### 5.2 Browsing everything (opt-in)

The full list still exists — it's just not the front door. A deliberate action ("View all",
"Everything") opens a separate **Library** screen with the ToDo / Chore split:

- **ToDos** — one-off tasks with no recurrence. Sorted by due date then estimated time.
- **Chores** — recurring tasks, showing next occurrence and last-completed info.
- Rows show title, estimated-time chip, and due/next indicator. Visual differentiation
  (color/icon) separates the "do it once" pile from the "keeps coming back" pile.
- From here the user can **promote any task to be the current task**, returning to the Now view.
- To avoid overwhelm even here: long lists are chunked/paged and collapsed by default; no
  aggregate "37 tasks!" counters shouted at the user.

### 5.3 Screens

| Screen              | Purpose                                                          |
|---------------------|-----------------------------------------------------------------|
| Now / Home          | The single current task + Done/Snooze/Skip + Pick-For-Me        |
| Library (opt-in)    | ToDo + Chore split; browse and promote a task to "current"      |
| Add / Edit Task     | Title, notes, estimated minutes, recurrence, nudge policy       |
| Task Detail         | Full info, nudge history, complete/verify actions               |
| Pick-For-Me Sheet   | Time-available input → single randomly chosen task              |
| Settings            | Notification prefs, quiet hours, default nudge intensity        |

---

## 6. Feature: "Pick For Me" (Time-boxed Random Task Picker)

Removes decision paralysis by choosing *for* the user.

### 6.1 Flow

1. User taps **Pick For Me** on the main view.
2. A sheet asks **"How much time do you have?"** — quick-pick chips (5, 15, 30, 60 min) plus a
   custom entry.
3. The app filters candidate tasks where `estimatedMinutes <= availableMinutes` and
   `status == pending`.
4. It **randomly selects one** and presents it big and clear: "Do this now: *Task title*".
5. Actions on the result: **Start / I'll do it**, **Pick another**, **Cancel**.
6. Choosing **Start** sets that task as the **current task** (`focusStartedAt`) — it becomes the
   single focus on the Now view, the one being nudged, and the one shown in the Live Activity.
   Selecting a new current task clears the previous one, preserving the one-at-a-time invariant.

### 6.2 Selection logic (design notes)

- Base pool: pending tasks fitting the time budget.
- Optional weighting to make it feel smart rather than purely random:
  - Slight bias toward tasks nearing their `dueDate`.
  - Slight bias toward tasks nudged many times but still not done.
  - Avoid immediately re-picking the last suggestion.
- If no task fits the time budget, show an encouraging empty state suggesting a smaller task or a
  break.

---

## 7. Architecture

```
ActuallyDoIt/
├─ Models/
│  ├─ Task.swift               (@Model, CloudKit-compatible)
│  ├─ RecurrenceRule.swift
│  ├─ NudgePolicy.swift
│  ├─ TaskActivityAttributes.swift  (ActivityAttributes — shared with widget target)
│  └─ Enums.swift              (TaskStatus, VerificationMethod, ...)
├─ Services/
│  ├─ NudgeScheduler.swift     (@Observable) — builds/reconciles notification ladders
│  ├─ NotificationManager.swift — UNUserNotificationCenter wrapper + delegate
│  ├─ LiveActivityManager.swift — starts/updates/ends Live Activities via ActivityKit
│  ├─ CompletionVerifier.swift — drives the verification state machine
│  └─ TaskPicker.swift         — Pick-For-Me selection logic
├─ Intents/
│  ├─ CompleteTaskIntent.swift  (AppIntent — Live Activity / notification action)
│  └─ SnoozeTaskIntent.swift
├─ Views/
│  ├─ HomeView.swift           (ToDo/Chore split + Pick-For-Me button)
│  ├─ TaskRowView.swift
│  ├─ AddEditTaskView.swift
│  ├─ TaskDetailView.swift
│  ├─ PickForMeSheet.swift
│  └─ SettingsView.swift
└─ App/
   └─ ActuallyDoItApp.swift         (ModelContainer + CloudKit config, notification delegate)

ActuallyDoItWidget/                 (Widget Extension target — required for Live Activities)
├─ TaskLiveActivity.swift      (ActivityConfiguration: Lock Screen + Dynamic Island views)
└─ Info.plist                  (NSSupportsLiveActivities = true)
```

- **Services are `@Observable`** and injected via the SwiftUI environment; views stay thin.
- **All async work uses `async`/`await`** (notification scheduling, verification timers). No
  Combine.
- **SwiftData `@Query`** drives the lists directly in views; services mutate the `ModelContext`.
- **`ActivityAttributes` are shared** between the app and widget targets, so keep them in a file
  that is a member of both targets.

### 7.4 Cross-device sync (CloudKit)

- The `ModelContainer` is configured for iCloud sync (a `ModelConfiguration` with a
  `cloudKitDatabase` / automatic option), so SwiftData mirrors the store to the user's **private
  CloudKit database** and syncs across their devices with no manual networking code.
- **Project setup:** enable the **iCloud → CloudKit** capability and a background-modes entitlement
  for remote-change delivery; requires a paid Apple Developer account and a CloudKit container.
- **Model rules** (see §2.2): defaults on all non-optional properties, optional relationships, no
  unique constraints. Uniqueness/identity handled in app logic.
- **Sync realities to design for:** changes are eventually-consistent (not instant), so the UI
  reacts to store updates rather than assuming immediate propagation; scheduling/Live-Activity
  logic keys off the local store and reconciles on change so a task completed on one device stops
  nudging on the others.

---

## 8. Notifications: Handling & Edge Cases

| Case                              | Handling                                                    |
|-----------------------------------|-------------------------------------------------------------|
| App killed / backgrounded         | Pre-scheduled ladder keeps firing; reconcile on next launch |
| User denies notification perms    | Degrade to in-app nudges + badge; prompt to re-enable       |
| Quiet hours                       | Skip scheduling within `quietHours`, resume after           |
| `maxNudgesPerDay` reached         | Stop for the day, resume next cycle                         |
| Chore completed early             | Mark done, schedule next occurrence from rule               |
| Device notification limit (64)    | Cap ladder depth; prioritise soonest/most-important tasks   |
| Critical-alert entitlement absent | `relentless` falls back to time-sensitive until granted     |
| User disables Live Activities     | Fall back to notification ladder; keep in-app state         |
| Task completed on another device  | CloudKit sync → reconcile: cancel nudges, end Live Activity |
| Live Activity ended by user       | Re-establish on next reconcile while task is still open      |

---

## 9. Implementation Phases

### Phase 1 — Foundation
- Replace `Item` with the `Task` model + supporting types (CloudKit-compatible from the start:
  defaults, optional relationships, no unique constraints).
- Enable the **iCloud/CloudKit capability** and configure the `ModelContainer` for sync.
- Build the **Now view** (single current task) as the home screen, plus the opt-in **Library**
  (ToDo/Chore split) and Add/Edit task flow (no notifications yet).
- Current-task selection (`focusStartedAt`) with the one-at-a-time invariant.
- Basic complete → `completed` (no verification yet).

### Phase 2 — Nudge Engine
- `NotificationManager` (permissions, categories, actions).
- `NudgeScheduler` (ladder scheduling + reconciliation).
- Snooze / escalation via `NudgePolicy` (active → time-sensitive; wire critical as fallback-ready).

### Phase 3 — Completion Verification
- `awaitingVerification` state + `CompletionVerifier`.
- tapToConfirm and delayedRecheck methods.

### Phase 4 — Live Activities (anti-dismissal)
- Add the **Widget Extension** target and `TaskActivityAttributes` (shared).
- `LiveActivityManager` to start/update/end activities; Lock Screen + Dynamic Island presentations.
- App Intent–backed **Complete / Snooze** buttons feeding the verification flow.

### Phase 5 — Critical alerts
- Request the critical-alert entitlement from Apple; add `criticalAlert` authorization.
- Wire `relentless` intensity to `.critical` interruption level with graceful fallback.

### Phase 6 — Pick For Me
- `PickForMeSheet` + `TaskPicker` selection logic with time filtering and weighting.

### Phase 7 — Chores & Recurrence
- `RecurrenceRule` evaluation, next-occurrence scheduling, chore history.

### Phase 8 — Polish
- Settings, quiet hours, empty states, accessibility, CloudKit sync-state UI,
  photo/checklist verification (stretch).

---

## 10. Testing Strategy

- **Unit tests (Swift Testing framework):**
  - `TaskPicker` selection: time filtering, weighting, no-repeat, empty pool.
  - `RecurrenceRule` next-occurrence math.
  - `NudgeScheduler` ladder generation respecting quiet hours & daily caps.
  - Completion state machine transitions (pending → awaitingVerification → completed / reopen).
- **UI tests (XCUIAutomation):**
  - Add a ToDo and a Chore; verify they appear in the correct sections.
  - Pick-For-Me flow returns a task within the time budget.
  - Completion requires verification before a task leaves the pending list.

---

### Resolved decisions

- **One thing at a time is the guiding principle** — the app focuses the user on a single current
  task; the full list is opt-in, and nudges/Live Activity concern only the current task. This
  overrides other features when they conflict (see §1, §5).
- **CloudKit sync is in scope** — the app syncs tasks across the user's devices via SwiftData +
  CloudKit from v1. Model is designed to CloudKit's constraints up front.
- **Critical alerts are in scope** — `relentless` intensity uses the `.critical` interruption
  level (pending Apple's entitlement), with a time-sensitive fallback.
- **Live Activities are in scope** — used as the primary anti-dismissal mechanism (persistent Lock
  Screen / Dynamic Island presence with in-place Complete/Snooze actions). **Exactly one runs at a
  time**, mirroring the current task — resolving the earlier "which tasks get a Live Activity?"
  question.

### Still open

1. **Verification default** — should `tapToConfirm` or `delayedRecheck` be the default method?
2. **Estimated time entry** — free-form minutes vs. fixed buckets (5/15/30/60) for simplicity?
3. **Gamification** — streaks/rewards for completion are a natural ADHD-friendly addition; in or
   out of scope? (Must respect the reduce-overwhelm principle if added.)
4. **CloudKit account edge cases** — behaviour when the user isn't signed into iCloud or storage
   is full: local-only fallback with a prompt?
5. **Skip vs. defer semantics** — when the user "Skips" the current task on the Now view, does it
   go back into the pool immediately, or lie low until later so the same thing isn't re-suggested?

---

*This document is a living plan and should be updated as decisions in §11 are resolved.*
