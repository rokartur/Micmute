import Foundation
import Combine

@MainActor
final class ShortcutPreferences: ObservableObject {
    @Published var toggleMuteShortcut: Shortcut?
    @Published var checkMuteShortcut: Shortcut?
    @Published var pushToTalkShortcut: Shortcut?

    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []

    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
        self.toggleMuteShortcut = Self.loadShortcut(.toggleMute, from: defaults) ?? .defaultToggleMute
        self.checkMuteShortcut = Self.loadShortcut(.checkMute, from: defaults) ?? .defaultCheckMute
        self.pushToTalkShortcut = Self.loadShortcut(.pushToTalk, from: defaults)

        observeChanges()
    }

    private func observeChanges() {
        $toggleMuteShortcut
            .dropFirst()
            .sink { [weak self] shortcut in
                self?.save(shortcut, for: .toggleMute)
            }
            .store(in: &cancellables)

        $checkMuteShortcut
            .dropFirst()
            .sink { [weak self] shortcut in
                self?.save(shortcut, for: .checkMute)
            }
            .store(in: &cancellables)

        $pushToTalkShortcut
            .dropFirst()
            .sink { [weak self] shortcut in
                self?.save(shortcut, for: .pushToTalk)
            }
            .store(in: &cancellables)
    }

    func resetToDefaults() {
        toggleMuteShortcut = .defaultToggleMute
        checkMuteShortcut = .defaultCheckMute
        pushToTalkShortcut = nil
    }

    private func save(_ shortcut: Shortcut?, for identifier: ShortcutIdentifier) {
        let key = identifier.defaultsKey
        if let shortcut {
            if let data = try? JSONEncoder().encode(shortcut) {
                defaults.set(data, forKey: key)
            }
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func loadShortcut(_ identifier: ShortcutIdentifier, from defaults: UserDefaults) -> Shortcut? {
        let key = identifier.defaultsKey
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }
}
