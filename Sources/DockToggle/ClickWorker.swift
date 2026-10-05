import Foundation
import AppKit
import DockToggleCore
import OSLog

final class ClickWorker {
    let mailbox = ClickMailbox()
    private let queue = DispatchQueue(label: "dev.nojusl.DockToggle.accessibility", qos: .userInitiated)
    private let runtime: RuntimeState
    private let backend: AccessibilityBackend
    private let engine: ToggleEngine<AccessibilityBackend>
    private let log = Logger(subsystem: "dev.nojusl.DockToggle", category: "Windows")
    init(runtime: RuntimeState) {
        self.runtime = runtime
        backend = AccessibilityBackend(runtime: runtime)
        engine = ToggleEngine(backend: backend)
    }
    func submit(_ click: Click) {
        guard mailbox.offer(click) else { return }
        queue.async { [self] in
            while let next = mailbox.take() {
                let current = { [self] in
                    let environment = runtime.snapshot()
                    guard environment.enabled && environment.epoch == next.epoch &&
                        environment.mode == next.mode &&
                        environment.active == next.activeApp &&
                        mailbox.isCurrent(next, now: monotonicTime()) else { return false }
                    // Verify outside the callback as well, in case UI-thread
                    // activation notifications have not yet updated the snapshot.
                    guard let active = NSWorkspace.shared.frontmostApplication,
                          let launched = active.launchDate else { return false }
                    return AppIdentity(pid: active.processIdentifier, launched: launched.timeIntervalSince1970) == next.activeApp
                }
                backend.mayProceed = current
                let outcome: ToggleOutcome
                if next.releasedAt == nil { outcome = engine.prepare(next, current: current) }
                else { outcome = engine.complete(next, current: current) }
                // No window titles, app paths or pointer coordinates in logs.
                if outcome == .failed || outcome == .minimized || outcome == .restored || outcome == .hidden {
                    log.info("Click outcome: \(outcome.rawValue, privacy: .public)")
                }
            }
            backend.mayProceed = { false }
        }
    }
    func reset(epoch: UInt64) {
        mailbox.invalidate(epoch: epoch)
        // No reset closures queued behind IPC. Engine clears lazily on the next epoch.
    }
}
