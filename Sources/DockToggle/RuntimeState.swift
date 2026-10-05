import AppKit
import ApplicationServices
import DockToggleCore

struct RunningApp {
    let identity: AppIdentity
    let bundleURL: URL
}

struct EnvironmentSnapshot {
    var enabled = false
    var mode: ToggleMode = .hideShow
    var epoch: UInt64 = 0
    var active: AppIdentity?
    var dockPID: pid_t?
    var applications: [RunningApp] = []
    var displays: [CGRect] = []
}

/// Tiny value snapshots shared across the UI, listener and AX worker. No AX calls
/// or filesystem work while holding this lock.
final class RuntimeState {
    private let lock = NSLock()
    private var environment = EnvironmentSnapshot()
    private var listener = "Starting"
    private var recoveries = 0
    func snapshot() -> EnvironmentSnapshot {
        lock.lock(); defer { lock.unlock() }; return environment
    }
    func update(_ value: EnvironmentSnapshot) {
        lock.lock(); defer { lock.unlock() }; environment = value
    }
    func setListener(_ value: String, recovered: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        listener = value
        if recovered { recoveries += 1 }
    }
    func listenerStatus() -> (String, Int) {
        lock.lock(); defer { lock.unlock() }; return (listener, recoveries)
    }
}

func monotonicTime() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
