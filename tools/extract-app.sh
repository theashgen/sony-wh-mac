#!/bin/sh
# Extract only the authorized app; no root, installation, or phone data dump.
set -eu
cd "$(dirname "$0")/.."
if [ -z "${JAVA_HOME:-}" ] && [ -x /opt/homebrew/opt/openjdk/bin/java ]; then
    export JAVA_HOME=/opt/homebrew/opt/openjdk
fi
mkdir -p research/apk research/evidence
apk_path=$(adb shell pm path com.sony.songpal.mdr | tr -d '\r' | sed -n 's/^package:\(.*\/base.apk\)$/\1/p')
if [ -z "$apk_path" ]; then
    printf '%s\n' 'Sound Connect base APK not found on the selected ADB device.' >&2
    exit 1
fi
adb pull "$apk_path" research/apk/sound-connect.apk
shasum -a 256 research/apk/sound-connect.apk > research/evidence/extracted-apk.sha256
# JADX can exit nonzero while still producing useful sources; retain its log.
if ! jadx --no-res -j 6 -d research/jadx research/apk/sound-connect.apk > research/evidence/jadx.log 2>&1; then
    printf '%s\n' 'JADX reported decompilation errors; inspect research/evidence/jadx.log.' >&2
fi
apktool d -s -f research/apk/sound-connect.apk -o research/resources > research/evidence/apktool.log 2>&1
printf '%s\n' 'Extracted sources to research/jadx and manifest/resources to research/resources.'
