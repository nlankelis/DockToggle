# Manual verification checklist

All boxes below are **unchecked**. Basic permission recovery and use were observed/reported, as recorded in [validation](VALIDATION.md), but these scenarios have not been individually verified. Automated tests use a fake window backend; they cannot prove live Dock/AX behaviour. Record a pass/fail, app version, observed differences and date for each row. Do not treat an unchecked row as passed.

Test machine: MacBook Pro, M2 Pro, 32 GB RAM, macOS 26.5.2. Record the build signature/certificate and whether the installed app is debug or release. Keep other Dock-click utilities quit during testing, so each action has one owner. Record your original Dock settings before changing any manually for a test and restore them afterward.

## Setup and menu

- [ ] Build with `./scripts/build-app.sh` and run `./scripts/test.sh`; capture terminal results. Open the bundled app, not `.build/.../DockToggle`.
- [ ] With permissions absent, the menu shows the missing permissions and the listener waits. Native Dock interaction works normally; no automatic permission dialog appears.
- [ ] Select each permission row. Verify the explanation and correct Settings panel; grant both to the installed app, restart it if macOS requests that, then verify “Granted” and “Listener: Listening”.
- [ ] If the app is missing from a permission list, use its **+** button to add the running `DockToggle.app` manually. For the recommended install, use Command–Shift–G to reach `~/Applications`. Verify that adding/enabling the app and reopening it updates the menu's permission state.
- [ ] After replacing an ad-hoc build, verify whether previous grants still match. If switches are on but status remains Required, follow the README's scoped reset procedure, grant fresh access to the installed copy, and record its own menu/log status after reopening. Do not treat a CLI process's inherited permissions as the installed app's grants.
- [ ] Disable from the menu during activity. New custom operations stop, and remembered minimized windows remain available for normal Dock restoration. Re-enable and verify a new ordinary window can toggle.
- [ ] Set Launch at Login and inspect General → Login Items. If approval is required, verify the menu's mixed/awaiting state and Settings link. Log out/in (after saving work) to verify one menu bar instance starts. Turn Launch at Login off and verify it is removed.
- [ ] Open a second copy with the same bundle identifier. Verify there is one menu item/listener. Quit from the menu; verify the process and menu item disappear and clicks remain native.

## Ordinary windows and ownership

Select **Mode → Minimise / Restore Window** for the scenarios in this section.

- [ ] Inactive TextEdit or Terminal: click the app icon. It activates normally and no window is minimized. Click again while active: only the focused ordinary window minimizes. Click again: that same window restores.
- [ ] Two windows with different contents/titles: focus A, minimize it via the Dock, and confirm B stays visible. The next active-app click restores A, even if B is focused in between. No “minimize all” occurs.
- [ ] Manually restore A using the app's Window menu or minimized tile. Focus B; the next active-app click minimizes B rather than treating the externally restored A as owned.
- [ ] Close a remembered window or quit its app. A later click must not act on a dead window. Relaunch the app; new windows toggle normally.
- [ ] Minimize a window, activate another app, then click the first app. This inactive click remains native; a later active click follows the remembered/current window rules. Note which windows the native Dock restores.
- [ ] No open window, hidden app, minimized last window and native reopen behaviours: observe what the Dock itself does; no custom request should target an invented or unrelated window. Record any native extra window restoration/creation as a limitation.
- [ ] Try Finder, Safari and a third-party app. Record which AX providers support the feature. A provider that rejects minimization, lacks geometry, or cannot identify its Dock URL should retain native behaviour.

## Dock interactions and geometry

Repeat these checks in both modes where applicable.

- [ ] Plain icon click near each edge and centre: verify correct app identity, including similarly named apps. Never minimize another application's window.
- [ ] Drag an app icon to rearrange it; drag out and back; drag away; drag a file onto an icon. No custom minimization occurs, even if the pointer returns to its starting point.
- [ ] Command, Option, Control, Shift and Fn clicks, including a modifier pressed/released during the gesture, preserve native behaviour. Verify right clicks and long presses open the usual menu.
- [ ] Trash, Downloads/other stacks, pinned folders, documents, URLs, separators and minimized-window tiles remain native. No title-based accidental match occurs.
- [ ] Enable magnification manually and click at different magnification levels and changing positions. Repeat with automatic hiding, after moving an icon, and after adding/removing a recent app. Record skipped custom clicks and any wrong targets.
- [ ] Repeat with Dock left, bottom and right; two displays including negative-coordinate placement; different scaling; move the Dock between displays. No assumptions about icon order or fixed rectangles should appear.
- [ ] Toggle “Minimise windows into application icon” manually both ways. Verify which native Dock windows restore, and document if the passive/native race changes the experience. Restore the original setting.
- [ ] Compare Dock settings before/after launch, toggles, reconnect and quit. DockToggle must not change any of them.

## Fullscreen and system window modes

