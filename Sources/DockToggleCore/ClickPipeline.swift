import Foundation

public struct Point: Equatable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    func distance(to other: Point) -> Double { hypot(x - other.x, y - other.y) }
}

/// PID plus launch time prevents an old window handle being reused for a new process.
public struct AppIdentity: Hashable {
    public let pid: Int32
    public let launched: TimeInterval
    public init(pid: Int32, launched: TimeInterval) { self.pid = pid; self.launched = launched }
}

public enum ToggleMode: String {
    case minimizeRestore
    case hideShow
}

public struct Click: Equatable {
    public let sequence: UInt64
    public let epoch: UInt64
    public let mode: ToggleMode
    public let point: Point
    public let activeApp: AppIdentity?
    public let startedAt: TimeInterval
    public var releasedAt: TimeInterval?
    public var releasedPoint: Point?
    public init(sequence: UInt64, epoch: UInt64, point: Point, activeApp: AppIdentity?,
                startedAt: TimeInterval, releasedAt: TimeInterval? = nil, mode: ToggleMode = .minimizeRestore) {
        self.sequence = sequence; self.epoch = epoch; self.point = point
        self.mode = mode
        self.activeApp = activeApp; self.startedAt = startedAt; self.releasedAt = releasedAt
    }
}

/// Called only on the listener thread. Any drag event disqualifies the gesture, even
/// if the pointer later returns to its origin. A long press also belongs to the Dock.
public struct ClickRecognizer {
    private var down: Click?
    public init() {}
    public mutating func begin(_ click: Click, modified: Bool) -> Click? {
        down = modified ? nil : click
        return down
    }
    public mutating func cancel() { down = nil }
    public mutating func finish(at point: Point, time: TimeInterval, modified: Bool) -> Click? {
        defer { down = nil }
        guard var click = down, !modified, time >= click.startedAt,
              time - click.startedAt <= 0.5, click.point.distance(to: point) <= 4 else { return nil }
        click.releasedAt = time
        click.releasedPoint = point
        return click
    }
}

/// A bounded mailbox, rather than one dispatched closure per click. Superseded work
/// is invalid immediately, including a worker currently inside an Accessibility read.
public final class ClickMailbox {
    private let lock = NSLock()
    private var sequence: UInt64 = 0
    private var epoch: UInt64 = 0
    private var pending: Click?
    private var releaseSeen = false
    private var draining = false
    public init() {}

    public func nextSequence() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        sequence &+= 1
        pending = nil
        releaseSeen = false
        return sequence
    }

    /// Returns true only when a single worker needs scheduling.
    public func offer(_ click: Click) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard click.sequence == sequence, click.epoch == epoch else { return false }
        if click.releasedAt != nil { releaseSeen = true }
        pending = click
        if draining { return false }
        draining = true
        return true
    }

    public func take() -> Click? {
        lock.lock(); defer { lock.unlock() }
        guard let click = pending else { draining = false; return nil }
        pending = nil
        return click
    }

    public func invalidate(epoch newEpoch: UInt64? = nil) {
        lock.lock(); defer { lock.unlock() }
        sequence &+= 1
        if let newEpoch { epoch = newEpoch }
        pending = nil
        releaseSeen = false
    }

    public func isCurrent(_ click: Click, now: TimeInterval) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard click.sequence == sequence, click.epoch == epoch else { return false }
        if let release = click.releasedAt { return now >= release && now - release <= 0.25 }
        // Preflight must finish before release; post-release native Dock state is
        // not a safe snapshot of the window the user originally clicked to toggle.
        return !releaseSeen && now >= click.startedAt && now - click.startedAt <= 0.5
    }
}
