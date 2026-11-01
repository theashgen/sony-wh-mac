# Menu bar popover and Notification Center widget — 0.3.0

The floating window has been replaced by a native `NSPopover` anchored below the headphones status item. Its transient behavior dismisses it on outside clicks; the icon toggles it. Controls use standard macOS typography, colors, segmented picker, sliders, switches, and EQ menu. Light/dark appearance follows the system. The persistent Bluetooth controller and action queue remain in the host application.

The separate WidgetKit extension supports small and medium widgets in Notification Center or on the desktop. The small layout shows battery and mode and opens the controls. Medium adds ANC, Ambient, and Off links routed through `sonycontrol://mode/<mode>`. `NSApplicationDelegate` validates these URLs and queues the selected mode, including on a cold app launch. Widget links open the host app; this is not an AppIntent implementation that guarantees controls execute without opening the app.

## Install and use

```sh
tools/install-app.sh
open "$HOME/Applications/Sony Control.app"
```

Quit the existing Sony Control instance before reopening an update. The install script copies only this application into the user's Applications folder and registers the extension. It removes the development copy's registration to avoid duplicate widgets.

Open Notification Center, select **Edit Widgets**, search for **Sony Headphones**, and add the preferred size. Placement is chosen in macOS's widget editor. The widget requires macOS 14+, and the host controller targets macOS 13+. This installation was verified on macOS 27 with the command-line Swift tools; full Xcode and an Apple Developer signing identity were not needed.

## Widget status and packaging

Ad hoc signing could not write an app-group container on this Mac. The final design instead exposes a read-only JSON snapshot on `127.0.0.1:52721/v1/status`. The listener binds only to IPv4 loopback, has bounded client counts, request size and lifetime, and rejects non-status paths and non-GET requests. It provides only battery, mode, connection state, and observation time. Bluetooth writes always go through the app's URL handler and its existing serial queue. The sandboxed extension has network-client access.

The app updates the in-memory snapshot on headset notifications and periodic refreshes. Reload requests are debounced and only sent when the displayed widget fields change. The widget asks for periodic timelines at 15-minute intervals. macOS controls actual refresh timing, so the widget can lag behind the menu bar controls. If the host is closed or unavailable, the widget prompts the user to open Sony Control rather than claiming a current connection.

The extension executable must enter through Foundation's `_NSExtensionMain`, which initializes the extension identity and invokes the Swift entry point. Using the ordinary executable entry point caused an ExtensionFoundation startup trap. The final build script sets the system entry point and embeds the extension Info.plist, then signs the extension before signing the host bundle. Both widget sizes subsequently rendered successfully through the macOS widget service.

## Verification and practical limits

- Release app and extension compiled; installed bundle passed deep/strict signature verification.
- Eight existing offline protocol checks passed: `research/evidence/native-protocol-checks.txt`.
- macOS registered one installed extension and successfully archived small and medium WidgetKit previews: `research/evidence/native-widget-success.log`.
- A sandboxed test app using the same status-reader source and network entitlement read the live headset state: `research/evidence/native-widget-network-check.txt`.
- Live status GET, invalid path, rejected POST, and fragmented HTTP header checks passed: `research/evidence/native-status-checks.txt`.
- The native popover's own SwiftUI view was captured and inspected: `research/evidence/native-popover.png`.
- Opening `sonycontrol://controls` through the installed application succeeded. Actual Notification Center placement and mode-link clicks were not automated. Outside-click behavior uses AppKit's native transient popover; physical mouse dismissal and both appearance modes were not separately tested.
- No mode-cycling hardware tests were repeated during this UI change, to avoid overriding the user's current settings. Prior transport verification is recorded in `2026-11-01_widget-update.md`.
