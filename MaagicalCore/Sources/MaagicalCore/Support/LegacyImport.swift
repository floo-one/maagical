import Foundation

/// What the first one.floo.maagical launch takes over from one.floo.vibeflow
/// (docs/designs/bundle-id-move.md). The app does the reading and writing (LegacyMigration);
/// these are the rules, kept here so they are tested.
public enum LegacyImport {
    /// The menu bar icon's autosave name before and after the move.
    static let iconNames = (old: "vibeflow-icon", new: "maagical-icon")

    /// The settings to copy from the old preferences domain: everything Maagical wrote itself,
    /// never what is already set under the new id. Of the system's own keys only the menu bar
    /// positions come along, renamed for the icon, so every item stays where it was. Sparkle's
    /// bookkeeping (SU…) and a test download URL for the bridge stay behind.
    public static func defaults(from old: [String: Any], isSet: (String) -> Bool) -> [String: Any] {
        var copied: [String: Any] = [:]
        for (key, value) in old {
            let key = key.hasPrefix("NSStatusItem ") ? key.replacingOccurrences(of: iconNames.old, with: iconNames.new) : key
            let system = key.hasPrefix("NS") || key.hasPrefix("Apple") || key.hasPrefix("SU") || key == "update.releaseDMG"
            guard !system || key.hasPrefix("NSStatusItem "), !isSet(key) else { continue }
            copied[key] = value
        }
        return copied
    }

    /// Copies the old Application Support (or Caches) folder to the new one when the new one
    /// does not exist yet. On APFS a copy is a clone, so it takes no time or space. The old
    /// folder stays for an old copy that still runs on this Mac (the author's Dev builds).
    /// True when it copied.
    @discardableResult
    public static func copyFolder(from old: URL, to new: URL, files: FileManager = .default) throws -> Bool {
        guard files.fileExists(atPath: old.path), !files.fileExists(atPath: new.path) else { return false }
        try files.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
        try files.copyItem(at: old, to: new)
        return true
    }
}
