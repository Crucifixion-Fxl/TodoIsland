# Todo Island Product Specification

## Product

Todo Island is a personal macOS accessory application that presents and manages unfinished iCloud Reminders in a Dynamic Island-style surface attached to the top center of one automatically determined Host Display.

- Product name: `Todo Island`
- Bundle identifier: `com.fxl.TodoIsland`
- Minimum system: macOS 14
- Initial delivery: personal, local build signed with `Sign to Run Locally`
- Languages: English and Simplified Chinese, selected from the system locale

The canonical product vocabulary lives in [`CONTEXT.md`](../CONTEXT.md). Architectural decisions live in [`docs/adr`](./adr).

## Product Boundaries

Todo Island reads and writes Reminders through Apple's public EventKit APIs. It requests full Reminders access because Apple does not expose a read-only authorization level. Reminder data remains on the Mac and is never uploaded, analyzed, or written to content logs.

The first version:

- uses only iCloud Reminder Lists;
- presents only Pending Reminders;
- switches between existing Reminder Lists inside the Island;
- creates, edits, completes, and deletes Reminders;
- edits title, optional Due Date and optional time, and Priority;
- can present and complete existing Recurring Reminders but cannot edit their repetition rules; and
- cannot move a Reminder between lists or create, rename, reorder, or delete Reminder Lists.

The first version does not include search, filters, notes, URLs, attachments, locations, tags, subtasks, recurrence editing, notifications, or due-date alerts.

## Reminder Ordering

EventKit does not expose the manual ordering used by Apple Reminders. Todo Island therefore does not support drag reordering and computes a stable action order:

1. overdue;
2. due today;
3. due in the future; and
4. no Due Date.

Within those groups, Reminders are ordered by due time, Priority, and title. The first item is the Next Reminder.

## Island States

### Collapsed Island

On a display with a physical notch, the Active List name appears on the left side and an 18-point green outline circle containing its Pending Reminder count in blue appears on the right. The text and count circle use matching outer insets so the Collapsed Island is visually symmetrical. On a display without a notch, the same information appears in a centered black capsule.

### Island Preview

Hovering briefly over the Collapsed Island expands an Island Preview without taking focus from the current application. The Preview shows the Active List's Pending Reminders and supports pointer-based actions such as switching lists and completing a Reminder. Quick Add uses the same bottom input as the Pinned Island; clicking it pins the Island and focuses the field. The Preview closes 500 milliseconds after the pointer leaves.

### Pinned Island

Clicking the Island opens or converts it to a Pinned Island. The Pinned Island can become key, accepts keyboard input, and remains open while the user works.

- `Escape` cancels an active edit or closes the Island.
- Clicking outside closes the Island.
- Enter or leaving an edit field saves its value.
- Escape while editing discards unsaved field changes.

The nominal expanded size is 480 by 360 points, with adaptation for smaller displays. Content scrolls instead of growing the Island without limit.

## Expanded Layout

The expanded Island contains:

1. a header showing the Active List, which opens a menu of existing iCloud Reminder Lists;
2. a scrollable list of Pending Reminders;
3. rows containing completion control, title, due state, and Priority;
4. a compact in-Island editor for the selected Reminder; and
5. Quick Add at the bottom.

The last Active List is restored on launch. If it no longer exists, the app falls back to the first available iCloud Reminder List.

Quick Add creates a Pending Reminder in the Active List from a title followed by Enter. It initially has no Due Date or Priority. The user can then open its compact editor.

Completing a Reminder immediately changes its leading circle to a green checkmark, then removes it from the visible Pending Reminders after 200 milliseconds. Completion has no Undo action. Deleting a Reminder requires confirmation.

## Keyboard Operations

- `Up Arrow` and `Down Arrow`: change the selected Reminder
- `Return`: edit the selected Reminder
- `Space`: complete the selected Reminder
- `Command-N`: focus Quick Add
- `Delete`: request deletion of the selected Reminder
- `Escape`: cancel editing or close the Pinned Island

Every operation also has a mouse-accessible equivalent.

## Appearance

The Island uses a black surface, white primary text, and gray secondary text. The Active List's Reminders color is the interaction accent. Overdue dates use red.

The application icon is an original black notch silhouette with a colored checkmark. The implementation must not copy boring.notch artwork or source code.

Todo Island supports VoiceOver, keyboard navigation, increased contrast where applicable, and Reduce Motion. Reduce Motion replaces geometry-heavy spring transitions with restrained fades or immediate state changes.

## Displays and Full Screen

Only the automatically determined Host Display hosts an Island. The application does not ask the user to select a display. A Host Display with a physical notch uses the notch-attached layout; one without a notch uses the top-center capsule fallback.

Whenever Host Display detection runs, the display containing the mouse pointer is selected. Whether that display has a physical notch affects the Island geometry and full-screen behavior, not its eligibility to become the Host Display.

While the Island is collapsed, the pointer must remain on a different display for approximately 350 milliseconds before that display becomes the Host Display. Brief boundary crossings do not move the Island. An Island Preview or Pinned Island locks its Host Display until it collapses, at which point detection resumes.

If the Host Display is disconnected, the Island immediately moves to the pointer's remaining display. This forced migration preserves the current presentation state, editing draft, and keyboard focus.

