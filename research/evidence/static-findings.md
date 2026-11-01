# Static observations — Sound Connect 13.3.0

Analyzed the installed base APK with JADX 1.5.6 and apktool 3.0.3. Source paths below are relative to `research/jadx/sources/`; they can be regenerated with `tools/extract-app.sh` against the same APK. These are analysis notes, not redistributed decompiled app code.

- Manifest: package `com.sony.songpal.mdr`; application `com.sony.songpal.mdr.vim.MdrApplication`; launcher `com.sony.songpal.mdr.vim.activity.MdrMainActivity`.
- E-imports equivalent for DEX: `ep0/c.java` imports Android BluetoothAdapter/BluetoothDevice and opens `createRfcommSocketToServiceRecord(eVar.a())`; `dp0/a.java` adapts BluetoothSocket streams. `qm0/b.java` frames socket output using ByteArrayOutputStream; `qm0/a.java` parses input. Critical control logic is Java. No JNI/native analysis was needed; native ABI split was not extracted.
- `lm0/i.java`: TABLE_SET_2 service UUID `956C7B26-D49A-4BA8-B03F-B17D393CB6E2`; `om0/d.java` selects it. The TABLE_SET_1 service UUID is `96CC203E-5068-46AD-B32D-E316F5E069BA`.
- `com/sony/songpal/tandemfamily/message/DataType.java`: DATA_MDR byte 12 and ACK byte 1.
- `qm0/b.java`: 0x3e start, datatype, sequence, 4-byte big-endian payload length, payload, checksum, 0x3c end.
- `cp0/f.java`: checksum is the low byte of the sum of unsigned body bytes.
- `cp0/b.java` and `qm0/e.java`: reserved bytes 0x3c/0x3d/0x3e escape to 0x3d followed by 0x2c/0x2d/0x2e.
- `lm0/c.java` and `cp0/d.java`: ACK sequence is 1 minus incoming sequence; outbound sequence switches on a matching ACK.
- `com/sony/songpal/tandemfamily/message/mdr/v2/table1/Command.java`: protocol query 0x00; function query 0x06; battery status 0x22; EQ read/write 0x56/0x58; ANC/ASM read/write 0x66/0x68.
- `sn0/c1.java`, `un0/f.java`, `sn0/l0.java`: NC/ASM type 0x17, followed by change-status, total effect, NC/ASM mode, voice-focus mode, and ambient level. `w30/f.java` is the higher-level app sender.
- `jn0/x0.java`, `jn0/j0.java`, `kn0/c.java`: EQ contains inquiry type, preset id, band count, and band values. `jn0/z.java` parses EQ capability records.
- `com/sony/songpal/tandemfamily/message/mdr/v2/EnableDisable.java`: 0 means enabled, 1 means disabled; this differs from the ANC on/off flag.
- JADX reported 278 errors elsewhere in the full application. Findings were checked against the parsed classes and live headset responses; the whole app was not perfectly decompiled.
