# Scope

The user requested reverse engineering of their installed Sony Sound Connect app to control ANC and other WH-CH720N features from their laptop. The connected phone and the WH-CH720N paired with this Mac are the targets. macOS was selected because the headset is already connected to this workspace's Mac; the user supplied the CH720N model.

Included: pulling the installed base APK, local decompilation, reading Sony control-service discovery information, implementing a macOS client, and reversible sound/EQ verification on this headset. The original sound/EQ configuration is restored after verification.

No app-account, cloud-service, firmware-update, authentication-bypass, unrelated phone-data, or third-party-device analysis was needed. Sound Connect was force-stopped once to release a possible competing Bluetooth connection. No app patch, replacement APK, root access, or dynamic hook was used.

Follow-up scope: the user requested faster controls, ambient/battery bug fixes, a floating desktop panel, and investigation of ANC-strength adjustment. This includes reversible timing and rapid-input/reconnection checks, UI changes, and read-only inspection of the advertised ANC control surface.
