import Foundation
import CoreGraphics
import DockToggleCore
import OSLog

/// A dedicated run loop keeps menu tracking and permission dialogs away from the
/// event callback. The callback never does AX IPC, app enumeration or logging.
final class MouseListener {
    private let runtime: RuntimeState
    private let worker: ClickWorker
    private let log = Logger(subsystem: "dev.nojusl.DockToggle", category: "Listener")
    private var thread: Thread?
    private let loopLock = NSLock()
    private var loop: CFRunLoop?
    private var stopping = false
    // Everything below is confined to the listener thread.
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var recognizer = ClickRecognizer()
    private var lastEpoch: UInt64?
    private var lastStatus = ""
    private var reenableAttempts = 0

    init(runtime: RuntimeState, worker: ClickWorker) { self.runtime = runtime; self.worker = worker }
    func start() {
        let thread = Thread { [weak self] in self?.run() }
        thread.name = "DockToggle mouse listener"
        self.thread = thread
        thread.start()
    }
    func stop() {
        loopLock.lock()
        stopping = true
        let currentLoop = loop
        loopLock.unlock()
        if let currentLoop { CFRunLoopStop(currentLoop); CFRunLoopWakeUp(currentLoop) }
    }
    #if DEBUG
    /// Deliberately disables only this app's tap, for the manual watchdog check.
    func testWatchdogRecovery() {
        loopLock.lock(); let currentLoop = loop; loopLock.unlock()
        guard let currentLoop else { return }
        CFRunLoopPerformBlock(currentLoop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
            guard let self, let tap = self.tap else { return }
            self.recognizer.cancel(); self.worker.mailbox.invalidate()
            CGEvent.tapEnable(tap: tap, enable: false)
            self.status("Disabled for watchdog test")
        }
        CFRunLoopWakeUp(currentLoop)
    }
    #endif
    private func run() {
        let currentLoop = CFRunLoopGetCurrent()!
        loopLock.lock()
        loop = currentLoop
        let shouldStop = stopping
        loopLock.unlock()
        guard !shouldStop else { return }
        let watchdog = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.reconcile() }
        RunLoop.current.add(watchdog, forMode: .common)
        reconcile()
        CFRunLoopRun()
        watchdog.invalidate()
        destroyTap()
        loopLock.lock(); loop = nil; loopLock.unlock()
    }
    private func status(_ text: String, recovered: Bool = false) {
        runtime.setListener(text, recovered: recovered)
        if text != lastStatus || recovered {
            log.info("\(text, privacy: .public)")
            lastStatus = text
        }
    }
    private func destroyTap() {
        recognizer.cancel()
        reenableAttempts = 0
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        tap = nil; source = nil
    }
    private func reconcile() {
        let environment = runtime.snapshot()
        if lastEpoch != environment.epoch {
            destroyTap()
            lastEpoch = environment.epoch
        }
        guard environment.enabled else {
            if tap != nil { destroyTap() }
            status("Paused")
            return
        }
        if let tap, !CFMachPortIsValid(tap) { destroyTap() }
        if let tap {
            if CGEvent.tapIsEnabled(tap: tap) { reenableAttempts = 0; return }
            recognizer.cancel(); worker.mailbox.invalidate()
            reenableAttempts += 1
            if reenableAttempts <= 2 {
                CGEvent.tapEnable(tap: tap, enable: true)
                status(CGEvent.tapIsEnabled(tap: tap) ? "Listening" : "Retrying listener", recovered: true)
                return
            }
            // Do not keep trying to revive the same broken port indefinitely.
            destroyTap()
            status("Recreating listener", recovered: true)
        }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                   .rightMouseDown, .otherMouseDown, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                             options: .listenOnly, eventsOfInterest: mask,
                                             callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let listener = Unmanaged<MouseListener>.fromOpaque(context).takeUnretainedValue()
            listener.receive(type, event: event)
            return Unmanaged.passUnretained(event)
        }, userInfo: context),
              let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            status("Listener unavailable — check permissions")
            return // The watchdog retries; there is no terminal silently-dead state.
        }
        tap = newTap; source = newSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        status(CGEvent.tapIsEnabled(tap: newTap) ? "Listening" : "Retrying listener")
    }

    private func receive(_ type: CGEventType, event: CGEvent) {
        let environment = runtime.snapshot()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            recognizer.cancel(); worker.mailbox.invalidate()
            if environment.enabled, let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                runtime.setListener(CGEvent.tapIsEnabled(tap: tap) ? "Listening" : "Retrying listener", recovered: true)
            }
            return
        }
        guard environment.enabled else { recognizer.cancel(); return }
        let relevantFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift,
                                          .maskSecondaryFn]
        let modified = !event.flags.intersection(relevantFlags).isEmpty
        let point = Point(x: event.location.x, y: event.location.y)
        let now = monotonicTime()
        switch type {
        case .leftMouseDown:
            let sequence = worker.mailbox.nextSequence()
            let click = Click(sequence: sequence, epoch: environment.epoch, point: point,
                              activeApp: environment.active, startedAt: now, mode: environment.mode)
            if let start = recognizer.begin(click, modified: modified) { worker.submit(start) }
        case .leftMouseUp:
            if let click = recognizer.finish(at: point, time: now, modified: modified) { worker.submit(click) }
            else { worker.mailbox.invalidate() }
        case .leftMouseDragged, .rightMouseDown, .otherMouseDown:
            recognizer.cancel(); worker.mailbox.invalidate()
        case .flagsChanged:
            if modified { recognizer.cancel(); worker.mailbox.invalidate() }
        default: break
        }
    }
}
