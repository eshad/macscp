#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/MacSCP.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building MacSCP..."

# Clean and create app bundle structure
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

# Compile
swiftc -parse-as-library \
    -target arm64-apple-macosx13.0 \
    -sdk "$(xcrun --show-sdk-path)" \
    -framework SwiftUI \
    -framework AppKit \
    -framework UniformTypeIdentifiers \
    -O \
    -o "$MACOS/MacSCP" \
    $(find "$PROJECT_DIR/MacSCP" -name '*.swift') \
    2>&1 | grep -v warning || true

# Copy icon
cp "$PROJECT_DIR/MacSCP/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"

# Write Info.plist
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MacSCP</string>
    <key>CFBundleIdentifier</key>
    <string>com.macscp.app</string>
    <key>CFBundleName</key>
    <string>MacSCP</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.5.3</string>
    <key>CFBundleVersion</key>
    <string>12</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
PLIST

echo "Build complete: $APP_DIR"

# Ad-hoc sign the build
codesign --force --deep --sign - "$APP_DIR"

echo "Build complete: $APP_DIR"

# Install to /Applications
echo "Installing to /Applications..."
rm -rf /Applications/MacSCP.app
cp -R "$APP_DIR" /Applications/MacSCP.app

# Re-register with LaunchServices so icon shows
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f /Applications/MacSCP.app

echo "Installed to /Applications/MacSCP.app"
