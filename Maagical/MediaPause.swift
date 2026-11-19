import AppKit
import OSLog

private let log = Logger(subsystem: "one.floo.vibeflow", category: "media")

/// Pauses whatever plays in Now Playing (Music, Spotify, a YouTube tab) while Maagical reads or
/// listens, and plays it on afterwards. Only media Maagical paused itself is started again.
///
/// Uses the private MediaRemote framework, loaded at runtime: macOS 15.4 and later refuse most of
/// it to other apps, but the is-playing query and the play and pause commands still answer
/// (checked on macOS 26.5). If they stop answering, nothing pauses and nothing ever starts.
@MainActor
final class MediaPause {
    /// A read that ends and a dictation or answer that follows within this time keep media paused.
    static let releaseDelay: Duration = .seconds(1)

    private typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool
    private typealias IsPlaying = @convention(c) (DispatchQueue, @escaping @Sendable (Bool) -> Void) -> Void
    /// MRMediaRemoteCommand values.
    private static let play: UInt32 = 0
    private static let pause: UInt32 = 1

    private let sendCommand: SendCommand?
    private let isPlaying: IsPlaying?
    private var active = false
    private var pausedByUs = false
    private var release: Task<Void, Never>?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
        sendCommand = dlsym(handle, "MRMediaRemoteSendCommand").map { unsafeBitCast($0, to: SendCommand.self) }
        isPlaying = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying").map { unsafeBitCast($0, to: IsPlaying.self) }
        // Quitting mid-read must not leave the user's music paused.
        _ = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func setActive(_ on: Bool) {
        if on {
            release?.cancel()
            release = nil
            guard !active else { return }
            active = true
            isPlaying?(.main) { playing in
                Task { @MainActor in self.pauseIfStillActive(playing) }
            }
        } else {
            guard active, release == nil else { return }
            release = Task { [weak self] in
                try? await Task.sleep(for: Self.releaseDelay)
                guard !Task.isCancelled else { return }
                self?.end()
            }
        }
    }

    private func pauseIfStillActive(_ playing: Bool) {
        // The answer can arrive after a short read already ended: then nothing is paused.
        guard active, release == nil, playing, !pausedByUs, sendCommand?(Self.pause, nil) == true else { return }
        pausedByUs = true
        log.notice("Media paused")
    }

    private func end() {
        release?.cancel()
        release = nil
        active = false
        guard pausedByUs else { return }
        pausedByUs = false
        _ = sendCommand?(Self.play, nil)
        log.notice("Media resumed")
    }
}
