# Own local Reminder storage

Todo Island will support an app-owned Local Source alongside its EventKit-backed iCloud Source instead of using Apple Reminders' “On My Mac” source. This keeps Local Reminder Lists private to Todo Island and available without iCloud, while accepting the cost of owning a second persistence backend, migrations, and explicit behavior across sources.
