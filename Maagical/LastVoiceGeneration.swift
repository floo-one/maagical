import AppKit
import Foundation
import MaagicalCore
import Observation
import OSLog

private let log = Logger(subsystem: "one.floo.maagical", category: "last-generation")

/// The audio of the last ElevenLabs read or answer, as an .m4a people can save or share
/// (the Last read row in the panel). One file, replaced by every new generation; it lives in
/// ~/Library/Caches/Maagical and is not kept across launches.
@MainActor
@Observable
final class LastVoiceGeneration {
    /// The finished file, nil until a generation has been written.
    private(set) var fileURL: URL?
    /// Its length in seconds.
    private(set) var duration: Double?
    @ObservationIgnored private var generation = 0

    #if DEBUG
    static let folder = AppIdentity.current.cachesDirectory.appending(path: "LastRead-dev")
    #else
    static let folder = AppIdentity.current.cachesDirectory.appending(path: "LastRead")
    #endif

    init() {
        try? FileManager.default.removeItem(at: Self.folder)
    }

    /// Takes the PCM of a finished generation and writes it off the main thread.
    func store(_ pcm: Data) {
        generation += 1
        let current = generation
        let name = Self.fileName(for: .now)
        let folder = Self.folder
        Task {
            let result = await Task.detached(priority: .utility) { () -> Result<URL, Error> in
                Result {
                    try? FileManager.default.removeItem(at: folder)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let url = folder.appending(path: name)
                    try GeneratedAudioFile.writeM4A(pcm16: pcm, to: url)
                    return url
                }
            }.value
            guard current == generation else { return }
            switch result {
            case .success(let url):
                fileURL = url
                duration = GeneratedAudioFile.duration(ofPCM16: pcm)
                log.notice("last generation saved, \(GeneratedAudioFile.duration(ofPCM16: pcm), format: .fixed(precision: 1)) s")
            case .failure(let error):
                fileURL = nil
                duration = nil
                log.error("last generation not saved: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
    }

    /// Copies the file to ~/Downloads and shows it in Finder.
    func saveToDownloads() {
        guard let fileURL else { return }
        let downloads = URL.downloadsDirectory
        var target = downloads.appending(path: fileURL.lastPathComponent)
        let base = fileURL.deletingPathExtension().lastPathComponent
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = downloads.appending(path: "\(base) \(n).\(GeneratedAudioFile.fileExtension)")
            n += 1
        }
        do {
            try FileManager.default.copyItem(at: fileURL, to: target)
            NSWorkspace.shared.activateFileViewerSelecting([target])
        } catch {
            log.error("save to Downloads failed: \(String(describing: type(of: error)), privacy: .public)")
            NSSound.beep()
        }
    }

    /// "Maagical 2026-11-14 at 15.32.m4a": never the read text, which can be private.
    static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Maagical \(formatter.string(from: date)).\(GeneratedAudioFile.fileExtension)"
    }
}
