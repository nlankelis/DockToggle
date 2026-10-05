# DockToggle

An original Swift macOS menu bar utility that adds click-to-hide or click-to-minimise behaviour to the existing Dock. A focused, local-first portfolio project built independently with Apple's public event, Accessibility, AppKit and Service Management APIs. No third-party dependencies, private window APIs, injected code, AppleScript, replacement Dock, network access or Dock preference changes.

**Version 0.2 is a conservative prototype.** It adds a saved mode selector and defaults to Hide / Show App when no mode has been selected. It compiles on the development Mac and its state/rapid-click tests pass. Live Dock interactions, timing and recovery still need the [manual verification checklist](docs/MANUAL-VERIFICATION.md). Initial development validation ran without Accessibility or Input Monitoring. Do not present live interactions as verified yet.

## Behaviour

Choose **Mode → Hide / Show App (all windows)** or **Mode → Minimise / Restore Window** from the menu. The selection persists across launches. Hide / Show is the default for this update.

**Hide / Show App:** a plain click on the active app's icon sends `NSRunningApplication.hide()`, hiding its windows without minimising them into the Dock. The next click follows normal Dock activation/unhiding. Inactive app clicks always remain native, including that show click. This avoids issuing a Scale/Genie minimise/restore operation; it does not remove every animation an app or macOS might perform. It affects all the app's windows. Focused fullscreen/display-covering, modal, sheet, no-window or otherwise ineligible windows remain native. The same completed-click, identity, deadline and lifecycle guards apply.

**Minimise / Restore Window** retains the original per-window behaviour:

| Interaction | DockToggle behaviour |
| --- | --- |
| Click an inactive app | Let the Dock activate it normally. |
| Plain click on the active app | Minimise its focused, eligible window. |
| Next plain click while that app is active | Restore the particular window DockToggle minimised and request that it be raised. |
| Multiple windows | Remember one AX window identity per running app; never minimise every window. |
| Restore the remembered window manually | Resume toggling the currently focused window on the next click. |
| Drag, modifier click, right click, long press | Let the Dock handle it. |
| Trash, folders, documents, stacks, minimized-window tiles | Let the Dock handle them. |
| Uncertain icon identity, slow AX response, superseded click | Skip the custom action; preserve the native click. |

An inactive app always follows normal Dock activation, even if DockToggle remembers a window for it. In Minimise / Restore mode its next active-app click can restore that window. Window memory is temporary and is cleared on mode switches, permission transitions, sleep/wake, Dock restarts, display changes, reconnect, or enable/disable; those operations do not restore, unhide, hide or minimise windows themselves. Closed windows and terminated processes are pruned individually. A PID plus launch date protects against process ID reuse.

## Build and run

Development environment inspected: Apple Silicon arm64, macOS **26.5.2 (25F84)**, Apple Swift **6.3.3**, macOS SDK **26.5**, Apple Command Line Tools. The package targets macOS 13+; older systems and Intel have not been tested.

From this folder:

```sh
./scripts/build-app.sh
./scripts/test.sh
open build/DockToggle.app
```

The build produces `build/DockToggle.app`. Full Xcode is optional; use **File → Open → Package.swift** to work on the package in Xcode. Command Line Tools can be installed with `xcode-select --install` if needed. This package uses Swift 5 language mode with Swift 6 tooling; thread safety is explicit through locks, immutable snapshots and a serial worker.

For daily use, quit DockToggle, copy the built app to a stable location such as `~/Applications/DockToggle.app`, and open that copy. Enable **Launch at Login** from its menu. This uses `SMAppService.mainApp`, shows the system's current registration status and opens Login Items when approval is needed. Quit DockToggle before replacing a running build. Only one copy with the bundle identifier may run at a time.

The original, stable bundle identifier is **`dev.nojusl.DockToggle`**. Local builds default to ad-hoc code signing and verify the result. For a more stable permission identity across rebuilds, sign with your own Apple Development certificate:

```sh
DOCKTOGGLE_SIGN_IDENTITY='Apple Development: Your Name (TEAMID)' ./scripts/build-app.sh
```

