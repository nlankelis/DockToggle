# DockToggle

A Swift macOS menu bar utility that adds click-to-hide and click-to-minimise behaviour to the existing Dock. Built independently with public Apple APIs as a personal portfolio project, with no third-party runtime dependencies.

**Status: experimental, v0.2.0.** Core tests pass and basic use has been reported working after permission setup. Intermittent delay and missed quick clicks are still being investigated. This is an early prototype; live macOS interaction coverage is incomplete.

## How it works

Choose a mode from DockToggle’s menu bar icon:

| | Hide / Show App — default | Minimise / Restore Window |
| --- | --- | --- |
| Click an inactive app | Normal Dock activation | Normal Dock activation |
| Click the active app | Hide its windows | Minimise the focused, eligible window |
| Click again | Normal Dock activation shows the app | Restore the remembered window when the app is active |
| Multiple windows | Hide the whole app | Remember one window per app |

Hide / Show avoids requesting the Dock’s Scale/Genie minimisation effect. It does **not** disable system animations, Spaces transitions or app-specific animations. Manually minimised windows still follow native restoration behaviour.

Custom actions ignore drags, modifier clicks, right clicks, long presses and non-app Dock items. Focused fullscreen, display-covering and modal/sheet windows are skipped. These guards are implemented; their behaviour across apps and Dock configurations still needs manual verification.

The menu includes enable/disable, mode selection, launch at login, permission status, listener status, reconnect and Quit. DockToggle opens **only in the menu bar**; it has no main window.

## Build and install

Requirements: macOS 13 or later and Swift 6 tooling, supplied by Xcode or compatible Apple Command Line Tools. Development was tested on an M2 Pro MacBook Pro with 32 GB RAM, macOS 26.5.2 and Swift 6.3.3. Intel and older macOS versions have not been verified.

```sh
git clone https://github.com/nlankelis/DockToggle.git
cd DockToggle
./scripts/test.sh
./scripts/build-app.sh
```

The build creates `build/DockToggle.app`. For a stable install location, quit any running DockToggle before copying or replacing it:

```sh
mkdir -p "$HOME/Applications"
ditto build/DockToggle.app "$HOME/Applications/DockToggle.app"
open "$HOME/Applications/DockToggle.app"
```

Grant permissions to **this installed copy**. Enable Launch at Login from its menu if desired; macOS may require approval under General → Login Items. Keep one installed copy and quit it before replacing its executable.

Local builds use ad-hoc signing with bundle identifier **`dev.nojusl.DockToggle`**. Changing an ad-hoc executable can invalidate its existing permissions even when Settings still shows its switches enabled. To use your own development certificate:

```sh
DOCKTOGGLE_SIGN_IDENTITY='Apple Development: Your Name (TEAMID)' ./scripts/build-app.sh
```

Distribution signing, notarisation and downloadable releases are not part of this version. Builds and compiler caches are ignored by Git.

## Permissions

Enable both permissions for the installed **DockToggle.app** under **System Settings → Privacy & Security**:

- **Accessibility:** identifies Dock icons and checks window eligibility; Minimise / Restore also controls the window’s minimised state.
- **Input Monitoring:** observes mouse clicks, dragging and modifier changes. It does not subscribe to typed-key events.

Click the corresponding permission row in DockToggle’s menu to request access and open Settings. If the app is missing from a list, use **+**, press **Command–Shift–G**, enter `~/Applications`, and select **DockToggle.app**. Select the app bundle, not the executable inside it.

Quit and reopen after granting Input Monitoring if requested. Before testing, the menu should show both permissions **Granted** and **Listener: Listening**. A running process alone does not establish that the listener works.

### Switches enabled, but status still says Required

