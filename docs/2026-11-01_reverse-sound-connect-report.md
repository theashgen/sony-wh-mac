# Sound Connect and WH-CH720N reverse engineering report

Implementation note: this report records version 0.1. See [the widget update](2026-11-01_widget-update.md) for version 0.2, persistent connections, notifications, and current validation.

Date: 2026-11-01. Report type: interoperability research; flavor: null.

## Result

Sound Connect's headset controls can be reproduced directly from this Mac over Bluetooth Classic RFCOMM. An independent Swift client and native menu bar app now support ANC, Off, ambient level 1–20, voice focus, saved EQ selection, and battery status. Live verification exercised the main modes, voice focus, and EQ Off, then restored the exact starting sound and EQ parameters. No phone relay, app-account login, root access, app patch, or firmware modification was needed. Support is scoped to this WH-CH720N and firmware; additional advertised functions remain unimplemented.

## Scope and sample

See [scope](scope.md) and [investigation timeline](timeline.md).

| Attribute | Observed value |
|---|---|
| Package/version | `com.sony.songpal.mdr`, 13.3.0, code 130305109 |
| APK | Installed base APK, 104651007 bytes |
| SHA-256 | `58837826f5f145cd0ad9689a298d2bfe9702f4d51d6d4e67d41440175ec0892c` |
| Application | `com.sony.songpal.mdr.vim.MdrApplication` |
| Launcher | `com.sony.songpal.mdr.vim.activity.MdrMainActivity` |
| Headphones | WH-CH720N, firmware 1.1.4 reported by macOS |
| Host | Apple Silicon macOS 27, Swift 6.4 |
| Static tools | ADB, JADX 1.5.6, apktool 3.0.3, Homebrew OpenJDK |

The base APK contains six DEX files. The critical Bluetooth-control logic is in Java; the separate native ABI split was not pulled or analyzed. Login, TLS, root detection, and unrelated cloud features were outside the investigation. No hooks or patches were applied. JADX reported 278 errors elsewhere in the app, so the result does not imply complete decompilation.

## Evidence

All observations are from the user's authorized local devices. Packet captures below are verbose client logs, not over-the-air Bluetooth captures. Paths are relative to the project root.

| ID | Source type and source reference | Observation | Reproduce |
|---|---|---|---|
| E-001 | File: `research/evidence/apk.sha256` and `apk-contents.txt` | APK identity and DEX inventory | `shasum -a 256 research/apk/sound-connect-13.3.0.apk`; `unzip -l research/apk/sound-connect-13.3.0.apk` |
| E-imports | File: `research/evidence/static-findings.md` | Android BluetoothSocket/stream APIs implement the control transport; Java protocol serializers identified | `tools/extract-app.sh`, then inspect the cited classes in `research/jadx/sources` |
| E-002 | Command output: `research/evidence/mac-services.txt` | TABLE_SET_2 UUID resolves to RFCOMM 18 on this headset | `swift tools/probe.swift` |
| E-003 | Command output: `research/evidence/protocol-query.txt` | Real protocol reply `01 00 03 00 10 02 00 00` | `swift run sony-control status --verbose` issues the same query |
| E-004 | Command output: `research/evidence/features-discovery.txt` | Live ANC capability, battery, EQ capability and state | `swift run sony-control status --verbose`; capability queries documented below |
| E-005 | Command output: `research/evidence/hardware-verification.txt` | Mode and EQ changes plus exact original sound/EQ restoration | `swift run sony-control verify --verbose` (temporarily changes settings) |
| E-006 | Command output: `research/evidence/tests.log` | Five offline checks passed | `swift run ProtocolChecks` |
| E-008 | Command output: `research/evidence/menu-launch.txt` | Packaged menu app read live battery, ANC, and EQ on startup | Run the packaged app executable or open the app |
| E-007 | Command output: `research/evidence/app-build.log` | Release app built and locally ad hoc signed | `tools/build-app.sh` |

The APK hash is a fixity anchor for the analyzed sample. Other evidence is local session output; it is not independently signed or certified. Re-extraction against a newer installed app will not reproduce the old APK hash.

## Findings and implementation paths

### F-001: direct Mac transport is available

- Category: reverse_algo; severity: n/a_re; status: validated; confidence: high.
- Evidence: E-imports, E-002, E-003.
- Location: `lm0/i.java`, `om0/d.java`, `ep0/c.java`; implementation `Sources/SonyControl/BluetoothLink.swift`.
- Finding: Sony's TABLE_SET_2 service UUID is `956C7B26-D49A-4BA8-B03F-B17D393CB6E2`. The observed RFCOMM channel was 18, but clients should resolve the UUID instead of hardcoding that channel.
- Path P-001: discover paired WH-CH720N → resolve UUID → asynchronously open RFCOMM → exchange Sony frames. Implemented and verified on this Mac. A short run-loop startup allowance avoids the observed CoreBluetooth powered-state race. This delay is a compatibility workaround, not a guarantee for every macOS release.

