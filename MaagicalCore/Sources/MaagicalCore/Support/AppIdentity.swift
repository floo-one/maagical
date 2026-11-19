import Foundation

/// Which names this copy of the app uses on disk and in the Keychain
/// (docs/designs/bundle-id-move.md). Maagical is one.floo.maagical (Dev: .dev) since 1.6;
/// before that it was one.floo.vibeflow. The bridge build that moves old installs still runs
/// under the old id, so it keeps reading the old folder and Keychain item until it has moved.
public struct AppIdentity: Equatable, Sendable {
    public static let bundleID = "one.floo.maagical"
    public static let legacyBundleID = "one.floo.vibeflow"

    /// A copy under the old bundle id: the bridge release, or a Dev build from before 1.6.
    public let isLegacy: Bool

    public init(bundleID: String?) {
        isLegacy = bundleID?.hasPrefix(Self.legacyBundleID) == true
    }

    public static let current = AppIdentity(bundleID: Bundle.main.bundleIdentifier)

    /// The folder in Application Support and Caches.
    public var folderName: String { isLegacy ? "VibeFlow" : "Maagical" }
    /// The Keychain service of the API keys, shared by the release and Dev.
    public var keychainService: String { isLegacy ? Self.legacyBundleID : Self.bundleID }

    /// ~/Library/Application Support/Maagical
    public var supportDirectory: URL { URL.applicationSupportDirectory.appending(path: folderName) }
    /// ~/Library/Caches/Maagical
    public var cachesDirectory: URL { URL.cachesDirectory.appending(path: folderName) }
}