A stable bundle identifier alone cannot preserve TCC grants after an ad-hoc executable changes. Rebuilt or relocated apps may need to be removed and added again in the permissions panels. Distribution signing/notarisation and universal builds are outside this first version. The app is not sandboxed; Accessibility control of other apps requires that design here.

## Permissions and privacy

In **System Settings → Privacy & Security**, grant the installed **DockToggle.app**:

1. **Accessibility** — reads the Dock item under the pointer and the active app's window attributes for both modes; in Minimise / Restore mode, writes one window's `AXMinimized` attribute and requests `AXRaise` on restoration. Hide / Show uses AppKit's app-wide hide request instead of writing a window's minimized state.
2. **Input Monitoring** — observes mouse down/up/drag and modifier-flag changes using a passive session event tap. No key down/up events are subscribed to.

If DockToggle is absent from either Settings list, add it manually with the **+** button. In the file chooser, press **Command–Shift–G**, enter the folder containing the running `DockToggle.app` (for the workspace build, this is `DockToggle/build` inside the project), select **DockToggle.app**, and click **Open**. Enable its switch, then quit and reopen DockToggle if requested. The workspace build is under a hidden `.codex` folder, so it may not appear when browsing Applications. Select the app bundle, not the executable inside `Contents/MacOS`. Apple's [Privacy & Security guide](https://support.apple.com/guide/mac-help/mchl211c911f/mac) documents manual addition to Input Monitoring.

The menu shows the mode selector, both permission states, enabled state, listener health, recovery count, Launch at Login and Quit. Its permission rows request the corresponding system permission and open Settings; **Permissions & Privacy…** explains why. Permission requests occur only when you select a permission row. The app waits quietly without both grants, including in Hide / Show mode. After granting Input Monitoring, macOS may require quitting and reopening the app. Grants are rechecked every second; the app cancels stale work on a permission transition.

If the switches are enabled but DockToggle still reports **Required** after reopening, an older ad-hoc build's saved code requirement can be the cause. This was confirmed during local development by macOS's `Failed to match existing code requirement` log for both Accessibility and ListenEvent. Quit DockToggle and reset only its entries with Apple's [app-scoped permission reset](https://developer.apple.com/documentation/xcode/resetting-access-to-protected-resources-in-macos):

```sh
tccutil reset Accessibility dev.nojusl.DockToggle
tccutil reset ListenEvent dev.nojusl.DockToggle
```

These commands revoke DockToggle's existing grants; they do not grant access or reset other apps. Open the installed copy, select each permission row to request access, and enable it in Settings. If adding manually, use **Command–Shift–G → `~/Applications`** and choose **DockToggle.app**. Quit and reopen after enabling Input Monitoring. Keep the executable unchanged during verification; changed ad-hoc builds require fresh grants. A reboot cannot repair a mismatched code requirement.

No Screen Recording, Automation, administrator access or helper daemon is requested. There is no input recording, telemetry, file log or network client. Unified logs contain lifecycle/outcome messages and permission states, without pointer coordinates, app paths or window titles. The saved app preferences are its own enabled state and mode; login registration is managed by macOS. Dock size, orientation, magnification, auto-hide and “Minimise windows into application icon” are never changed.

## Architecture

```text
AppKit menu / NSWorkspace notifications / permission checks
                  │ immutable environment snapshot
                  ▼
Dedicated mouse run loop — passive CGEvent tap + 1-second watchdog
                  │ small gesture record; no AX IPC
                  ▼
One-slot ClickMailbox — newest sequence and lifecycle epoch win
                  ▼
Serial Accessibility worker — bounded reads, guarded writes
                  ▼
ToggleEngine — one remembered AX window per application instance
```

