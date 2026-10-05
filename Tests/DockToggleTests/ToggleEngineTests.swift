import Foundation
import DockToggleCore

private final class FakeBackend: WindowBackend {
    typealias Window = Int
    var hit: AppIdentity?
    var running: Set<AppIdentity> = []
    var focused: [AppIdentity: Int] = [:]
    var windows: [Int: WindowState] = [:]
    var writes: [(Int, Bool)] = []
    var raised: [Int] = []
    var hidden: [AppIdentity] = []
    var hitFailure = false
    var stateFailure = false
    var writeFailure = false
    var hideFailure = false
    var onRead: (() -> Void)?
    func application(at point: Point) throws -> AppIdentity? {
        if hitFailure { throw BackendFailure.transient }; return hit
    }
    func isRunning(_ app: AppIdentity) -> Bool { running.contains(app) }
    func focusedWindow(of app: AppIdentity) throws -> Int? { focused[app] }
    func state(of window: Int) throws -> WindowState {
        onRead?()
        if stateFailure { throw BackendFailure.transient }
        guard let state = windows[window] else { throw BackendFailure.invalidWindow }
        return state
    }
    func setMinimized(_ minimized: Bool, window: Int) throws {
        if writeFailure { throw BackendFailure.transient }
        guard let old = windows[window] else { throw BackendFailure.invalidWindow }
        writes.append((window, minimized))
        windows[window] = WindowState(minimized: minimized, canMinimize: old.canMinimize)
    }
    func raise(_ window: Int) throws { raised.append(window) }
    func hide(_ app: AppIdentity) throws {
        if hideFailure { throw BackendFailure.transient }
        guard running.contains(app) else { throw BackendFailure.invalidWindow }
        hidden.append(app)
    }
}

