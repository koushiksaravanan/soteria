#!/bin/sh
# Build SoteriaBar.app with the command-line tools only (no Xcode project).
# Output: ./SoteriaBar.app (menu-bar only, LSUIElement). CLI bundled beside it.
set -eu
cd "$(dirname "$0")/../.."
APP="SoteriaBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -o "$APP/Contents/MacOS/SoteriaBar" app/SoteriaBar/main.swift -framework AppKit -framework Security
cp ./soteria "$APP/Contents/MacOS/soteria"
# Optional custom menu icon: black-on-transparent PNG (18px, +36px @2x).
# Drop your art at app/SoteriaBar/MenuIcon.png (and MenuIcon@2x.png) and it
# ships automatically; without it the app falls back to the system shield.
for icon in app/SoteriaBar/MenuIcon.png app/SoteriaBar/MenuIcon@2x.png; do
  [ -f "$icon" ] && cp "$icon" "$APP/Contents/Resources/"
done
chmod +x "$APP/Contents/MacOS/soteria"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>SoteriaBar</string>
  <key>CFBundleIdentifier</key><string>dev.soteria.bar</string>
  <key>CFBundleName</key><string>SoteriaBar</string>
  <key>CFBundleVersion</key><string>0.1.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
codesign -s - --deep --force "$APP" 2>/dev/null || true
echo "built: $APP"
echo "run:   open $APP   (look for the shield in the menu bar)"
