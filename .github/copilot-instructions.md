# Micmute – AI coding agent playbook

## Overview
- Micmute is a macOS menu-bar SwiftUI app that orchestrates global mute toggles and per-app audio gain through CoreAudio.
- Entry flows: `MicmuteApp` bootstraps `AppDelegate`, which constructs the status bar item, hosts `MainMenuView`, and drives `ContentViewModel` (the single source of truth for microphone state).

## Architectural map
- `Models/ContentViewModel.swift` owns device discovery, mute/unmute commands, notification windows, and ties keyboard shortcuts through `GlobalShortcutManager`.
- `Views/MenuView.swift` renders the menu UI; it binds to `ContentViewModel` and hands per-app controls to `Views/PerAppAudio/` components while persisting collapsed/expanded state via `@AppStorage`.
- `Utilities/SettingsUpdaterModel.swift` is the long-lived updater service; dependent views consume it via `EnvironmentObject` (`PreferencesView`, `UpdatesView`).
- `Audio/` namespace:
  - `Driver/` holds the Objective-C++ AudioServerPlugIn (`VolumeControlDriverPlugin.mm`) plus shared-memory helpers.
  - `Bridge/VirtualDriverBridge.swift` exposes the C bridge (`VirtualAudioDriver*` functions from `VirtualAudioDriverBridge.h/.cpp`) as an async Swift singleton.
  - `Manager/PerAppAudioVolumeManager.swift` manages installer state, refreshes `AudioApplication` lists, and proxies mute/volume to the driver.
  - `Monitoring/ApplicationAudioMonitor.swift` polls the driver on a background queue; in Debug it emits `AudioApplication.mockItems` so UI work is possible without the driver installed.

## Patterns & conventions
- Most observable classes are `@MainActor`; keep UI mutations, `@Published` assignments, and NotificationCenter posts on the main thread.
- Persist new user defaults via the `AppStorageEntry` enum in `Utilities/Constants.swift` instead of hard-coded keys.
- Per-app gain is clamped to `0.0...1.25` before touching the driver (`PerAppAudioVolumeManager.setVolume`); keep that clamp in any new UI.
- Driver install/uninstall must flow through `DriverInstaller` (`Audio/Installer/DriverInstaller.swift`), which builds a temporary privileged script and runs it with `osascript`; avoid heredocs so the fish-compatible script generation stays intact.
- Extending driver capabilities: add the C symbol to `VirtualAudioDriverBridge.h/.cpp`, surface it inside `VirtualDriverBridge`, then thread it through `PerAppAudioVolumeManager` or relevant view models; remember to include new headers in `Micmute-Bridging-Header.h`.
- `ApplicationVolumeListViewModel` caches per-bundle rows and filters out muted/silent apps based on the `peakLevel` threshold—mirror that logic when adding new filters.

## UI & interaction notes
- `PreferencesView` tabs (`General`, `PerAppAudio`, `Notification`, `Updates`, `About`) live under `Views/`; they expect `SettingsUpdaterModel`, `PerAppAudioVolumeManager`, `ShortcutPreferences`, and `ContentViewModel` in the environment.
- Status bar behaviour respects `menuBehaviorOnClick`: menu vs direct mute; always post `NSNotification.Name("MuteStateChanged")` after toggling so icons and notification windows stay synchronized.
- `NotificationWindowController` auto-hides unless `NotificationPinBehavior` keeps it pinned; reuse `ContentViewModel.refreshPinnedNotification()` when preferences change to maintain state.

## Developer workflows
- Build with Xcode: open `Micmute.xcodeproj`, select the `Micmute` scheme, target macOS 13+; ensure `VolumeControlDriver.driver` stays bundled so installation works.
- Debug per-app volume without installing the driver by running a Debug build—the monitor will return mock apps.
- GitHub update checks hit `https://api.github.com/repos/rokartur/Micmute/releases`; set a `GITHUB_TOKEN` environment variable in the run scheme to avoid rate limits.
- Logs use `os.Logger` categories (`PerAppAudioVolumeManager`, `DriverInstaller`, `com.rokartur.Micmute.Driver`); driver logs appear under the `Micmute Volume Control Driver` subsystem in Console.

## Gotchas & housekeeping
- `LaunchAtLoginManager.update(_:)` toggles registration opposite the provided flag—guard downstream expectations before “fixing” it.
- `ApplicationAudioMonitor` emits on a background queue; hop back to the main actor (`Task { @MainActor ... }`) before mutating UI state, as `PerAppAudioVolumeManager` already demonstrates.
- CoreAudio device IDs persist as `Int` via `@AppStorage`; use the computed wrappers on `ContentViewModel` (`selectedDeviceID`, etc.) so migrations centralize there.
- Driver state maintains shared memory under `/Library/Application Support/Micmute`; coordinate any extra artifacts with `DriverInstaller.uninstallDriver()` to keep cleanup complete.