struct ToggleEngineTests {
    private let a = AppIdentity(pid: 42, launched: 1)
    private let b = AppIdentity(pid: 43, launched: 1)
    private func fixture() -> (FakeBackend, ToggleEngine<FakeBackend>) {
        let backend = FakeBackend()
        backend.hit = a; backend.running = [a, b]
        backend.focused = [a: 1, b: 3]
        backend.windows = [1: WindowState(minimized: false, canMinimize: true),
                           2: WindowState(minimized: false, canMinimize: true),
                           3: WindowState(minimized: false, canMinimize: true)]
        return (backend, ToggleEngine(backend: backend))
    }
    private func click(_ sequence: UInt64, active: AppIdentity?, epoch: UInt64 = 0,
                       mode: ToggleMode = .minimizeRestore) -> Click {
        Click(sequence: sequence, epoch: epoch, point: Point(x: 0, y: 0), activeApp: active, startedAt: 10, mode: mode)
    }
    @discardableResult
    private func toggle(_ engine: ToggleEngine<FakeBackend>, _ sequence: UInt64 = 1,
                        active: AppIdentity? = nil, epoch: UInt64 = 0,
                        mode: ToggleMode = .minimizeRestore) -> ToggleOutcome {
        var next = click(sequence, active: active ?? a, epoch: epoch, mode: mode)
        _ = engine.prepare(next, current: { true })
        next.releasedAt = 10.1
        return engine.complete(next, current: { true })
    }
    func testInactiveAppClickRemainsNative() {
        let (backend, engine) = fixture()
        expect(toggle(engine, active: b) == .skipped)
        expect(backend.writes.isEmpty)
    }
    func testMinimizeFocusedWindowAndRestoreSameWindowWithMultipleWindows() {
        let (backend, engine) = fixture()
        expect(toggle(engine) == .minimized)
        backend.focused[a] = 2
        expect(toggle(engine, 2) == .restored)
        expect(backend.writes.map { $0.0 } == [1, 1])
        expect(backend.writes.map { $0.1 } == [true, false])
        expect(backend.raised == [1])
        expect(engine.rememberedCount == 0)
        expect(!(backend.windows[2]!.minimized))
    }
    func testFocusedWindowIsCapturedBeforeNativeDockChangesFocus() {
        let (backend, engine) = fixture()
        var next = click(1, active: a)
        _ = engine.prepare(next, current: { true })
        backend.focused[a] = 2
        next.releasedAt = 10.1
        expect(engine.complete(next, current: { true }) == .minimized)
        expect(backend.writes.first?.0 == 1)
    }
    func testNativeDockRestoreDoesNotImmediatelyReminimize() {
        let (backend, engine) = fixture()
        toggle(engine)
        var next = click(2, active: a)
        _ = engine.prepare(next, current: { true })
        backend.windows[1] = WindowState(minimized: false, canMinimize: true)
        next.releasedAt = 10.1
        expect(engine.complete(next, current: { true }) == .restored)
        expect(backend.writes.count == 1)
        expect(backend.raised == [1])
    }
    func testManualRestoreResumesFocusedWindowBehavior() {
        let (backend, engine) = fixture()
        toggle(engine)
        backend.windows[1] = WindowState(minimized: false, canMinimize: true)
        backend.focused[a] = 2
        expect(toggle(engine, 2) == .minimized)
        expect(backend.writes.last?.0 == 2)
    }
    func testDockReadFailurePreservesRememberedWindowsAndNextClickRecovers() {
        let (backend, engine) = fixture()
        toggle(engine)
        backend.hitFailure = true
        toggle(engine, 2)
        expect(engine.rememberedCount == 1)
        expect(backend.writes.count == 1)
        backend.hitFailure = false
        expect(toggle(engine, 3) == .restored)
    }
    func testTransientWindowReadFailureDoesNotEraseRestoreTarget() {
        let (backend, engine) = fixture()
        toggle(engine)
        backend.stateFailure = true
        toggle(engine, 2)
        expect(engine.rememberedCount == 1)
        backend.stateFailure = false
        expect(toggle(engine, 3) == .restored)
    }
    func testFailedWriteDoesNotInventRememberedMinimization() {
        let (backend, engine) = fixture()
        backend.writeFailure = true
        expect(toggle(engine) == .failed)
        expect(engine.rememberedCount == 0)
        backend.writeFailure = false
        expect(toggle(engine, 2) == .minimized)
    }
    func testClosedRememberedWindowFallsBackToCurrentFocusedWindow() {
        let (backend, engine) = fixture()
        toggle(engine)
        backend.windows.removeValue(forKey: 1)
        backend.focused[a] = 2
        expect(toggle(engine, 2) == .minimized)
        expect(backend.writes.last?.0 == 2)
    }
    func testFullscreenOrUnminimizableWindowAndNonAppDockItemAreSkipped() {
        let (backend, engine) = fixture()
        backend.windows[1] = WindowState(minimized: false, canMinimize: false)
        toggle(engine)
        expect(backend.writes.isEmpty)
        backend.hit = nil
        toggle(engine, 2)
        expect(backend.writes.isEmpty)
    }
    func testCancellationDuringSlowReadPreventsMutation() {
        let (backend, engine) = fixture()
        var current = true
        var next = click(1, active: a)
        _ = engine.prepare(next, current: { current })
        backend.onRead = { current = false }
        next.releasedAt = 10.1
        expect(engine.complete(next, current: { current }) == .cancelled)
        expect(backend.writes.isEmpty)
    }
    func testMovedOrChangedDockItemAtReleaseIsCancelled() {
        let (backend, engine) = fixture()
        var next = click(1, active: a)
        _ = engine.prepare(next, current: { true })
        backend.hit = b
        next.releasedAt = 10.1
        expect(engine.complete(next, current: { true }) == .cancelled)
        expect(backend.writes.isEmpty)
    }
    func testNoPreparedMouseDownNeverActsFromPostClickFocus() {
        let (backend, engine) = fixture()
        var next = click(1, active: a)
        next.releasedAt = 10.1
        expect(engine.complete(next, current: { true }) == .skipped)
        expect(backend.writes.isEmpty)
    }
    func testSlowPreflightCannotUseWindowStateReadAfterRelease() {
        let (backend, engine) = fixture()
        let mailbox = ClickMailbox()
        let down = click(mailbox.nextSequence(), active: a)
        _ = mailbox.offer(down)
        _ = mailbox.take()
        var up = down
        up.releasedAt = 10.1
        backend.onRead = { _ = mailbox.offer(up) }
        expect(engine.prepare(down, current: { mailbox.isCurrent(down, now: 10.11) }) == .cancelled)
        expect(engine.complete(up, current: { mailbox.isCurrent(up, now: 10.11) }) == .skipped)
        expect(backend.writes.isEmpty)
    }
    func testTerminationAndPIDReuseDoNotRestoreOldHandle() {
        let (backend, engine) = fixture()
        toggle(engine)
        let replacement = AppIdentity(pid: a.pid, launched: 2)
        backend.running = [replacement]
        backend.hit = replacement
        backend.focused[replacement] = 2
        expect(toggle(engine, 2, active: replacement) == .minimized)
        expect(backend.writes.last?.0 == 2)
    }
    func testEpochChangeForSleepPermissionLossOrDockRestartDropsOldHandles() {
        let (backend, engine) = fixture()
        toggle(engine)
        backend.focused[a] = 2
        expect(toggle(engine, 2, epoch: 1) == .minimized)
        expect(backend.writes.last?.0 == 2)
    }
    func testHideModeHidesAppWithoutMinimizingAnyWindow() {
        let (backend, engine) = fixture()
        expect(toggle(engine, mode: .hideShow) == .hidden)
        expect(backend.hidden == [a])
        expect(backend.writes.isEmpty)
        expect(backend.raised.isEmpty)
        expect(engine.rememberedCount == 0)
        expect(backend.windows.values.allSatisfy { !$0.minimized })
    }
    func testClickToShowHiddenAppStaysNativeEvenIfDockActivatesItBeforeRelease() {
        let (backend, engine) = fixture()
        expect(toggle(engine, mode: .hideShow) == .hidden)
        var show = click(2, active: b, mode: .hideShow)
        expect(engine.prepare(show, current: { true }) == .native)
        // The native Dock may unhide/activate A at release. Down was inactive,
        // so no hide plan exists and this must not immediately hide A again.
        show.releasedAt = 10.1
        expect(engine.complete(show, current: { true }) == .skipped)
        expect(backend.hidden == [a])
        expect(backend.writes.isEmpty)
    }
    func testHideModeLeavesIneligibleFullscreenAndNoWindowAppsNative() {
        let (backend, engine) = fixture()
        backend.windows[1] = WindowState(minimized: false, canMinimize: false)
        toggle(engine, mode: .hideShow)
        expect(backend.hidden.isEmpty)
        backend.focused[a] = nil
        toggle(engine, 2, mode: .hideShow)
        expect(backend.hidden.isEmpty)
        backend.hit = nil
        toggle(engine, 3, mode: .hideShow)
        expect(backend.hidden.isEmpty)
    }
    func testFullscreenTransitionBeforeReleasePreventsAppHiding() {
        let (backend, engine) = fixture()
        var next = click(1, active: a, mode: .hideShow)
        _ = engine.prepare(next, current: { true })
        backend.windows[1] = WindowState(minimized: false, canMinimize: false)
        next.releasedAt = 10.1
        expect(engine.complete(next, current: { true }) == .native)
        expect(backend.hidden.isEmpty)
    }
    func testSwitchingToHideModeClearsWindowOwnershipWithoutRestoringIt() {
        let (backend, engine) = fixture()
        expect(toggle(engine) == .minimized)
        backend.focused[a] = 2
        expect(toggle(engine, 2, mode: .hideShow) == .hidden)
        expect(engine.rememberedCount == 0)
        expect(backend.windows[1]?.minimized == true)
        expect(backend.writes.count == 1)
        expect(toggle(engine, 3, mode: .minimizeRestore) == .minimized)
        expect(backend.writes.last?.0 == 2)
    }
    func testReleaseCannotUsePreparedPlanForAnotherMode() {
        let (backend, engine) = fixture()
        let down = click(1, active: a, mode: .hideShow)
        _ = engine.prepare(down, current: { true })
        var differentMode = click(1, active: a, mode: .minimizeRestore)
        differentMode.releasedAt = 10.1
        expect(engine.complete(differentMode, current: { true }) == .skipped)
        expect(backend.hidden.isEmpty)
        expect(backend.writes.isEmpty)
    }
    func testFailedHideDoesNotAffectWindowStateAndNextClickCanRetry() {
        let (backend, engine) = fixture()
        backend.hideFailure = true
        expect(toggle(engine, mode: .hideShow) == .failed)
        expect(backend.hidden.isEmpty)
        expect(backend.writes.isEmpty)
        expect(engine.rememberedCount == 0)
        backend.hideFailure = false
        expect(toggle(engine, 2, mode: .hideShow) == .hidden)
    }
    func testHideModeDockReadFailureRecoversOnNextClick() {
        let (backend, engine) = fixture()
        backend.hitFailure = true
        toggle(engine, mode: .hideShow)
        expect(backend.hidden.isEmpty)
        backend.hitFailure = false
        expect(toggle(engine, 2, mode: .hideShow) == .hidden)
    }
    func testTerminationBeforeHideReleaseCannotHideReplacementProcess() {
        let (backend, engine) = fixture()
        var next = click(1, active: a, mode: .hideShow)
        _ = engine.prepare(next, current: { true })
        backend.running = [AppIdentity(pid: a.pid, launched: 2)]
        next.releasedAt = 10.1
        expect(engine.complete(next, current: { true }) == .skipped)
        expect(backend.hidden.isEmpty)
    }
    func testCancellationDuringReleaseReadPreventsHide() {
        let (backend, engine) = fixture()
        var next = click(1, active: a, mode: .hideShow)
        var current = true
        _ = engine.prepare(next, current: { current })
        backend.onRead = { current = false }
        next.releasedAt = 10.1
        expect(engine.complete(next, current: { current }) == .cancelled)
        expect(backend.hidden.isEmpty)
    }
    func testRapidHideClicksReplacePendingActionsAndExpiredHideIsDiscarded() {
        let (backend, engine) = fixture()
        let mailbox = ClickMailbox()
        var latest: Click!
        for _ in 0..<10_000 {
            let down = click(mailbox.nextSequence(), active: a, mode: .hideShow)
            _ = mailbox.offer(down)
            _ = mailbox.take()
            _ = engine.prepare(down, current: { mailbox.isCurrent(down, now: 10.05) })
            latest = down
            latest.releasedAt = 10.1
            _ = mailbox.offer(latest)
        }
        expect(mailbox.take() == latest)
        expect(engine.complete(latest, current: { mailbox.isCurrent(latest, now: 10.2) }) == .hidden)
        expect(backend.hidden == [a])
        expect(backend.writes.isEmpty)
        var expired = click(mailbox.nextSequence(), active: a, mode: .hideShow)
        _ = engine.prepare(expired, current: { mailbox.isCurrent(expired, now: 10.05) })
        expired.releasedAt = 10.1
        _ = mailbox.offer(expired)
        expect(engine.complete(expired, current: { mailbox.isCurrent(expired, now: 10.4) }) == .cancelled)
        expect(backend.hidden == [a])
    }
}
