import AppKit
import ApplicationServices
import ServiceManagement
import OSLog
import DockToggleCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let runtime = RuntimeState()
    private lazy var worker = ClickWorker(runtime: runtime)
    private lazy var listener = MouseListener(runtime: runtime, worker: worker)
    private var statusItem: NSStatusItem!
    private var enabledItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var modeItem: NSMenuItem!
    private var hideModeItem: NSMenuItem!
    private var minimizeModeItem: NSMenuItem!
    private var accessibilityItem: NSMenuItem!
    private var inputItem: NSMenuItem!
    private var listenerItem: NSMenuItem!
    private var recoveryItem: NSMenuItem!
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var sleeping = false
    private var epoch: UInt64 = 0
    private var permissions: (ax: Bool, input: Bool) = (false, false)
    private var reportedPermissions = false
    private let permissionLogger = Logger(subsystem: "dev.nojusl.DockToggle", category: "Permissions")
    private var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "enabled") }
    }
    private var mode: ToggleMode {
        get { ToggleMode(rawValue: UserDefaults.standard.string(forKey: "toggleMode") ?? "") ?? .hideShow }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "toggleMode") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second local launch must not install a second mouse listener.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: {
               $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
           }) { NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "DockToggle")
        if statusItem.button?.image == nil { statusItem.button?.title = "DT" }
        let menu = NSMenu()
        menu.delegate = self
        let title = NSMenuItem(title: "DockToggle", action: nil, keyEquivalent: "")
        menu.addItem(title)
        enabledItem = add("Enable DockToggle", action: #selector(toggleEnabled), to: menu)
        modeItem = add("Mode", action: nil, to: menu)
        let modeMenu = NSMenu(title: "Mode")
        hideModeItem = add("Hide / Show App (all windows)", action: #selector(selectHideMode), to: modeMenu)
        minimizeModeItem = add("Minimise / Restore Window", action: #selector(selectMinimizeMode), to: modeMenu)
        modeItem.submenu = modeMenu
        loginItem = add("Launch at Login", action: #selector(toggleLogin), to: menu)
        menu.addItem(.separator())
        accessibilityItem = add("Accessibility", action: #selector(openAccessibility), to: menu)
        inputItem = add("Input Monitoring", action: #selector(openInputMonitoring), to: menu)
        add("Permissions & Privacy…", action: #selector(explainPermissions), to: menu)
        listenerItem = add("Starting", action: nil, to: menu)
        recoveryItem = add("Listener recoveries: 0", action: nil, to: menu)
        add("Reconnect Listener", action: #selector(reconnect), to: menu)
        #if DEBUG
        add("Test Watchdog Recovery", action: #selector(testWatchdog), to: menu)
        #endif
        menu.addItem(.separator())
        add("Quit DockToggle", action: #selector(quit), to: menu, key: "q")
        statusItem.menu = menu
        observeLifecycle()
        refreshEnvironment(forceReset: true)
        listener.start()
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshEnvironment()
        }
        RunLoop.main.add(timer!, forMode: .common)
        refreshMenu()
    }

    @discardableResult
    private func add(_ title: String, action: Selector?, to menu: NSMenu, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; menu.addItem(item); return item
    }

    private func identity(_ app: NSRunningApplication) -> AppIdentity? {
        guard let date = app.launchDate else { return nil }
        return AppIdentity(pid: app.processIdentifier, launched: date.timeIntervalSince1970)
    }

    private func refreshEnvironment(forceReset: Bool = false) {
        let ax = AXIsProcessTrusted()
        let input = CGPreflightListenEventAccess()
        let previous = runtime.snapshot()
        let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let dockPID = running.first { $0.bundleIdentifier == "com.apple.dock" }?.processIdentifier
        let changedPermissions = ax != permissions.ax || input != permissions.input
        permissions = (ax, input)
        if !reportedPermissions || changedPermissions {
            permissionLogger.info("Accessibility: \(ax ? "granted" : "required", privacy: .public); Input Monitoring: \(input ? "granted" : "required", privacy: .public)")
            reportedPermissions = true
        }
        if forceReset || changedPermissions || dockPID != previous.dockPID { epoch &+= 1 }
        let regularApps = running.filter { $0.activationPolicy == .regular }
        let apps = regularApps.compactMap { app -> RunningApp? in
            guard let identity = identity(app), let url = app.bundleURL else { return nil }
            return RunningApp(identity: identity, bundleURL: url.standardizedFileURL.resolvingSymlinksInPath())
        }
        let active = NSWorkspace.shared.frontmostApplication.flatMap(identity)
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        CGGetActiveDisplayList(UInt32(displayIDs.count), &displayIDs, &count)
        let environment = EnvironmentSnapshot(enabled: enabled && ax && input && !sleeping,
            mode: mode, epoch: epoch, active: active, dockPID: dockPID, applications: apps,
            displays: displayIDs.prefix(Int(count)).map(CGDisplayBounds))
        runtime.update(environment)
        if epoch != previous.epoch { worker.reset(epoch: epoch) }
        else if active != previous.active { worker.mailbox.invalidate() }
        refreshMenu()
    }

    private func observeLifecycle() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.refreshEnvironment()
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = true; self?.refreshEnvironment(forceReset: true)
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = false; self?.refreshEnvironment(forceReset: true)
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in
            self?.refreshEnvironment(forceReset: true)
        })
    }

    func menuWillOpen(_ menu: NSMenu) { refreshEnvironment() }
    private func refreshMenu() {
        guard statusItem != nil else { return }
        enabledItem.state = enabled ? .on : .off
        modeItem.title = mode == .hideShow ? "Mode: Hide / Show App" : "Mode: Minimise / Restore Window"
        hideModeItem.state = mode == .hideShow ? .on : .off
        minimizeModeItem.state = mode == .minimizeRestore ? .on : .off
        let loginStatus = SMAppService.mainApp.status
        loginItem.state = loginStatus == .enabled ? .on : (loginStatus == .requiresApproval ? .mixed : .off)
        loginItem.title = loginStatus == .requiresApproval ? "Launch at Login — Awaiting Approval" : "Launch at Login"
        accessibilityItem.title = "Accessibility: \(permissions.ax ? "Granted" : "Required")…"
        inputItem.title = "Input Monitoring: \(permissions.input ? "Granted" : "Required")…"
        let (status, recoveries) = runtime.listenerStatus()
        listenerItem.title = runtime.snapshot().enabled ? "Listener: \(status)" : (enabled ? "Waiting for Permissions" : "Disabled")
        recoveryItem.title = "Listener recoveries: \(recoveries)"
        statusItem.button?.appearsDisabled = !runtime.snapshot().enabled
        statusItem.button?.toolTip = "DockToggle — \(listenerItem.title)"
    }

    @objc private func toggleEnabled() { enabled.toggle(); refreshEnvironment(forceReset: true) }
    @objc private func selectHideMode() { selectMode(.hideShow) }
    @objc private func selectMinimizeMode() { selectMode(.minimizeRestore) }
    private func selectMode(_ value: ToggleMode) {
        guard mode != value else { return }
        mode = value
        refreshEnvironment(forceReset: true)
    }
    @objc private func reconnect() { refreshEnvironment(forceReset: true) }
    #if DEBUG
    @objc private func testWatchdog() { listener.testWatchdogRecovery() }
    #endif
    @objc private func toggleLogin() {
        do {
            switch SMAppService.mainApp.status {
            case .enabled: try SMAppService.mainApp.unregister()
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default: try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t change Launch at Login"
            alert.informativeText = "Keep DockToggle.app in a stable location, such as Applications, and try again.\n\n\(error.localizedDescription)"
            alert.runModal()
        }
        refreshMenu()
    }
    @objc private func openAccessibility() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        openSettings("Privacy_Accessibility")
    }
    @objc private func openInputMonitoring() {
        CGRequestListenEventAccess()
        openSettings("Privacy_ListenEvent")
    }
    private func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc private func explainPermissions() {
        let alert = NSAlert()
        alert.messageText = "DockToggle needs two permissions"
        alert.informativeText = "Accessibility identifies Dock application icons and checks window eligibility. Minimise / Restore controls one window. Hide / Show hides all windows of the active app; clicking its Dock icon again shows it normally. Input Monitoring observes mouse clicks and drags.\n\nGrant both to DockToggle in System Settings → Privacy & Security. You may need to quit and reopen after granting Input Monitoring.\n\nDockToggle doesn’t record input, read typed text, send data, or change Dock preferences. It monitors mouse events only; modifier changes cancel a click. Turn it off here at any time."
        alert.addButton(withTitle: "Done")
        alert.runModal()
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        sleeping = true
        refreshEnvironment(forceReset: true)
        timer?.invalidate()
        listener.stop()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
