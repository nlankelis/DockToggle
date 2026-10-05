import Foundation

public enum BackendFailure: Error { case transient, invalidWindow, unsupported }

public struct WindowState {
    public let minimized: Bool
    public let canMinimize: Bool
    public init(minimized: Bool, canMinimize: Bool) {
        self.minimized = minimized; self.canMinimize = canMinimize
    }
}

public protocol WindowBackend {
    associatedtype Window: Equatable
    func application(at point: Point) throws -> AppIdentity?
    func isRunning(_ app: AppIdentity) -> Bool
    func focusedWindow(of app: AppIdentity) throws -> Window?
    func state(of window: Window) throws -> WindowState
    func setMinimized(_ minimized: Bool, window: Window) throws
    func raise(_ window: Window) throws
    func hide(_ app: AppIdentity) throws
}

public enum ToggleOutcome: String { case native, minimized, restored, hidden, cancelled, skipped, failed }

/// Confined to the Accessibility worker. State changes only after a successful AX
/// write. A failed read never clears other apps' remembered windows.
public final class ToggleEngine<Backend: WindowBackend> {
    private let backend: Backend
    private var remembered: [AppIdentity: Backend.Window] = [:]
    private var prepared: (click: Click, app: AppIdentity, window: Backend.Window, restore: Bool)?
    private var epoch: UInt64?
    private var mode: ToggleMode?
    public init(backend: Backend) { self.backend = backend }
    public var rememberedCount: Int { remembered.count }

    public func reset() { prepared = nil; remembered.removeAll(); epoch = nil; mode = nil }

    public func prepare(_ click: Click, current: () -> Bool) -> ToggleOutcome {
        if epoch != click.epoch || mode != click.mode {
            reset(); epoch = click.epoch; mode = click.mode
        }
        prepared = nil
        remembered = remembered.filter { backend.isRunning($0.key) }
        guard current() else { return .cancelled }
        do {
            guard let app = try backend.application(at: click.point), backend.isRunning(app),
                  current() else { return .skipped }
            guard app == click.activeApp else { return .native }
            if click.mode == .minimizeRestore, let window = remembered[app] {
                do {
                    let state = try backend.state(of: window)
                    guard current() else { return .cancelled }
                    if state.minimized {
                        prepared = (click, app, window, true)
                        return .skipped
                    }
                    // The user restored it outside DockToggle; resume focused-window behavior.
                    remembered.removeValue(forKey: app)
                } catch BackendFailure.invalidWindow {
                    remembered.removeValue(forKey: app)
                }
            }
            guard let window = try backend.focusedWindow(of: app) else { return .native }
            let state = try backend.state(of: window)
            guard current() else { return .cancelled }
            guard !state.minimized, state.canMinimize else { return .native }
            prepared = (click, app, window, false)
            return .skipped
        } catch { return .failed }
    }

    public func complete(_ click: Click, current: () -> Bool) -> ToggleOutcome {
        guard click.releasedAt != nil, current() else { return .cancelled }
        guard let plan = prepared, plan.click.sequence == click.sequence,
              plan.click.epoch == click.epoch, plan.click.mode == click.mode else { return .skipped }
        prepared = nil
        guard backend.isRunning(plan.app) else {
            remembered.removeValue(forKey: plan.app)
            return .skipped
        }
        do {
            // Revalidate live Dock identity at release. No cached hit rectangles.
            guard try backend.application(at: click.releasedPoint ?? click.point) == plan.app, current() else { return .cancelled }
            let state = try backend.state(of: plan.window)
            guard current() else { return .cancelled }
            if plan.click.mode == .hideShow {
                // Hiding is app-wide. The next click is inactive-app activation,
                // so the Dock itself unhides it; never hide it on that show click.
                guard state.canMinimize, !state.minimized else { return .native }
                try backend.hide(plan.app)
                return .hidden
            }
            if plan.restore {
                if state.minimized {
                    try backend.setMinimized(false, window: plan.window)
                }
                remembered.removeValue(forKey: plan.app)
                // Native Dock may already have restored it. Never minimize it again.
                if current() { try? backend.raise(plan.window) }
                return .restored
            }
            guard state.canMinimize, !state.minimized else { return .native }
            try backend.setMinimized(true, window: plan.window)
            remembered[plan.app] = plan.window
            return .minimized
        } catch BackendFailure.invalidWindow {
            remembered.removeValue(forKey: plan.app)
            return .skipped
        } catch { return .failed }
    }
}