- [ ] Enter fullscreen in an ordinary supported app. Clicking its active Dock icon does not request minimization, exit fullscreen or change fullscreen state through DockToggle. Native Spaces navigation remains available.
- [ ] With one fullscreen window and another remembered minimized ordinary window, click the app's icon. Record native/AX behaviour and whether it changes the Space; this mixed case needs particular scrutiny.
- [ ] Test a display-covering borderless window, a maximized ordinary window, a modal dialog and a sheet. Full-display, modal and direct-sheet windows are skipped. Ordinary maximized windows should toggle unless their geometry also covers the entire display.
- [ ] Test Mission Control, app Exposé, Split View, multiple Spaces and Stage Manager on/off. Verify no unexpected fullscreen/minimize operations; record provider or native-Dock differences.

## Hide / Show mode

- [ ] Verify **Mode → Hide / Show App (all windows)** is selected when no mode preference exists. With two ordinary windows, click the active app's Dock icon. Both windows should hide rather than minimise, with no Scale/Genie minimise request from DockToggle.
- [ ] Click the same icon again while another app is active. The Dock shows the hidden app normally, and DockToggle must not immediately hide it again. Repeat after hiding via Command-H and after switching between several apps.
- [ ] Quit and reopen DockToggle after selecting each mode. Verify the selected mode is retained and menu checkmarks agree with actual behaviour.
- [ ] Switch modes while a gesture or pending operation exists. The pending operation must cancel. Switching must not itself hide, unhide, minimise or restore any app/window. Previously minimized windows stay minimized; hidden apps stay hidden until activated normally.
- [ ] In Hide / Show mode, verify focused fullscreen, display-covering, modal/sheet and no-window apps retain native behaviour. Specifically test an app with ordinary and fullscreen windows on different Spaces; app-wide hiding must be assessed separately from one-window minimization.
- [ ] Repeat rapid bursts, drag/modifier gestures, failed AX reads, permission changes, sleep/wake, Dock restart and display changes in Hide / Show mode. No stale hide should execute after the app is shown again.
- [ ] Restore any manually minimized windows before comparing animation behaviour. Check app-specific native reopen/restoration separately; Hide / Show does not promise that every macOS or app animation is absent.

## Responsiveness and recovery

- [ ] Compare switching between the same ordinary apps with DockToggle enabled, disabled and quit. Keep Dock settings, app windows and Spaces unchanged. Record each condition separately to investigate the reported delay; do not assume it originates in either DockToggle or macOS.
- [ ] Repeated clicks at ordinary speed: record successful custom actions versus attempts. Separately test very short clicks; unfinished preflight is deliberately skipped. A skipped custom action must never become a delayed minimize later.
- [ ] Make bursts at several rates on one icon and alternating icons, then stop. Superseded work may be skipped. No custom action sequence should replay after the burst. New AX requests must not start beyond the final click's 250 ms release deadline; native/AX animations already accepted can finish later.
- [ ] Repeat under normal CPU load and with an unresponsive test app (use a disposable test process, not unsaved work). The mouse/Dock should stay responsive; a failing AX read should affect only the current custom action. Other icons must recover on a subsequent ordinary click.
- [ ] Keep the menu open for several seconds and use the permission explanation dialog. Close it, return to an ordinary app and verify the dedicated listener still works.
- [ ] Debug watchdog check: quit the release build; build with `DOCKTOGGLE_CONFIGURATION=debug ./scripts/build-app.sh`, open it, and select **Test Watchdog Recovery**. That disables only DockToggle's tap. Within about one watchdog interval, verify the recovery count increases, the status returns to Listening, and new clicks work. This tests the watchdog route, not an actual OS timeout notification. Rebuild release afterward.
- [ ] Actual timeout notification, when reproduced with a development debugger or a test host: verify cancellation of the partial gesture, immediate re-enable attempt and fallback watchdog recovery. Do not stall the production callback as part of normal use. Record this separately from the debug watchdog check.
- [ ] Revoke Accessibility while running; verify status and custom operation pause. Regrant, restart if required, and verify recovery. Repeat separately for Input Monitoring. Never treat an alive process alone as listener health.
- [ ] Sleep/wake after minimizing a window and during a gesture. No held-down gesture should complete after wake. Verify new clicks work; old minimized windows restore normally through the Dock because ownership was cleared.
- [ ] Restart the Dock after saving your work (for example, `killall Dock` in Terminal). Verify a new Dock PID causes reconnection and new icon identification. Existing minimized windows stay under normal Dock control; new clicks should work after the Dock settles.
- [ ] Disconnect/reconnect a display or change resolution during a gesture. Outstanding work is invalidated, and new clicks resolve current geometry.
- [ ] Select **Reconnect Listener**. Within the next watchdog interval, verify a fresh tap and working new clicks. The window-memory reset must not itself minimize or restore a window.
- [ ] Run for at least one hour with intermittent use. Watch listener status/recovery count and the log stream for silent loss of functionality, repeated failures or an unexpected action backlog.

## Evidence to capture

Use the running app's menu and permission logs to confirm its grants. `--diagnose` is prompt-free but may inherit its launcher's permission context. Use `log stream --style compact --predicate 'subsystem == "dev.nojusl.DockToggle"'` for listener/outcome logs. For live latency and hit-rate measurement, use a screen recording or Instruments locally after obtaining any permissions those tools require. Record native animation time separately from callback/AX request time; no quantitative responsiveness claim is established by the unit tests.

| Build/date | Scenario | App + Dock settings | Pass/fail | Expected/observed difference | Evidence |
| --- | --- | --- | --- | --- | --- |
| | | | | | |