- **Fast listener:** the callback reads local event fields and snapshots, updates a gesture and submits to a bounded mailbox. It never enumerates Dock icons, performs AX calls, waits on the worker, logs input or suppresses/reposts mouse events. A dedicated run loop avoids menu tracking/dialog stalls.
- **Completed clicks:** preflight begins on mouse down. A left drag event permanently disqualifies the gesture, even if the pointer returns; release must be within four screen points and 500 ms. Modifier changes and other buttons cancel it. No window operation happens on mouse down.
- **No replay queue:** only one worker drain and one pending record exist. A new down invalidates in-flight work immediately. The full window snapshot must be ready before release. Release actions expire after 250 ms, with a sequence/epoch/deadline check before every AX IPC. The worker also verifies the live frontmost process/launch time in case UI activation notifications lag. Rapid bursts can lose custom toggles rather than replaying them later; this is intentionally not an odd/even click counter.
- **Live identity:** `AXUIElementCopyElementAtPosition` uses the event's top-left screen coordinates at down and release. Check the owning Dock PID, bounded ancestor traversal, `AXDockItem` role, `AXApplicationDockItem` subrole, then the file URL against exactly one running app's canonical bundle URL. No localized-title guessing, icon-order assumptions or stored rectangles. This accommodates magnification, auto-hide, multiple displays and rearrangements when the Dock exposes its AX items.
- **Failure isolation:** there is no whole-Dock recognized-icon list to clear. A temporary AX error skips that gesture and preserves remembered windows for other apps. Each AX message has a 50 ms timeout. Invalid window handles are removed separately; failed minimize writes do not create remembered state.
- **Listener recovery:** timeout/user-input-disable notifications cancel the partial gesture and attempt to enable the tap immediately. A one-second watchdog checks the real port/enabled state, retries creation failures, enables disabled taps and recreates invalid ports. Lifecycle epochs recreate the tap. The menu reads real health, rather than treating a running process as proof of a working listener.
- **Window safety:** use the focused window, not the first element of the window list. Skip modal windows, direct sheets and windows with an unsettable minimized attribute. An optional provider `AXFullScreen` attribute is supplemented by documented window geometry; display-covering windows are conservatively skipped. Restore uses the original AX element (`CFEqual` identity), never a matching title. If native Dock restoration already occurred after preflight, the action is treated as restoration, avoiding an immediate re-minimise.
- **Hide / Show:** capture mode with mouse down, and check it again before action. Eligible active-app clicks call `NSRunningApplication.hide()` after rechecking the process ID/launch date and cancellation guard. No minimized-window state is written or remembered. Normal Dock activation handles showing the app. Switching mode increments the lifecycle epoch, invalidates pending actions and clears per-window ownership without changing the windows themselves.
- **Lifecycle:** workspace launch/activation/termination notifications refresh process snapshots, and a one-second poll is a fallback. Sleep/wake, permission changes, Dock PID changes and display changes invalidate outstanding gestures. Terminated app windows cannot be applied to a new process. Quit disables the environment and stops the run loop.

See [Apple API references](docs/APPLE-REFERENCES.md) and the small modules in `Sources/`.

## Tests and diagnostics

