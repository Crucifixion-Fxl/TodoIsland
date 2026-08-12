# Use public EventKit for iCloud Reminders

Todo Island will access iCloud Reminders through Apple's public EventKit APIs and accept the system's full Reminders permission even though the app presents only pending reminders. This keeps the integration compatible with normal macOS privacy and distribution mechanisms; private Reminders databases and private frameworks are out of scope.
