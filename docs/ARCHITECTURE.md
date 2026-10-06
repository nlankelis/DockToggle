# Architecture

DockToggle observes Dock clicks using public Apple APIs. Window work runs outside the mouse-event callback. The design prioritises cancellation and bounded work; actual click latency and hit rate remain under investigation.

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

See [Apple API references](APPLE-REFERENCES.md) and the modules in `../Sources/`.

## Native Dock overlap

The listener is passive. Dock activation, reopening and window restoration continue while DockToggle performs its own checks. There is no public, atomic API to replace the Dock's app-icon click. Native behaviour can therefore restore or create windows independently of DockToggle's remembered target.

A request accepted by another process may finish after a newer click invalidates pending work. Cancellation prevents new stale requests; it cannot revoke a request already sent. Very short clicks may finish before preflight completes and retain only native behaviour.

## Source map

| File | Responsibility |
| --- | --- |
| `Sources/DockToggle/AppDelegate.swift` | Menu, saved settings, permissions and workspace lifecycle |
| `Sources/DockToggle/RuntimeState.swift` | Locked environment and listener snapshots |
| `Sources/DockToggle/MouseListener.swift` | Dedicated run loop, passive event tap and watchdog |
| `Sources/DockToggle/ClickWorker.swift` | Serial worker and action guards |
| `Sources/DockToggle/AccessibilityBackend.swift` | Live Dock identity and AppKit/AX window requests |
| `Sources/DockToggleCore/ClickPipeline.swift` | Gesture recognition and bounded mailbox |
| `Sources/DockToggleCore/ToggleEngine.swift` | Mode transitions and per-app window ownership |

See [validation](VALIDATION.md) for what has actually been exercised, and the [manual checklist](MANUAL-VERIFICATION.md) for remaining integration checks.