### F-002: sound controls require state-aware writes

- Category: reverse_algo; severity: n/a_re; status: validated; confidence: high for this firmware.
- Evidence: E-imports, E-004, E-005; initial attempts in `research/evidence/off-check.txt` and `ambient-check.txt`.
- Location: `sn0/c1.java`, `un0/f.java`, `w30/f.java`; implementation `Sources/SonyControl/Headphones.swift`.
- Finding: `68 17` writes ANC/ambient parameters, but ACK receipt alone does not establish that a setting changed. Off with NC selector 0 was ignored during this session; Off with ASM selector 1 succeeded. Ambient level/voice parameters needed active ASM mode when restoring the original ANC configuration.
- Path P-002: read current state → select the appropriate mode → send setting → poll readback for up to three seconds. If restoring inactive ambient parameters, activate ASM with those parameters before restoring the requested sound mode. Every public setting operation verifies the result.

### F-003: EQ and battery work without the phone

- Category: reverse_algo; severity: n/a_re; status: validated; confidence: high for exercised operations.
- Evidence: E-imports, E-004, E-005.
- Location: `jn0/x0.java`, `kn0/c.java`, power status classes; implementation `Sources/SonyControl/Headphones.swift`.
- Finding: the headset advertised 12 saved EQ presets and six band values. Battery status returned 81%, later 80%. EQ Off selection and Custom 1 restoration were verified. The other advertised preset IDs are exposed by the client but were not individually exercised.
- Path P-003: `22 00` reads battery; `56 00` reads EQ; `58 00 <preset> 00` selects a saved preset without supplying new band values. Exact restoration additionally re-sends the original band values.

Remediation is not applicable: these are interoperability findings, not vulnerability claims. ATT&CK mapping is not applicable.

## Recovered wire format

All numbers below are hexadecimal unless stated otherwise.

```text
3e | escaped(type | sequence | payload_length_be32 | payload | checksum) | 3c
```

`checksum` is the low eight bits of the unsigned sum of type, sequence, length bytes, and payload. Escape `3c`, `3d`, and `3e` as `3d 2c`, `3d 2d`, and `3d 2e`. Data type `0c` is MDR data; type `01` is ACK. Sequence alternates 0/1; ACK carries the next sequence (`1 - received_sequence`). Retransmitted incoming frames are acknowledged and deduplicated. No application-layer encryption was observed in the exercised command stream; Bluetooth link security still applies.

| Operation | Request payload | Reply prefix |
|---|---|---|
| Protocol | `00 00` | `01 00` |
| Connection capability | `02 00` | `03 00` |
| Supported functions | `06 00` | `07 00` |
| Battery | `22 00` | `23 00` |
| EQ capability | `50 00` | `51 00` |
| EQ state | `56 00` | `57 00` |
| Select saved EQ | `58 00 <id> 00` | ACK, then read EQ state |
| ANC capability | `60 17` | `61 17` |
| ANC availability | `62 17` | `63 17` |
| ANC state | `66 17` | `67 17` |
| ANC setting | `68 17 <change> <effect> <mode> <voice> <level>` | ACK, then read ANC state |

For ANC setting, change `01` means changed; effect `00/01` means Off/On; mode `00/01` means ANC/ASM; voice `00/01` means normal/voice focus; ambient level is decimal 1–20. Availability uses a different enum: `00` means enabled.

Observed starting state:

```text
ANC: 67 17 01 01 00 00 14
EQ:  57 00 a1 06 10 10 0e 0c 0d 13
```

This means ANC on, ambient level 20 retained, normal ambient mode, Custom 1 selected, and six raw EQ values. The final verification restored both payloads exactly.

## Validation and practical limits

The five offline checks cover captured query/ACK bytes, fragmented response parsing, Sony escape bytes, corruption recovery, and invalid length/sequence/escape rejection. They run without XCTest because this command line toolchain lacks that module. The full hardware verification passed after the firmware-specific changes described above. The native menu app shares the same controller, and the packaged app successfully read live state on startup (E-008). Individual menu actions were not clicked; they call the same hardware-verified controller.

The client intentionally matches one exactly named WH-CH720N. It has bounded connection/request timeouts, no automatic reconnect or outgoing retransmission, and no continuous polling. A Bluetooth dropout or process kill during verification can prevent restoration. Firmware updates, multipoint configuration, adaptive sound control, DSEE, custom EQ editing, and other models remain out of scope. The phone app's adaptive automation can still independently change headphone settings if it is running.

See [README](../README.md) for build and usage commands.
