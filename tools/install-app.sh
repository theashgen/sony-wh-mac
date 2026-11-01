#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tools/build-app.sh
app_dir="$HOME/Applications/Sony Control.app"
mkdir -p "$HOME/Applications"
if [ -d "$app_dir" ]; then
    identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_dir/Contents/Info.plist")
    [ "$identifier" = "local.sony-rev.control" ] || { echo "A different app already exists at $app_dir" >&2; exit 1; }
fi
ditto ".build/Sony Control.app" "$app_dir"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_dir"
pluginkit -a "$app_dir/Contents/PlugIns/SonyControlWidget.appex"
# Avoid a second registered development copy of the same widget.
pluginkit -r "$PWD/.build/Sony Control.app/Contents/PlugIns/SonyControlWidget.appex" 2>/dev/null || true
printf 'Installed %s\nQuit the running Sony Control before reopening the updated app.\n' "$app_dir"
