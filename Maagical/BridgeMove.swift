import AppKit
import KeychainAccess
import MaagicalCore
import OSLog
import Security
import ServiceManagement

/// The bridge (docs/designs/bundle-id-move.md): the last build under the old bundle id,
/// one.floo.vibeflow, which every old install gets through its old update feed. Sparkle cannot
/// install across a bundle id change, so this does it in one click: it downloads the newest
/// release (one.floo.maagical), checks it like Back to Stable does (StableInstaller), puts it
/// in place as Maagical.app, hands the API keys over so the new app reads them without a
/// Keychain prompt, and opens it. The new app imports settings and data itself
/// (LegacyMigration). What cannot move: macOS permissions, which belong to the bundle id.
@MainActor @Observable
final class BridgeMove {
    static let shared = BridgeMove()

    /// Only the bridge release moves; a Dev build from before 1.6 never does.
    static var isBridge: Bool { Bundle.main.bundleIdentifier == AppIdentity.legacyBundleID }

    /// The step in progress, for the panel card; nil when idle.
    private(set) var step: String?

    private let log = Logger(subsystem: "one.floo.maagical", category: "update")

    /// At launch, so the move happens on the day the bridge arrives. Later keeps the card in
    /// the menu bar panel.
    func offerAtLaunch() {
        guard Self.isBridge else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Maagical has a new home"
        alert.informativeText = """
            One last update moves Maagical to its new identity on this Mac. Your keys, settings \
            and history come along. Afterwards macOS asks once more for Accessibility and the \
            microphone.
            """
        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn { start() }
    }

    func start() {
        guard Self.isBridge, step == nil else { return }
        Task {
            do {
                try await run()
            } catch {
                log.error("new home: \(error.localizedDescription, privacy: .public)")
                step = nil
                NSApp.activate()
                let alert = NSAlert()
                alert.messageText = "Could not move Maagical"
                alert.informativeText = "\(error.localizedDescription) Try again from the menu bar panel."
                alert.runModal()
            }
        }
    }

    private func run() async throws {
        let current = Bundle.main.bundleURL
        // A 1.5 release still sits at VibeFlow.app; the new app goes next to it as Maagical.app.
        let target = current.deletingLastPathComponent().appending(path: "Maagical.app")
        let files = FileManager.default
        let work = try files.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true)
        defer { try? files.removeItem(at: work) }

        let staged = try await StableInstaller.fetchRelease(into: work, identifier: AppIdentity.bundleID, log: log) { self.step = $0 }

        step = "Installing…"
        if files.fileExists(atPath: target.path) {
            _ = try files.replaceItemAt(target, withItemAt: staged)
        } else {
            try files.moveItem(at: staged, to: target)
        }
        if current.standardizedFileURL != target.standardizedFileURL {
            try? files.trashItem(at: current, resultingItemURL: nil)
        }
        let keys = Self.handOverKeys(to: target)
        // The old login item would point at an app that is gone; the new app registers its
        // own when Open at Login was on.
        try? await SMAppService.mainApp.unregister()
        log.notice("new home: installed at \(target.path, privacy: .public), \(keys, privacy: .public) keys handed over, opening")

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        do {
            try await NSWorkspace.shared.openApplication(at: target, configuration: configuration)
        } catch {
            throw StableInstaller.Failure("The new Maagical is installed, but did not open: \(error.localizedDescription) Open it from Applications.")
        }
        NSApp.terminate(nil)
    }

    /// Copies the keys to the new Keychain services with an access list that names this app
    /// and the new one, so the new app reads them without asking. This app can read the old
    /// items without a prompt; the new one could not. Keys already there stay.
    private static func handOverKeys(to app: URL) -> Int {
        var me: SecTrustedApplication?
        var them: SecTrustedApplication?
        guard SecTrustedApplicationCreateFromPath(nil, &me) == errSecSuccess,
              SecTrustedApplicationCreateFromPath(app.path, &them) == errSecSuccess,
              let me, let them else { return 0 }
        let moves: [(from: String, to: String, keys: [SecretKey])] = [
            (AppIdentity.legacyBundleID, AppIdentity.bundleID, SecretKey.allCases.filter { !$0.readsOnDemand }),
            (AppIdentity.legacyBundleID + ".google", AppIdentity.bundleID + ".google", [.googleRefreshToken]),
        ]
        var copied = 0
        for move in moves {
            for key in move.keys {
                guard let value = try? Keychain(service: move.from).get(key.rawValue), !value.isEmpty else { continue }
                var access: SecAccess?
                guard SecAccessCreate(move.to as CFString, [me, them] as CFArray, &access) == errSecSuccess, let access else { continue }
                let item: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: move.to,
                    kSecAttrAccount as String: key.rawValue,
                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
                    kSecAttrSynchronizable as String: false,
                    kSecAttrAccess as String: access,
                    kSecValueData as String: Data(value.utf8),
                ]
                if SecItemAdd(item as CFDictionary, nil) == errSecSuccess { copied += 1 }
            }
        }
        return copied
    }
}
