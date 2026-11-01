> Superseded UI: version 0.3 uses a menu bar popover and adds a separate Notification Center widget. See [the 0.3 update](2026-11-01_menu-widget-update.md).

# Floating widget and responsiveness update

Date: 2026-11-01. Scope remains [the user's Mac, WH-CH720N, and installed Sound Connect](scope.md). This is an interoperability/UI update, not a vulnerability finding.

## Changes

The user reported slow controls, ambient behavior bugs, and a changing battery indicator, and selected a floating desktop panel. Version 0.2 replaces the menu-only UI with a native SwiftUI panel hosted in an AppKit floating window. Its pin button toggles staying above other windows; the menu bar icon shows/hides the panel. Right-click exposes reconnect, control disconnect, and quit.

The old implementation reopened the control socket, waited one second, repeated initialization, and fetched several settings for every click. Version 0.2 keeps the socket open and uses async delegate-driven request continuations, cached confirmed state, and live Sony notifications. Normal control changes skip connection/setup and unrelated battery/EQ reads. Fallback readback still confirms writes when notifications are delayed. An idle refresh runs every 45 seconds.

The battery no longer becomes an ellipsis/spinner during an operation. Connection activity has its own label/progress indicator. The last known battery is retained across disconnects. Incoming external setting notifications update confirmed state.

Rapid input now queues and coalesces unsent changes of the same control instead of silently dropping clicks while busy. Pending mode/voice/EQ choices remain visible until completion. The slider commits on release and its in-flight value is protected from older state notifications. Errors appear inline. ANC/Off transitions preserve the saved ambient level and voice mode; setting EQ waits for confirmed state rather than assuming the first reply must be current.

Disconnect/reconnect uses a one-second closing cooldown because the macOS stack timed out when reopening the same RFCOMM channel 21 ms after closing it. The cooldown does not apply to ordinary clicks on the persistent connection. Dropped connections trigger backoff from 2 to 30 seconds; explicit control disconnect disables automatic reconnect.

## Evidence → finding → implementation

| Evidence | Observation | Finding and implementation |
|---|---|---|
| `Sources/SonyControl/MenuBar.swift` from the first version; prior report | Every click created a new Headphones instance; busy inputs returned without queuing; battery title became an ellipsis | F-W1, validated code cause: move client lifetime to `ControlModel`, queue input, keep battery presentation independent |
| `research/evidence/widget-hardware.txt` | Async controller verified Off in 764 ms, Ambient in 629 ms, ANC in 677 ms, then voice/EQ and original-state restoration | F-W2, validated on this device: persistent async controller supports confirmed mode updates in roughly 0.6–0.8 seconds in the measured run |
| `research/evidence/widget-tests.log` | Eight offline regression checks pass | Parser capture/corruption checks plus preservation of ambient voice/level, correct Off selector, and rejection of invalid levels |
| `research/evidence/widget-queue-check.txt` | Rapid mode/level/voice inputs, retained battery, exact restoration, and reconnect pass | F-W3, validated action queue: shared methods used by the panel settle to the latest requested setting |
| `research/evidence/widget.png` | Rendered native panel was visually inspected | Layout checked for mode buttons, ambient slider, voice focus, EQ, battery, and status/footer |
| `research/evidence/widget-app-build.log` | Release app built and ad hoc signed | Version 0.2 delivery at `.build/Sony Control.app` |

Hardware evidence is client packet logging and readback on the authorized headset, not an over-the-air capture. The widget check invokes the panel's action queue programmatically; it is not an automated mouse-click test. The image was rendered from the app's own native view after `screencapture` could not capture the window; no additional screen-recording access was required.

## ANC-strength conclusion

Evidence: the previously captured feature list advertises function `0x6b`; its `NCASM` inquiry type is `0x17` (`MODE_NC_ASM_DUAL_NC_MODE_SWITCH_AND_ASM_SEAMLESS`). In `sn0/x.java` and `un0/b.java`, the capability describes ambient modes and their level ranges. The live reply `61 17 02 00 01 14 01 01 01 14 01` describes normal/voice ambient levels 1–20. `sn0/c1.java` and `un0/f.java` serialize total effect, NC/ASM mode, ambient voice mode, and ambient level, without an ANC-strength field.

F-W4: no supported ANC-boost control was identified for this WH-CH720N, confidence high within the advertised/app-supported command surface. The 1–20 control adjusts ambient passthrough. `NcValue` contains single/dual/auto choices used by other protocol variants, but this headset's advertised type does not expose those as a strength slider. No firmware patch or out-of-range command was attempted. This finding does not prove that undocumented hardware/firmware paths cannot exist.

## Reproduce

Close the widget's control connection before running CLI checks:

```sh
swift build
swift run --skip-build ProtocolChecks
swift run --skip-build sony-control verify --verbose
```

For the native panel/action-queue check, use one instance:

```sh
SONY_WIDGET_CHECK=1 SONY_WIDGET_CAPTURE="$PWD/.build/widget-check.png" swift run sony-control menu
```

This check temporarily changes sound settings and restores the snapshot before checking disconnect/reconnect. It leaves the panel running. Keep the headset connected during verification. Build the normal app with `tools/build-app.sh`, then open `.build/Sony Control.app`.

Limitations: macOS-only, one exactly named WH-CH720N, firmware 1.1.4 tested. No actual radio-drop/power-cycle test was performed in this update; the release/reconnect path was exercised. Connection-loss errors remain bounded by transport timeouts, and process termination during a setting change can prevent restoration. Preset availability is based on the previously captured capability list; not every preset was individually selected.