A stale code-signing requirement after a rebuild caused this during development. First quit DockToggle and remove/re-add the installed copy in both permission lists. If it persists, reset **only DockToggle’s** entries using Apple’s [app-scoped permission reset](https://developer.apple.com/documentation/xcode/resetting-access-to-protected-resources-in-macos):

```sh
tccutil reset Accessibility dev.nojusl.DockToggle
tccutil reset ListenEvent dev.nojusl.DockToggle
```

These commands revoke this app’s saved grants. Reopen the installed copy, request and enable both permissions again, then quit/reopen. They do not grant access or affect other apps. Repeated reboots do not repair a mismatched signing requirement.

## Privacy and Dock preferences

DockToggle records no input history and has no telemetry or network client. Diagnostic logs contain permission states, listener health, AX error codes and action outcomes, without pointer coordinates, window titles or app paths. It requests no Screen Recording, Automation or administrator access.

Dock size, position, magnification, auto-hide, minimisation effect and “Minimise windows into application icon” preferences are preserved.

## Tests and diagnostics

```sh
./scripts/test.sh
./scripts/test.sh --sanitize=thread --scratch-path .build/thread-sanitizer
```

The recorded suite passes **34 tests and 118 assertions**, including window ownership, mode changes, cancellation, PID reuse, temporary failures, drag/modifier rejection, 10,000-click bursts and concurrent mailbox access. Thread Sanitizer reported no races in that test executable.

Tests use a fake backend and virtual time. They do not prove live Dock timing, fullscreen behaviour, listener recovery or another app’s Accessibility implementation. The dependency-free test runner is invoked through the script above, rather than `swift test`.

The [CI workflow](.github/workflows/ci.yml) is configured to run tests, Thread Sanitizer and bundle validation on a macOS runner. Its first hosted run is pending; CI does not grant system permissions or test live Dock clicks.

```sh
# Version and prompt-free diagnostics:
build/DockToggle.app/Contents/MacOS/DockToggle --version
build/DockToggle.app/Contents/MacOS/DockToggle --diagnose

# Listener, permission and action logs:
log stream --style compact --predicate 'subsystem == "dev.nojusl.DockToggle"'
```

Use the running app’s menu to confirm permissions: command-line diagnostics may inherit their launcher’s permission context. **Reconnect Listener** recreates the tap and clears temporary restore ownership.

## Known limitations

- **Responsiveness:** intermittent delay has been reported during app switching and repeated toggles. Its cause is not yet established. Very short clicks can be skipped because window checks must finish before mouse release. There is no intentional click-delay timer or replay queue.
- **Native Dock overlap:** DockToggle observes the normal click and acts after release. macOS can independently reopen or restore other windows; exact per-window behaviour cannot be guaranteed in every app.
- **Window state:** switching modes, disabling, reconnecting or a lifecycle reset clears restore ownership without restoring windows. Restore previously minimised windows normally; hidden apps show through normal activation.
- **Compatibility:** mixed fullscreen/ordinary windows, Spaces, Stage Manager, magnification, auto-hide and multiple displays need further verification. Unsupported or ambiguous Accessibility data causes a custom action to be skipped.
- **Recovery:** timeout handling, watchdog retries and sleep/wake/Dock-restart resets are implemented, but sustained reliability and real disruption recovery have not been fully tested.

## Demo

1. Install, grant permissions and confirm **Listener: Listening**.
2. Open two ordinary TextEdit or Terminal windows. In Hide / Show mode, click the active icon to hide the app; click again to show it.
3. Select Minimise / Restore. Focus one window, click its active icon to minimise it, then click again to restore it. Observe the other window and native Dock behaviour.
4. Try dragging and modifier clicks, then a rapid burst followed by stopping. Record skipped clicks, delay or unexpected actions.

Use the [manual verification checklist](docs/MANUAL-VERIFICATION.md) to record actual results. See [architecture](docs/ARCHITECTURE.md), [Apple API references](docs/APPLE-REFERENCES.md) and [validation evidence](docs/VALIDATION.md) for implementation details and remaining gaps.

## License

A license has not been selected for this repository yet.
