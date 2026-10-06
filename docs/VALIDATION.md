# Validation

This record separates automated checks, observed runtime status and user-reported behaviour. Implemented recovery paths and passing core tests do not establish production reliability.

## Development environment

Initial checks were performed on 5 October 2026 using an M2 Pro MacBook Pro with 32 GB RAM, arm64 macOS 26.5.2 (25F84), Apple Swift 6.3.3 and macOS SDK 26.5. Apple Command Line Tools were installed; full Xcode was not required. No third-party packages were downloaded and no competitor implementation was inspected.

## Automated checks — v0.2.0

| Check | Recorded result |
| --- | --- |
| Debug and release compilation | Passed, including the debug-only watchdog control |
| Core test executable | 34 tests, 118 assertions, zero failures |
| Core tests with Thread Sanitizer | Same suite passed; no race diagnostics |
| Bundle plist | `plutil -lint` passed |
| Local ad-hoc signature | `codesign --verify --strict` passed |
| Version command | Reported v0.2.0 and `dev.nojusl.DockToggle` |

On 6 October 2026, the core suite and Thread Sanitizer suite were rerun with the same results. Debug and release bundles were rebuilt locally while checking the new workflow's commands; the installed copy was not replaced. Workflow YAML syntax, shell script syntax and local Markdown links were also checked. This does not establish a hosted CI result.

The suite uses fake window operations, virtual timestamps and real concurrent mailbox access. It covers per-window ownership, native/inactive clicks, failed reads/writes, mode switches, fullscreen eligibility, lifecycle cancellation, PID reuse, completed gestures, 10,000-click bursts and concurrent access. It never sends live Dock/window requests.

The earlier v0.1 suite passed 23 tests and 75 assertions; v0.2 added eleven Hide / Show cases. The dependency-free executable runner avoids unavailable/incomplete test frameworks on the inspected Command Line Tools installation. Run it through `scripts/test.sh`, rather than `swift test`.

Local restricted builds used `--disable-sandbox` and caches inside `.build`. This option affects build subprocesses, not the app's macOS permissions. The installed executable was left unchanged during subsequent documentation and timing investigation.

## Permission recovery — observed on 5 October 2026

The app initially reported both permissions Required and its listener Paused, even when its Settings switches were enabled. Reopening the app and restarting the Mac did not resolve this.

Scoped macOS TCC logs reported `Failed to match existing code requirement` for both `kTCCServiceAccessibility` and `kTCCServiceListenEvent`. The saved ad-hoc signature requirement belonged to an older executable. This confirmed a signing mismatch; it was not resolved by permission polling or rebooting.

The unchanged build was installed at `~/Applications/DockToggle.app`. Its signature and executable byte comparison passed. The app's Accessibility and ListenEvent entries were reset using app-scoped `tccutil` commands. After fresh access was granted, the running app logged both permissions Granted and then Listening. A read-only `CGGetEventTapList` query also confirmed an enabled passive tap.

Command-line `--diagnose` results differed between sandboxed and native launch contexts. They do not establish the separately launched app's permission state; use its menu and its own permission logs.

## Live behaviour — reported smoke check

Basic use was reported working after fresh grants, followed by intermittent delay both when switching apps and quickly toggling the same icon. This is a limited smoke check, not a completed integration test or a latency measurement.

Logs contained AX errors -25201 (illegal argument), -25204 (cannot complete) and failed click outcomes. The generic failed outcome can also include cancellation during unfinished preflight, so those logs do not establish an API-failure count or the cause of app-switching delay. Source inspection confirms that clicks released before preflight finishes can lose their custom action.

The event tap's reported latency fields were all zero and provided no usable measurement. An enable/disable comparison was requested, but no result has been recorded. Actual click latency, hit rate, power use and long-running reliability remain unmeasured.

## Still to verify

The [manual checklist](MANUAL-VERIFICATION.md) remains the integration test plan. Its unchecked scenarios include exact-window ownership in real apps, rapid-click success rate, drag/modifier handling, fullscreen, magnification, auto-hide, multiple displays, Spaces, Stage Manager, launch at login, real listener timeout recovery, sleep/wake and Dock restarts.

The GitHub Actions workflow is configured for automated macOS tests and bundle builds. No hosted result is claimed until a run completes after the workflow is pushed. It does not test interactive Dock behaviour or grant system permissions.
