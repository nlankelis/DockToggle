import AppKit
import ApplicationServices
import DockToggleCore
import OSLog

/// AXUIElement uses CFEqual, preserving identity rather than window title or order.
struct AXWindow: Equatable {
    let element: AXUIElement
    static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.element, rhs.element) }
}

final class AccessibilityBackend: WindowBackend {
    private let runtime: RuntimeState
    private let system = AXUIElementCreateSystemWide()
    private let log = Logger(subsystem: "dev.nojusl.DockToggle", category: "Accessibility")
    private var lastErrorTime: TimeInterval = 0
    // Worker-confined guard, checked before every AX IPC, including the final write.
    var mayProceed: () -> Bool = { false }
    init(runtime: RuntimeState) {
        self.runtime = runtime
        AXUIElementSetMessagingTimeout(system, 0.05)
    }

    private func check() throws {
        guard mayProceed() else { throw BackendFailure.transient }
    }
    private func validate(_ error: AXError) throws {
        if error != .success, error != .attributeUnsupported, error != .noValue,
           monotonicTime() - lastErrorTime >= 1 {
            lastErrorTime = monotonicTime()
            log.info("AX operation returned error \(error.rawValue, privacy: .public)")
        }
        switch error {
        case .success: return
        case .invalidUIElement: throw BackendFailure.invalidWindow
        case .attributeUnsupported, .actionUnsupported, .notImplemented: throw BackendFailure.unsupported
        default: throw BackendFailure.transient
        }
    }
    private func value(_ element: AXUIElement, _ attribute: String) throws -> CFTypeRef? {
        try check()
        var result: CFTypeRef?
        try validate(AXUIElementCopyAttributeValue(element, attribute as CFString, &result))
        return result
    }
    private func optionalValue(_ element: AXUIElement, _ attribute: String) throws -> CFTypeRef? {
        do { return try value(element, attribute) }
        catch BackendFailure.unsupported { return nil }
    }
    private func element(_ object: CFTypeRef?) -> AXUIElement? {
        guard let object, CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
        return (object as! AXUIElement)
    }
    private func bool(_ element: AXUIElement, _ attribute: String) throws -> Bool {
        guard let result = try value(element, attribute), CFGetTypeID(result) == CFBooleanGetTypeID()
        else { throw BackendFailure.unsupported }
        return (result as! CFBoolean) == kCFBooleanTrue
    }
    private func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    func application(at point: Point) throws -> AppIdentity? {
        let environment = runtime.snapshot()
        guard let dockPID = environment.dockPID else { return nil }
        try check()
        var hit: AXUIElement?
        try validate(AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit))
        guard var item = hit else { return nil }
        var owner: pid_t = 0
        try validate(AXUIElementGetPid(item, &owner))
        guard owner == dockPID else { return nil }
        // A hit can be a child of the icon. Limit traversal; never scan the Dock tree.
        for _ in 0..<6 {
            let role = try value(item, kAXRoleAttribute) as? String
            if role == kAXDockItemRole {
                guard try value(item, kAXSubroleAttribute) as? String == kAXApplicationDockItemSubrole
                else { return nil }
                let raw = try value(item, kAXURLAttribute)
                let url: URL?
                if let rawURL = raw as? URL { url = rawURL }
                else if let string = raw as? String { url = URL(string: string) }
                else { url = nil }
                guard let url, url.isFileURL else { return nil }
                let bundleURL = canonical(url)
                let candidates = environment.applications.filter { $0.bundleURL == bundleURL }
                // Never guess by localized icon title or pick between duplicate instances.
                return candidates.count == 1 ? candidates[0].identity : nil
            }
            guard let parent = element(try value(item, kAXParentAttribute)) else { return nil }
            item = parent
        }
        return nil
    }

    func isRunning(_ app: AppIdentity) -> Bool {
        runtime.snapshot().applications.contains { $0.identity == app }
    }

    func focusedWindow(of app: AppIdentity) throws -> AXWindow? {
        let application = AXUIElementCreateApplication(app.pid)
        guard let window = element(try value(application, kAXFocusedWindowAttribute)) else { return nil }
        guard try value(window, kAXRoleAttribute) as? String == kAXWindowRole else { return nil }
        // Sheets and modal windows remain under the application's control.
        if (try optionalValue(window, kAXModalAttribute) as? Bool) == true { return nil }
        if let children = try optionalValue(window, kAXChildrenAttribute) as? [AXUIElement] {
            guard children.count <= 32 else { return nil }
            for child in children {
                if try value(child, kAXRoleAttribute) as? String == kAXSheetRole { return nil }
            }
        }
        return AXWindow(element: window)
    }

    func state(of window: AXWindow) throws -> WindowState {
        let minimized = try bool(window.element, kAXMinimizedAttribute)
        try check()
        var settable = DarwinBoolean(false)
        try validate(AXUIElementIsAttributeSettable(window.element, kAXMinimizedAttribute as CFString, &settable))
        if minimized { return WindowState(minimized: true, canMinimize: settable.boolValue) }
        if !settable.boolValue { return WindowState(minimized: false, canMinimize: false) }
        // AXFullScreen is an optional provider attribute (no SDK constant). The
        // documented geometry/settable checks below are the conservative fallback.
        let fullscreen = (try optionalValue(window.element, "AXFullScreen") as? Bool) == true
        let coveringDisplay = try coversDisplay(window.element)
        return WindowState(minimized: minimized, canMinimize: settable.boolValue && !fullscreen && !coveringDisplay)
    }

    private func coversDisplay(_ window: AXUIElement) throws -> Bool {
        // Read only for visible windows; unsupported geometry fails safely.
        guard let rawPosition = try value(window, kAXPositionAttribute),
              let rawSize = try value(window, kAXSizeAttribute),
              CFGetTypeID(rawPosition) == AXValueGetTypeID(), CFGetTypeID(rawSize) == AXValueGetTypeID()
        else { throw BackendFailure.unsupported }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &position),
              AXValueGetValue(rawSize as! AXValue, .cgSize, &size) else { throw BackendFailure.unsupported }
        return runtime.snapshot().displays.contains {
            abs(position.x - $0.minX) < 2 && abs(position.y - $0.minY) < 2 &&
            abs(size.width - $0.width) < 2 && abs(size.height - $0.height) < 2
        }
    }

    func setMinimized(_ minimized: Bool, window: AXWindow) throws {
        try check()
        try validate(AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString,
                                                 minimized ? kCFBooleanTrue : kCFBooleanFalse))
    }
    func raise(_ window: AXWindow) throws {
        try check()
        try validate(AXUIElementPerformAction(window.element, kAXRaiseAction as CFString))
    }
    func hide(_ app: AppIdentity) throws {
        try check()
        guard isRunning(app), let running = NSRunningApplication(processIdentifier: app.pid),
              !running.isTerminated, let launched = running.launchDate,
              launched.timeIntervalSince1970 == app.launched else { throw BackendFailure.invalidWindow }
        // Recheck immediately before sending the app-wide request. This does not
        // minimize any window or alter the user's Dock animation preferences.
        try check()
        guard running.hide() else { throw BackendFailure.transient }
    }
}
