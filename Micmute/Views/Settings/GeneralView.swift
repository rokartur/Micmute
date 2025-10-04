import SwiftUI

struct GeneralView: View {
    @EnvironmentObject private var contentViewModel: ContentViewModel
    @EnvironmentObject private var shortcutPreferences: ShortcutPreferences
    @AppStorage(AppStorageEntry.pushToTalk.rawValue) var pushToTalk: Bool = false
    @AppStorage(AppStorageEntry.menuBehaviorOnClick.rawValue) var menuBehaviorOnClick: MenuBarBehavior = .menu
    @AppStorage(AppStorageEntry.launchAtLogin.rawValue) var launchAtLogin: Bool = false
    @AppStorage(AppStorageEntry.syncSoundEffectsWithOutput.rawValue) var syncSoundEffectsWithOutput: Bool = true

    var body: some View {
        VStack(spacing: 16) {
            CustomSectionView(title: "Keyboard shortcuts") {
                VStack(spacing: 12) {
                    HStack {
                        Text("Toggle mute")
                        Spacer()
                        ShortcutRecorderView(
                            shortcut: Binding(
                                get: { shortcutPreferences.toggleMuteShortcut },
                                set: { shortcutPreferences.toggleMuteShortcut = $0 }
                            ),
                            placeholder: "None"
                        )
                        .frame(width: 110, alignment: .trailing)
                    }

                    Divider()

                    HStack {
                        Text("Check mute status")
                        Spacer()
                        ShortcutRecorderView(
                            shortcut: Binding(
                                get: { shortcutPreferences.checkMuteShortcut },
                                set: { shortcutPreferences.checkMuteShortcut = $0 }
                            ),
                            placeholder: "None"
                        )
                        .frame(width: 110, alignment: .trailing)
                    }

                    Divider()

                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Push to talk")
                            Text("Hold the shortcut to temporarily unmute")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        ShortcutRecorderView(
                            shortcut: Binding(
                                get: { shortcutPreferences.pushToTalkShortcut },
                                set: { shortcutPreferences.pushToTalkShortcut = $0 }
                            ),
                            isEnabled: pushToTalk,
                            placeholder: "None"
                        )
                        .frame(width: 110, alignment: .trailing)
                        .opacity(pushToTalk ? 1 : 0.5)
                    }
                }
                .toggleStyle(.switch)
            }
            
            CustomSectionView(title: "Behavior") {
                VStack(spacing: 12) {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Push to talk mode")
                            Text("Mic unmutes while the shortcut is held")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $pushToTalk)
                            .controlSize(.mini)
                    }

                    Divider()

                    HStack {
                        Text("Launch Micmute at login")
                        Spacer()
                        Toggle("", isOn: $launchAtLogin)
                            .controlSize(.mini)
                            .onChange(of: launchAtLogin) { newValue, _ in
                                LaunchAtLoginManager.update(newValue)
                            }
                    }

                    Divider()

                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sync system sound effects")
                            Text("Match macOS \"Play sound effects through\" with the selected output device")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $syncSoundEffectsWithOutput)
                            .controlSize(.mini)
                            .onChange(of: syncSoundEffectsWithOutput) { _, newValue in
                                guard newValue else { return }
                                contentViewModel.syncSoundEffectsToCurrentOutput()
                            }
                    }
                }
                .toggleStyle(.switch)
            }
            
            CustomSectionView(title: "Menubar icon") {
                VStack(spacing: 12) {
                    HStack {
                        Text("Behavior on left click")
                        Spacer()
                        Picker("", selection: $menuBehaviorOnClick) {
                            Text("Shows menu").tag(MenuBarBehavior.menu)
                            Text("Toggle mute").tag(MenuBarBehavior.mute)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .toggleStyle(.switch)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal)
    }
}
