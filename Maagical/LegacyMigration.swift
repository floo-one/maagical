import Foundation
import KeychainAccess
import MaagicalCore
import OSLog

/// One-time import from the app's previous identity, one.floo.vibeflow (Dev:
/// one.floo.vibeflow.dev), at the first launch as one.floo.maagical
/// (docs/designs/bundle-id-move.md): settings, API keys, the Google sign-in and the
/// Application Support folder. Runs before any store is created. Idempotent: a marker in the
/// new defaults stops it from running twice, and it never overwrites what already exists under
/// the new identity. A fresh install finds nothing and creates nothing under the old names.
enum LegacyMigration {
    private static let markerKey = "migratedFromVibeFlow"
    private static let log = Logger(subsystem: "one.floo.maagical", category: "migration")

    /// True when settings came over, so the caller can restore launch at login.
    @discardableResult
    static func runIfNeeded(defaults: UserDefaults = .standard) -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier, !AppIdentity.current.isLegacy,
              !defaults.bool(forKey: markerKey) else { return false }
        let oldID = AppIdentity.legacyBundleID + bundleID.dropFirst(AppIdentity.bundleID.count)
        let copiedDefaults = migrateDefaults(from: oldID, into: defaults)
        let copiedKeys = migrateKeychain(oldID: oldID, newID: bundleID)
        var copiedFolder = false
        do {
            copiedFolder = try LegacyImport.copyFolder(from: AppIdentity(bundleID: oldID).supportDirectory,
                                                       to: AppIdentity.current.supportDirectory)
        } catch {
            log.error("legacy migration: could not copy the data folder: \(error.localizedDescription, privacy: .public)")
        }
        defaults.set(true, forKey: markerKey)
        log.notice("legacy migration from \(oldID, privacy: .public): \(copiedDefaults, privacy: .public) settings, \(copiedKeys, privacy: .public) keys, folder \(copiedFolder ? "copied" : "not copied", privacy: .public)")
        return copiedDefaults > 0
    }

    /// Presets, preferences, KeyboardShortcuts bindings and the menu bar positions. Not
    /// sandboxed, so the old app's preferences domain is readable by name.
    private static func migrateDefaults(from oldID: String, into defaults: UserDefaults) -> Int {
        guard let old = defaults.persistentDomain(forName: oldID) else { return 0 }
        let copied = LegacyImport.defaults(from: old) { defaults.object(forKey: $0) != nil }
        for (key, value) in copied { defaults.set(value, forKey: key) }
        return copied.count
    }

    /// The bridge build hands the keys over before it opens this app (BridgeMove), so this
    /// usually finds them in place. A copy installed by hand reads the old items instead, and
    /// macOS asks once for each, since they belong to the old app.
    private static func migrateKeychain(oldID: String, newID: String) -> Int {
        let pairs = [
            (Keychain(service: AppIdentity.legacyBundleID), Keychain(service: AppIdentity.current.keychainService).accessibility(.whenUnlocked),
             SecretKey.allCases.filter { !$0.readsOnDemand }),
            (Keychain(service: oldID + ".google"), Keychain(service: newID + ".google").accessibility(.whenUnlocked),
             [SecretKey.googleRefreshToken]),
        ]
        var copied = 0
        for (old, new, keys) in pairs {
            for key in keys {
                guard (try? new.get(key.rawValue)) == nil,
                      let value = try? old.get(key.rawValue), !value.isEmpty else { continue }
                do {
                    try new.set(value, key: key.rawValue)
                    copied += 1
                } catch {
                    log.error("legacy migration: could not copy \(key.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        return copied
    }
}
