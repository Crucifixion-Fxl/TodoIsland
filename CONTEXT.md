# Todo Island

Todo Island is a macOS accessory application for viewing and managing unfinished reminders from iCloud in a notch-attached surface.

## Language

**Reminder**:
An item belonging to a Reminder List, with a title and optional Due Date and Priority, that can be created, edited, completed, or deleted.
_Avoid_: Todo, task

**Pending Reminder**:
A Reminder that has not been completed. Todo Island presents only Pending Reminders in its normal list views.
_Avoid_: Open todo, incomplete task

**Reminder List**:
A user-defined collection of Reminders in iCloud Reminders.
_Avoid_: Calendar, category

**Active List**:
The Reminder List currently presented in the Island. A user can switch the Active List from within the Island.
_Avoid_: Selected calendar, current category

**Island**:
The top-center surface that is visually attached to a physical display notch, or shown as a top-center capsule on a display without one.
_Avoid_: Popup, widget, panel

**Host Display**:
The single display that currently hosts the Island. Todo Island determines it from the display containing the pointer rather than asking the user to select one.
_Avoid_: Selected Display, main monitor, primary screen

**Island Preview**:
The expanded Island shown while the pointer hovers over its collapsed surface. It supports pointer-based Reminder actions without taking keyboard focus and closes 500 milliseconds after the pointer leaves. Quick Add remains visible; clicking it converts the Preview to a Pinned Island for text input.
_Avoid_: Hover mode, passive popup

**Pinned Island**:
The expanded, interactive Island entered by clicking it. It takes keyboard focus and remains open while the user creates or manages Reminders.
_Avoid_: Focused popup

**Locked Island**:
An Island that cannot present or modify Reminders because Reminders access is unavailable. It explains the required access and offers the appropriate authorization or recovery action.
_Avoid_: Onboarding, permission page

**Quick Add**:
The compact input in a Pinned Island that creates a Pending Reminder from a title alone in the Active List. A Quick Add Reminder initially has no Due Date or Priority.
_Avoid_: New-task box, composer

**Due Date**:
The optional calendar date on which a Reminder becomes due. It may additionally specify a particular time.
_Avoid_: Deadline, timestamp

**Priority**:
The optional urgency assigned to a Reminder in iCloud Reminders.
_Avoid_: Importance, rank

**Next Reminder**:
The first Pending Reminder in the Active List after overdue, today, future, and undated Reminders are ordered by time, Priority, and title.
_Avoid_: First task, current todo

**Recurring Reminder**:
A Reminder whose repetition rule is managed in iCloud Reminders. Todo Island can present and complete it but does not change its repetition rule.
_Avoid_: Repeating task, recurrence item

**All Done**:
The state of an Active List that contains no Pending Reminders. The Island remains available for Quick Add while showing this state.
_Avoid_: Empty list, zero state
