# Todo Island

Todo Island is a native macOS 14+ menu-bar application that presents and manages pending reminders from iCloud or Todo Island's private local storage in a Dynamic Island-style surface on the display where the pointer is currently working.

## Open and run

1. Open `TodoIsland.xcodeproj` in Xcode 26 or newer.
2. Select the `TodoIsland` scheme and **My Mac** destination.
3. Run the application.
4. In the Pinned Island, choose whether the Collapsed Island stays visible or hides automatically.
5. Grant Reminders access for iCloud or choose **Use Local** to work without that permission.

The checked-in project uses `Sign to Run Locally`, the bundle identifier `com.fxl.TodoIsland`, the App Sandbox, and the Reminders calendar entitlement. Configure a Personal Team or Developer ID only when distributing to another Mac.

## Build from Terminal

```sh
xcodebuild \
  -project TodoIsland.xcodeproj \
  -scheme TodoIsland \
  -configuration Debug \
  -derivedDataPath /tmp/TodoIslandDerivedData \
  build
```

## Test

```sh
xcodebuild \
  -project TodoIsland.xcodeproj \
  -scheme TodoIsland \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/TodoIslandDerivedData \
  test
```

## Documentation

- [`CONTEXT.md`](CONTEXT.md) defines the product language.
- [`docs/PRODUCT-SPEC.md`](docs/PRODUCT-SPEC.md) contains the accepted product specification.
- [`docs/adr`](docs/adr) records architectural decisions.

## Privacy and source boundary

iCloud Reminder content is accessed through EventKit. Todo Island Local lists and reminders are stored in a sandboxed, versioned SwiftData store in Application Support with CloudKit synchronization disabled. Todo Island has no backend, analytics SDK, or content logging.

The Island implementation is original code informed by the public architectural approach of boring.notch. No GPLv3 source or artwork from boring.notch is copied into this project.