`./scripts/test.sh` builds and runs a dependency-free Swift test executable. It returns a nonzero exit status on failure. The installed CLT test frameworks were incomplete (XCTest unavailable; Swift Testing's runtime dependency missing), so the final test runner uses simple assertions and fake window operations. It does not need an external testing package or either permission. Register new cases in `Tests/DockToggleTests/main.swift`.

Coverage includes focused-window capture, inactive/native clicks, exact-window restoration, native/manual restoration, multiple windows, invalid/closed windows, failed writes, temporary Dock/window reads, full-screen eligibility, release identity changes, stale-action cancellation, preflight timing, permission/sleep epochs, termination/PID reuse, drag/modifier/long-press rejection, 10,000-click bursts and concurrent mailbox access. Hide / Show tests additionally cover app-wide requests without minimize writes, native showing without immediately re-hiding, failed hides, fullscreen eligibility changes, mode transitions, termination and stale/rapid hide actions. These are model/coordination tests, not proof of another app's AX implementation.

```sh
# Status check only; no requests or window changes:
build/DockToggle.app/Contents/MacOS/DockToggle --diagnose

# Version:
build/DockToggle.app/Contents/MacOS/DockToggle --version

# Live diagnostic stream; no window names or input contents:
log stream --style compact --predicate 'subsystem == "dev.nojusl.DockToggle"'
```

Use **Reconnect Listener** to invalidate outstanding work and recreate the tap at the next watchdog check. Reconnect clears temporary restore memory. Logs distinguish listener health, rate-limited AX error codes and window-action outcomes. A “Listening” status confirms an enabled tap; it does not prove that every app exposes suitable AX windows. After two unsuccessful watchdog enable attempts, the port is recreated. A debug build adds **Test Watchdog Recovery** to disable this app's tap deliberately; see the manual checklist.

The automated suite also passed with Thread Sanitizer:

```sh
./scripts/test.sh --sanitize=thread --scratch-path .build/thread-sanitizer
```

See [recorded validation](docs/VALIDATION.md) for exact results and remaining gaps.

Restricted development environments can pass `--disable-sandbox` to either script to avoid SwiftPM's nested build sandbox. Compiler/package caches are kept in `.build`. This option affects build subprocesses, not system permissions. There are no dependency downloads.

## Known limitations

- Hide / Show affects the whole app. Its next activation uses the native Dock, which can still restore manually minimized windows or invoke app-specific reopen behaviour with its own animations. A focused fullscreen window is skipped, but apps mixing ordinary and fullscreen windows in separate Spaces need particular verification because hiding is app-wide. Previously minimized windows remain minimized when switching modes; restore them normally first if you want a hide/show-only demo.

- Apple exposes event taps and Accessibility, but no public, atomic “replace this Dock click” API. This version observes the native click and acts after release. Native Dock activation/restoration/reopen remains in control and may also restore or create a different window. DockToggle only explicitly acts on its remembered window; it cannot guarantee that native Dock behaviour affects no other windows.
- AX preflight must finish before release. Very short clicks, slow apps, 50 ms timeouts, rapid bursts, or menu/main-thread load can cause a custom action to be skipped. No click delay or replay is introduced. Measure real hit rate and latency on the target machine before changing thresholds.
- Full-screen geometry, sheets, custom Accessibility providers, Stage Manager, Mission Control and Spaces need application-specific verification. A borderless window covering a display is also skipped. Unsupported/ambiguous icon URLs or windows fail safely; no title fallback is provided. Alias Dock icons or apps with multiple instances may therefore be native-only.
- AX success means a request was accepted, not that a window's animation has finished. A request already sent to another process cannot be revoked; that process may finish it later. Sequence checks prevent *new* stale requests from being issued, not the completion of an already accepted native/AX request.
- `AXFullScreen` is an optional provider attribute with no SDK constant and is not treated as a guaranteed Apple contract. Full-screen safety also checks documented geometry and writability. No private API is called.
- After a mode switch, disable, reconnect, sleep, permission changes, a Dock restart or a display change, previously minimized windows remain minimized and temporary ownership is discarded. Hidden apps remain hidden until normally activated. Use the Dock or the app's Window menu to restore windows normally.
- Menu permission status, actual event delivery, animation latency, login registration, Dock magnification/auto-hide and resilience to real system disruptions remain manual verification items. No runtime performance numbers or energy claims are made yet.

## Portfolio demo

1. Build, install and grant permissions. Run the tests and record the results in the verification checklist.
2. In **Hide / Show App** mode, open two ordinary TextEdit or Terminal windows and keep one focused. Click the active icon: both windows hide without a minimise request. Click again: normal Dock activation shows the app. Record actual transitions rather than claiming every animation is disabled.
3. Select **Minimise / Restore Window**. Open two ordinary TextEdit or Terminal windows; keep one focused. Place the app's icon in the Dock.
4. Show normal inactive-app activation. Click its now-active icon to minimise the focused window; click again to restore that specific window. Keep the other window visible to demonstrate ownership.
5. Demonstrate a Dock icon drag and a modifier click in both modes. Show that Trash/folder interactions remain native. Enable magnification and auto-hide manually, then repeat; restore your preferred settings afterward.
6. Make a rapid burst of clicks, stop, and show that DockToggle issues no delayed replay sequence. Explain that superseded/late custom actions may be skipped.
7. Show the menu's permission/health status and the test results. Describe the passive/native Dock limitation and label any unverified interactions honestly.

Nothing has been published or pushed. Create the GitHub repository yourself from this folder when ready; `.build/` and `build/` are ignored. Choose your own license before publishing.
