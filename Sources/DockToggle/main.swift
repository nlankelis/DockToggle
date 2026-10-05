import AppKit
import ApplicationServices

if CommandLine.arguments.contains("--version") {
    print("DockToggle 0.2.0 (dev.nojusl.DockToggle)")
    exit(0)
}
if CommandLine.arguments.contains("--diagnose") {
    print("DockToggle 0.2.0")
    let mode = UserDefaults.standard.string(forKey: "toggleMode") ?? "hideShow"
    print("Mode: \(mode)")
    print("Bundle: \(Bundle.main.bundleIdentifier ?? "unbundled; use build/DockToggle.app")")
    print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    print("Accessibility: \(AXIsProcessTrusted() ? "granted" : "required")")
    print("Input Monitoring: \(CGPreflightListenEventAccess() ? "granted" : "required")")
    print("No permission requests or Dock/window changes made.")
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
