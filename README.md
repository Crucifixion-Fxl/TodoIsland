# Todo Island

Todo Island is a native macOS 14+ menu-bar application that presents and manages pending iCloud Reminders in a Dynamic Island-style surface attached to the selected display's notch.

## Open and run

1. Open `TodoIsland.xcodeproj` in Xcode 26 or newer.
2. Select the `TodoIsland` scheme and **My Mac** destination.
3. Run the application.
4. Read the in-app privacy explanation, then grant Reminders access when ready.

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

Reminder content stays in EventKit and application memory on this Mac. Todo Island has no backend, analytics SDK, or content logging.

The Island implementation is original code informed by the public architectural approach of boring.notch. No GPLv3 source or artwork from boring.notch is copied into this project.
