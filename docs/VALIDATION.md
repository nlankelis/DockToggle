# Validation record — 5 October 2026

Environment actually inspected: arm64 macOS 26.5.2 (25F84), Apple Swift 6.3.3, macOS SDK 26.5, `/Library/Developer/CommandLineTools`. Full Xcode was not installed. No external packages were downloaded or competitor implementation inspected.

## Passed

- The executable compiled in debug and release configurations, including the debug-only watchdog test control.
- A local `.app` bundle was produced with `LSUIElement`, the original bundle identifier `dev.nojusl.DockToggle`, and an ad-hoc signature. `plutil -lint` passed and `codesign --verify --strict` succeeded.
- `scripts/test.sh --disable-sandbox`: **23 tests, 75 assertions, zero failures**. They use simulated windows, failures and virtual timestamps, plus real concurrent mailbox access.
- `scripts/test.sh --disable-sandbox --sanitize=thread --scratch-path .build/thread-sanitizer`: **23 tests, 75 assertions, zero failures; no Thread Sanitizer race diagnostics**.
- `build/DockToggle.app/Contents/MacOS/DockToggle --diagnose`: executable launched, read its bundle identifier and OS version, reported both Accessibility and Input Monitoring as **required**, and exited successfully without prompting or changing windows/Dock settings.
- `--version` reported `DockToggle 0.1.0 (dev.nojusl.DockToggle)`.

`--disable-sandbox` was needed for build subprocesses in the restricted workspace. Compiler caches were redirected into `.build`. The installed CLT lacked XCTest and its Swift Testing framework could not load a missing `lib_TestingInterop.dylib`. The final runner is a plain Swift executable with no dependency on those frameworks; use the supplied test script, not `swift test`.

## Still unverified

Neither app permission was granted. No live Dock clicks, AX window mutations, permission requests, login registration, menu interaction, real listener timeout, sleep/wake, Dock restart, fullscreen, magnification, auto-hide, Spaces or display changes were exercised. Actual icon hit rate, click latency, power usage and long-running reliability have not been measured. Thread Sanitizer covered the core test executable; it did not exercise the GUI/listener/AX worker against macOS.

The [manual checklist](MANUAL-VERIFICATION.md) remains unchecked. The debug recovery control compiles, but its runtime recovery behaviour still needs verification. The passive/native Dock overlap and deliberate skipped-click policy in the README are material first-version limitations, not established integration results.

All work remains local. No GitHub repository, remote, push, upload, login item or permission grant was created.

## Hide / Show update — version 0.2.0

Added an app-wide Hide / Show mode alongside the original per-window Minimise / Restore mode. The menu saves the mode selection; the default when unset is Hide / Show. Mode changes invalidate pending work and drop minimized-window ownership without mutating windows. The actual hiding request uses Apple's `NSRunningApplication.hide()`; normal Dock activation handles showing.

- Debug compilation passed, including the saved mode selector and existing debug recovery control.
- The normal test executable passed **34 tests, 118 assertions, zero failures**.
- The same suite passed with Thread Sanitizer: **34 tests, 118 assertions, zero failures**, with no sanitizer race diagnostics.
- Eleven added cases cover app-wide hiding without minimize writes, native showing without immediately re-hiding, fullscreen/no-window eligibility, fullscreen transitions, mode switches, mismatched release modes, failed hides, temporary Dock failures, PID reuse, cancellation and 10,000 rapidly superseded hide clicks plus release expiry.
- The release 0.2.0 app was rebuilt and passed `codesign --verify --strict` and bundle plist validation. The previous DockToggle instance was quit using `NSRunningApplication.terminate()`, and the rebuilt app was reopened through Launch Services; its new running process was confirmed.
- A prompt-free `--diagnose` check **outside the restricted build sandbox** reported `Mode: hideShow`, **Accessibility: granted**, and **Input Monitoring: granted**. The same check inside the build sandbox returned “required”. These CLI results do not establish the permissions of the separately launched menu bar app: its listener subsequently logged “Paused”. Check the app's own permission rows before testing live clicks. No permission changes were made by the agent.
- Added startup/transition-only permission diagnostics to the app's own unified log and rebuilt/reopened the release bundle. The normally launched app reported **Accessibility: required; Input Monitoring: required**, followed by **Paused**. The UI inspection attempt could not complete because Computer Use access initially was unavailable and retries timed out. No live Dock interaction was tested.

These tests simulate app hiding; they do not prove actual macOS hide timing or absence of every app-specific animation. Hide / Show affects all windows of the app. The new manual checklist includes native showing, both modes' persistence, permission changes and mixed fullscreen/ordinary windows. Live checks remain unverified.

## Permission identity recovery after restart

The user reported enabled permission switches and a Mac restart, with both app rows still Required. Scoped macOS TCC logs confirmed `Failed to match existing code requirement` for both `kTCCServiceAccessibility` and `kTCCServiceListenEvent`. The saved requirement was for cdhash `0b832ce8230d61b8cf01c253cf8604f59a098df6`; the current bundle's verified ad-hoc signature is `3aacba364dbea3221b7d4bb1a3523cfd4f4a623d`. This establishes a stale signing requirement, rather than a need for repeated restarts. No valid code-signing certificate identities were available.

The running app was quit. The existing, unchanged bundle was copied to `/Users/nojusl/Applications/DockToggle.app`; strict signature verification and an executable byte comparison passed. `tccutil reset Accessibility dev.nojusl.DockToggle` and `tccutil reset ListenEvent dev.nojusl.DockToggle` both succeeded. These resets remove only this app's stale approvals; no permission was granted by the agent. The installed copy was opened and revealed in Finder, and its running executable path was confirmed. Its fresh startup reports Required/Paused, as expected before the user grants access again. Live permission recognition, listener delivery and Dock interactions remain pending those grants. No code rebuild was performed during this recovery.

## First user interaction and timing investigation

After the user granted fresh permissions, the installed app logged Accessibility granted at 15:03:59 and Input Monitoring granted at 15:04:03, followed by Listening at 15:04:04 (Europe/London). The user reported that it worked, then reported intermittent delay both when switching apps and quickly toggling the same icon. This is a user-reported smoke check, not a completed manual verification checklist.

Logs show Accessibility errors -25201 (illegal argument) and -25204 (cannot complete), plus failed click outcomes. The current generic failed outcome can also include deliberate cancellation during an unfinished preflight, so these logs cannot establish how many actual API failures occurred or their cause. Source inspection confirms that preflight must finish before release, making short custom clicks liable to be skipped. It does not establish the cause of native app-switching delay.

A read-only `CGGetEventTapList` query confirmed the app's tap was enabled and passive. All reported callback latency fields were zero, so they provide no usable timing measurement. The GUI inspection could not complete because Computer Use timed out. An enable/disable comparison was requested from the user; its result and actual click latency remain pending. The installed executable was kept unchanged throughout this investigation to preserve its fresh grants.
