import AppKit
import CoreGraphics
import Observation
import OSLog

private let log = Logger(subsystem: "one.floo.vibeflow", category: "shortcuts")

/// Notices when another app holds secure keyboard input, which blocks every Maagical shortcut
/// without a sound or an error. Apps turn it on while a password field has focus (Chrome can
/// leave it on afterwards, 2026-11-20). The menu bar icon and panel then name the app.
///
/// macOS posts no notification for it, so this polls the login session's
/// kCGSSessionSecureInputPID (present only while some process holds it) every two seconds.
/// It reports only after two samples in a row, so typing a password does not flash the icon.
@MainActor
@Observable
final class SecureInputWatch {
    /// The app holding secure input, nil while shortcuts work.
    private(set) var blockingApp: String?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var pendingPID: pid_t?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer?.tolerance = 0.5
    }

    private func sample() {
        let pid = Self.holderPID()
        // Maagical's own key fields (Settings > Keys) hold it too; the user is typing there.
        guard let pid, pid != ProcessInfo.processInfo.processIdentifier else {
            pendingPID = nil
            if blockingApp != nil {
                log.notice("Secure input released, shortcuts work again")
                blockingApp = nil
            }
            return
        }
        guard pendingPID == pid else {
            pendingPID = pid
            return
        }
        let app = NSRunningApplication(processIdentifier: pid)
        let name = app?.localizedName ?? "Another app"
        guard name != blockingApp else { return }
        log.notice("Secure input held by \(app?.bundleIdentifier ?? "pid \(pid)", privacy: .public), shortcuts blocked")
        blockingApp = name
    }

    private static func holderPID() -> pid_t? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = session["kCGSSessionSecureInputPID"] as? Int, pid > 0 else { return nil }
        return pid_t(pid)
    }
}
