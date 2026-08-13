# Keep Reminder data on device

Todo Island will process iCloud Reminder data through the local EventKit store and Local Reminder data through its sandboxed on-device SwiftData store. It will have no application backend, analytics SDK, or content logging, preventing Reminder titles and details from being uploaded by Todo Island and keeping the permission explanation truthful. Apple Reminders remains responsible for iCloud synchronization of the iCloud Source.
