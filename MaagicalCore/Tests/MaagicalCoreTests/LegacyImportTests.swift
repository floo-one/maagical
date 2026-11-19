import Foundation
import Testing
@testable import MaagicalCore

/// The move from one.floo.vibeflow to one.floo.maagical (docs/designs/bundle-id-move.md).
struct LegacyImportTests {
    @Test func identityFollowsTheBundleID() {
        let new = AppIdentity(bundleID: "one.floo.maagical")
        #expect(!new.isLegacy && new.folderName == "Maagical" && new.keychainService == "one.floo.maagical")
        #expect(!AppIdentity(bundleID: "one.floo.maagical.dev").isLegacy)
        let bridge = AppIdentity(bundleID: "one.floo.vibeflow")
        #expect(bridge.isLegacy && bridge.folderName == "VibeFlow" && bridge.keychainService == "one.floo.vibeflow")
        #expect(AppIdentity(bundleID: "one.floo.vibeflow.dev").isLegacy)
        #expect(!AppIdentity(bundleID: nil).isLegacy)
    }

    @Test func copiesOwnSettingsAndMenuBarPositionsButNotSystemKeys() {
        let old: [String: Any] = [
            "launchAtLogin": true,
            "rename.noticeSeen": true,
            "KeyboardShortcuts_read": "{}",
            "NSStatusItem Preferred Position vibeflow-icon": 662,
            "NSStatusItem VisibleCC vibeflow-icon": 1,
            "NSStatusItem Preferred Position Item-0": 700,
            "NSWindow Frame Settings": "0 0 100 100",
            "AppleLanguages": ["de"],
            "SULastCheckTime": Date(),
            "update.releaseDMG": "file:///tmp/Maagical.dmg",
            "update.newestMain": true,
        ]
        let copied = LegacyImport.defaults(from: old) { _ in false }
        #expect(Set(copied.keys) == ["launchAtLogin", "rename.noticeSeen", "KeyboardShortcuts_read", "update.newestMain",
                                     "NSStatusItem Preferred Position maagical-icon", "NSStatusItem VisibleCC maagical-icon",
                                     "NSStatusItem Preferred Position Item-0"])
        #expect(copied["NSStatusItem Preferred Position maagical-icon"] as? Int == 662)
    }

    @Test func neverOverwritesWhatIsAlreadySet() {
        let copied = LegacyImport.defaults(from: ["launchAtLogin": true, "speed": 1.2]) { $0 == "launchAtLogin" }
        #expect(Set(copied.keys) == ["speed"])
    }

    @Test func copiesTheFolderOnceAndKeepsTheOld() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "maagical-import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appending(path: "VibeFlow"), new = root.appending(path: "Maagical")
        #expect(try LegacyImport.copyFolder(from: old, to: new) == false)

        try FileManager.default.createDirectory(at: old.appending(path: "Transcripts"), withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: old.appending(path: "history.json"))
        #expect(try LegacyImport.copyFolder(from: old, to: new))
        #expect(FileManager.default.fileExists(atPath: new.appending(path: "history.json").path))
        #expect(FileManager.default.fileExists(atPath: new.appending(path: "Transcripts").path))
        #expect(FileManager.default.fileExists(atPath: old.appending(path: "history.json").path))

        try Data("[1]".utf8).write(to: old.appending(path: "history.json"))
        #expect(try LegacyImport.copyFolder(from: old, to: new) == false)
        #expect(try Data(contentsOf: new.appending(path: "history.json")) == Data("[]".utf8))
    }
}
