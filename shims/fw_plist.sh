#!/bin/sh
# usage: fw_plist.sh <executable> <bundle-id> [version]  -> minimal iOS framework Info.plist on stdout
cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$1</string>
  <key>CFBundleIdentifier</key><string>$2</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$1</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>${3:-1.0}</string>
  <key>CFBundleVersion</key><string>${3:-1.0}</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
  <key>MinimumOSVersion</key><string>26.0</string>
</dict></plist>
PLIST