A normal collapsed Host Display change uses a brief fade out on the old display and fade in on the new display. With Reduce Motion enabled, the Island changes displays immediately.

- On a physical-notch display, the Island remains available in full-screen spaces.
- On a display without a notch, the collapsed fallback capsule hides while an application is full screen. That display remains the Host Display, and the capsule returns when full screen ends.
- A first-launch authorization Island or a Pinned Island explicitly opened by the user can appear above a full-screen application. When it collapses, the normal hiding rule resumes.
- Screen attachment, removal, resolution changes, and Host Display changes recalculate the Island geometry.

## Application Surfaces

Todo Island is an accessory application with no Dock icon. Its menu-bar icon opens a menu containing:

- Open Island;
- Settings;
- Launch at Login;
- About; and
- Quit.

Settings contains:

- Reminders authorization status and an Open System Settings action;
- Launch at Login;
- full-screen hiding behavior;
- About; and
- Quit.

Launch at Login is disabled by default.

## In-Island Authorization

On first launch, Todo Island opens a Pinned Island that explains why full Reminders access is required, states that Reminder content stays on the device, and offers an Allow Access action. The application does not use a separate onboarding window. The macOS authorization prompt remains a system-owned surface triggered by that action.

If access is granted, the same Pinned Island immediately replaces its authorization content with the Active List and its Reminders. If access is denied or restricted, it remains pinned in a locked state and replaces the action with Open System Settings. Settings retains the authorization status and the same recovery action. The application does not repeatedly prompt.

The user may dismiss the first-launch authorization Island with Escape or by clicking outside it. The Island then remains available in its collapsed locked state and can be reopened to continue authorization. Dismissing it does not quit the application.

After authorization, the app restores the last valid Active List. If it is unavailable or none has been saved, the app automatically uses the first available iCloud Reminder List. The user can switch the Active List from within the Island.

If no iCloud Reminder List is available, the Pinned Island shows an empty state with Open Reminders and Check Again actions. Todo Island does not create a Reminder List on the user's behalf.

If access is revoked while Todo Island is running, the Island preserves its current presentation state and replaces its Reminder content with the locked state. It does not expand itself or take focus solely because authorization changed.

If authorization is revoked during an edit, the unsaved draft remains in memory but cannot be saved. If access returns, Todo Island refetches the Reminder, validates that the draft still has a valid target, and lets the user explicitly save it. Authorization restoration never writes a draft automatically.

The app uses:

- `requestFullAccessToReminders()` on macOS 14 or newer;
- `NSRemindersFullAccessUsageDescription`; and
- the sandbox calendar personal-information entitlement.

## Data Refresh and Identity

A long-lived EventKit store provides Reminder Lists and Reminders. The app builds immutable presentation snapshots rather than retaining fetched EventKit objects as UI state.

When EventKit reports a store change, the app coalesces notifications and refetches the available lists and Pending Reminders for the Active List. It also refetches after authorization changes and when the application becomes active.

EventKit identifiers are treated as recoverable references rather than permanent identities. Missing identifiers result in refetch and fallback behavior, not corrupted local state.

## Architecture

- Swift 6
- AppKit window, menu-bar, activation, display, and focus coordination
- SwiftUI Island, authorization, editor, and settings views
- EventKit repository behind an application-owned protocol
- ServiceManagement launch-at-login integration
- Swift Testing or XCTest for deterministic logic
- no third-party runtime dependencies
- no private Reminders database or private framework integration

The Island shell is an independent implementation informed by boring.notch's public architectural approach: a transparent borderless panel at the top center, explicit display geometry, a custom black shape, and animated collapsed and expanded states. GPLv3 source from boring.notch is not copied.

## First-Version Definition of Done

- The Xcode project opens and builds without errors.
- A locally signed `.app` launches on the current Mac.
- Unit tests cover Reminder ordering, presentation mapping, Island state transitions, and display geometry.
- The application has no Dock icon and its menu-bar entry remains usable when the Island cannot be shown.
- In-Island authorization correctly handles not-determined, full-access, denied, and restricted states.
- The app reads and performs the agreed CRUD operations against real iCloud Reminders.
- Active List switching, Quick Add, compact editing, 200-millisecond completion feedback, and confirmed deletion work.
- External Reminders changes appear after EventKit change notifications.
- Collapsed, Preview, and Pinned states follow the agreed focus behavior and shortcuts.
- Physical-notch and no-notch layouts are manually checked on available displays.
- Full-screen and display-configuration behavior is manually checked.
- English and Simplified Chinese layouts are checked for truncation.
- VoiceOver labels and Reduce Motion behavior are checked.
- All automated tests pass.

## Planned Implementation Sequence

1. Create the native Xcode project, targets, entitlements, local signing, and test harness.
2. Implement domain snapshots, automatic ordering, EventKit mapping, and unit tests.
3. Implement authorization, iCloud list filtering, CRUD, refresh, and failure states.
4. Implement the AppKit Island window, display geometry, state and focus coordination.
5. Implement the SwiftUI collapsed, Preview, Pinned, list, editor, and Quick Add surfaces.
6. Implement menu-bar, in-Island authorization, settings, launch at login, localization, accessibility, and artwork.
7. Build, run automated tests, and perform real EventKit and display acceptance checks.
