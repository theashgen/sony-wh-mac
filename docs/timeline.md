# Investigation timeline — 2026-11-01

1. Located one authorized ADB phone and installed Sound Connect 13.3.0; identified the WH-CH720N connected to this Mac.
2. Pulled and hashed the base APK; decoded manifest/resources and Java code locally.
3. Identified the Sony TABLE_SET_2 RFCOMM UUID; local SDP cache resolved channel 18.
4. Initial Mac opens failed. Logs identified CoreBluetooth startup state; asynchronous open after run-loop initialization succeeded. Sound Connect was also force-stopped as a connection-contention check.
5. Read protocol version, supported functions, ANC capability/state, EQ capability/state, and battery from the headset.
6. First Off attempt using the NC selector was ignored; repeated readback detected the failure. Off with ASM selector succeeded. Ambient parameter updates were found to require active ASM mode.
7. Implemented delayed readback, intermediate ambient restoration, and independent sound/EQ restore attempts.
8. The hardware verification passed: Off, Ambient, ANC, voice focus, EQ Off, then exact sound/EQ restoration. Captures: `research/evidence/hardware-verification.txt`.
9. Packaged a local macOS menu bar app and added five offline protocol checks.
10. The first native menu startup exposed a main-dispatch callback issue; moving controller work to a run-loop timer fixed it. The packaged app then read live ANC, EQ, and battery state successfully and remained running.
11. User requested faster controls, bug fixes, a floating desktop widget, and an ANC-strength investigation. Replaced per-click synchronous connections with a persistent asynchronous controller and live notifications.
12. Eight offline regression checks and live async mode/voice/EQ/restoration checks passed. Measured warm sound updates were 629–764 ms including readback.
13. Native panel action-queue verification caught an immediate-reopen timeout. Added a reconnect-only cooldown; rapid control inputs, retained battery, restoration, and reconnect then passed. Native view rendering was visually inspected.

- 2026-11-01: Replaced the floating panel with a transient native menu bar popover. Built, installed, and registered a separate small/medium WidgetKit extension; corrected its Foundation extension entry point; verified native preview rendering, sandboxed live status access, bundle signing, and eight protocol checks. See `2026-11-01_menu-widget-update.md`.
