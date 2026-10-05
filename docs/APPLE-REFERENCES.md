# Apple API references

The implementation was developed independently using the local Apple SDK headers and these Apple documentation pages. No competitor source or implementation was inspected.

- [CGEvent and event taps](https://developer.apple.com/documentation/coregraphics/cgevent): passive observation, session-level taps and enabled-state checks.
- [CGEvent.tapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)): run-loop installation, options and creation failure.
- [CGEventType](https://developer.apple.com/documentation/coregraphics/cgeventtype): `tapDisabledByTimeout` and `tapDisabledByUserInput`.
- [CGRequestListenEventAccess](https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess()): explicit Input Monitoring request; the matching preflight function is declared in `CGEvent.h`.
- [AXUIElementSetMessagingTimeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout): short, process-wide AX messaging timeout using the system-wide element; also documents top-left hit-test coordinates and AX value/action APIs.
- [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions): explicit asynchronous Accessibility prompting and non-prompting trust checks.
- [kAXMinimizedAttribute](https://developer.apple.com/documentation/applicationservices/kaxminimizedattribute): the documented window minimized state.
- [SMAppService.mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp): register the app itself for launch at login.
- [NSRunningApplication.hide](https://developer.apple.com/documentation/appkit/nsrunningapplication/hide()): app-wide hiding without minimising windows. The SDK notes that success means the request was sent. The live process ID/launch time is checked before the call.
- [Hide or minimise windows](https://support.apple.com/en-hk/guide/mac-help/mchlb7beb9af/mac): normal Dock activation unhides an app. Hide / Show mode leaves the show click native.

Additional local SDK references: `AXRoleConstants.h` (`kAXDockItemRole`, `kAXApplicationDockItemSubrole`), `AXAttributeConstants.h` (URL, focused window, modal, children, position and size), `AXActionConstants.h` (`kAXRaiseAction`), and `AXUIElement.h` (error handling and attribute writability).

The use of live Dock AX role/subrole/URL data is a design inference from the public Accessibility API, not a guarantee that every future Dock exposes an identical hierarchy. Likewise, `AXFullScreen` is a provider attribute read via the public AX API, not a documented SDK constant. The implementation has no private WindowServer calls or private Dock hooks.
