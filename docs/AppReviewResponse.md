# ActuallyDoIt — App Review Information

This document answers each item requested by App Review. The relevant parts should be
copied into the **Notes** field of the **App Review Information** section in App Store Connect
(and kept there for future submissions).

> The requested screen recording (item 1) will be attached separately in the App Store Connect reply.

---

## 1. Screen recording

A screen recording captured on a physical device running the latest OS will be attached to the
App Store Connect reply. It begins with launching the app and walks through the core flow:

1. Launch → first-run tour (skippable), then the **Now** screen showing a single current task.
2. Adding a task, setting its schedule/recurrence, tags, and nudge intensity.
3. **Pick for me** choosing the next task; marking a task **Done** and using **Can't do this now**.
4. **All tasks** (Library): one-off and recurring tasks, filtering by tag.
5. Notifications permission prompt and a nudge reminder.
6. Home Screen widget and Lock Screen Live Activity, including completing a task from the widget.
7. **Settings → Support the developer** (the in-app purchase / tip flow).

**There are no account, login, or account-deletion flows** (see item 4). The only prompt for a
device capability is the **notifications** permission request, which is shown in the recording.
The only purchase flow is the optional tip jar, also shown.

---

## 2. Devices and operating systems tested

<!-- TODO: Replace with the actual physical devices/OS versions you tested on before submitting. -->

The app was tested on physical devices prior to submission:

| Device | OS version |
| --- | --- |
| iPhone (model) | iOS (version) |
| iPad (model) | iPadOS (version) |
| Mac (model) | macOS (version) |

The app is a universal build supporting iPhone, iPad, and Mac.

---

## 3. App description and target audience

**ActuallyDoIt** is a personal to-do / task manager built around doing **one thing at a time**.

- **Problem it solves:** Conventional task apps show a long backlog that's easy to feel paralysed
  by, and easy to swipe reminders away and forget. ActuallyDoIt keeps resurfacing the single most
  relevant task and nudges the user until it's actually done.
- **How it works / value:**
  - The **Now** screen shows one task front and centre, with **Done** and **Can't do this now**.
  - **Pick for me** chooses a sensible next task when the user can't decide.
  - **All tasks** holds the full backlog: one-off to-dos and recurring chores (daily/weekly/monthly),
    organised with tags (e.g. Home, Work) that can filter the Now screen.
  - **Nudges** are local reminders with per-task intensity (Gentle, Persistent, Relentless) and
    user-set times; chores can be paused while away.
  - **Home Screen widgets** and a **Lock Screen Live Activity** keep the current task in view and
    allow completing it without opening the app.
- **Target audience:** General productivity users — anyone who wants a low-friction way to focus on
  and follow through on tasks, including people who find long task lists overwhelming. No age-gated
  or specialised audience.

---

## 4. Setup instructions and access

**No login is required and no demo account is needed.** The app has no user accounts, sign-up,
or sign-in. All features are available immediately on launch, with no paywall, unlock, or gated
content.

Getting to the main features:

1. **Launch the app.** A short first-run tour appears and can be skipped. The **Now** screen loads.
2. **Add a task:** tap the add (＋) control, enter a title, and optionally set a schedule,
   recurrence, tags, and a nudge intensity.
3. **Work through tasks:** on **Now**, tap **Done** to complete, or **Can't do this now** to defer.
   Use **Pick for me** to have the app choose the next task.
4. **Browse everything:** open **All tasks** to see the full backlog and filter by tag.
5. **Reminders:** allow notifications when prompted to receive nudges at the scheduled times.
6. **Widgets / Live Activity:** add the Home Screen widget or Lock Screen Live Activity from the
   system UI to see and complete the current task.
7. **Optional tip:** **Settings → Support the developer** offers optional one-off tips (see item 5).

- **Data & sync:** Tasks are stored locally on device (SwiftData). If the user is signed into
  iCloud, data syncs automatically across their own devices via the app's private CloudKit
  database. iCloud is optional — the app is fully functional offline and while signed out of iCloud.
- **No sample files or credentials** are required to review the app.

---

## 5. External services, tools, and platforms

The app relies **only on Apple platform services**. There are no third-party SDKs, backends,
analytics, advertising, or AI services.

| Purpose | Service |
| --- | --- |
| In-app purchases (optional tips) | **Apple StoreKit 2** |
| Cross-device sync of the user's own data | **Apple CloudKit** (private database, via SwiftData) |
| Local reminders | **Apple UserNotifications** (local notifications only — no push server) |
| Widgets & Live Activities | **Apple WidgetKit / ActivityKit** |

There is **no custom server**, no third-party authentication, no third-party payment processor,
and no network calls to any non-Apple service.

---

## 6. Regional differences

The app **functions consistently across all regions**. There is no region-locked content and no
regional feature differences. All UI is in English. The only region-dependent element is the
localised **price** of the optional in-app tips, which is set automatically by the App Store per
storefront.

---

## 7. Regulated industry / protected third-party material

**Not applicable.** ActuallyDoIt does not operate in a regulated industry (no health, financial,
gambling, etc. functionality) and contains no protected third-party material. All content and
assets in the app are original and created by the developer.

---

## Notes on the "Prevent Common Issues" guidance

These were general tips in the reply, not confirmed rejections, but for the record:

- **2.1 Bugs / accessing the app:** No account or credentials are needed — the app opens straight
  to full functionality.
- **3.1.2 Subscriptions:** The app has **no subscriptions**. The only in-app purchases are three
  **consumable** "tip" products (Small $1.99, Medium $4.99, Large $9.99) that support the developer
  and unlock nothing. Because they are one-off consumables, not auto-renewable subscriptions, the
  subscription-disclosure requirements (title/length/price, Terms of Use link) do not apply.
- **2.3.3 Screenshots:** App Store screenshots show the actual app in use (the Now screen, task
  list, nudges, and widgets), not title art or a splash/login screen.
- **5.1.1 Purpose strings:** The app requests **notification** permission only, used to deliver the
  user's own task reminders ("nudges") at times they choose. It does not request location, contacts,
  camera, microphone, photos, or App Tracking Transparency, and performs no tracking.
