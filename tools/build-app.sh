#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release --product sony-control
bin_dir=$(swift build -c release --show-bin-path)
app_dir="$PWD/.build/Sony Control.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$bin_dir/sony-control" "$app_dir/Contents/MacOS/sony-control"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>sony-control</string>
<key>CFBundleIdentifier</key><string>local.sony-rev.control</string>
<key>CFBundleName</key><string>Sony Control</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>CFBundleURLTypes</key><array><dict>
<key>CFBundleURLName</key><string>local.sony-rev.control</string>
<key>CFBundleURLSchemes</key><array><string>sonycontrol</string></array>
</dict></array>
<key>LSUIElement</key><true/>
<key>NSBluetoothAlwaysUsageDescription</key><string>Connect to your WH-CH720N to control noise cancellation, ambient sound, and EQ.</string>
</dict></plist>
PLIST
widget_dir="$app_dir/Contents/PlugIns/SonyControlWidget.appex"
mkdir -p "$widget_dir/Contents/MacOS"
architecture=$(uname -m)
# Foundation's NSExtensionMain initializes extension identity, then invokes Swift's entry.
xcrun swiftc -parse-as-library -O -application-extension -target "$architecture-apple-macos14.0" \
    Sources/WidgetShared/WidgetSnapshot.swift Widgets/SonyControlWidget/SonyControlWidget.swift \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist \
    -Xlinker "$PWD/Widgets/SonyControlWidget/Info.plist" \
    -o "$widget_dir/Contents/MacOS/SonyControlWidget"
cp Widgets/SonyControlWidget/Info.plist "$widget_dir/Contents/Info.plist"
signing_identity=${SONY_SIGNING_IDENTITY:--}
codesign --force --sign "$signing_identity" --entitlements Widgets/SonyControlWidget/Widget.entitlements "$widget_dir"
codesign --force --sign "$signing_identity" "$app_dir"
printf 'Built %s\n' "$app_dir"
