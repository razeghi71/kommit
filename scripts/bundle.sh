#!/bin/bash
set -euo pipefail

APP_NAME="Kommit"
BUNDLE_ID="no.marz.kommit"
VERSION="${VERSION:-1.0.0}"
APP_DIR="build/${APP_NAME}.app"
ICON_SVG="icon.svg"
ICON_ICNS="Sources/Kommit/Resources/AppIcon.icns"

generate_app_icon() {
    if [[ ! -f "$ICON_SVG" ]]; then
        echo "Error: Missing icon source at $ICON_SVG"
        exit 1
    fi

    if ! command -v rsvg-convert >/dev/null 2>&1; then
        echo "Error: rsvg-convert is required (brew install librsvg)"
        exit 1
    fi

    if ! command -v iconutil >/dev/null 2>&1; then
        echo "Error: iconutil is required to build $ICON_ICNS"
        exit 1
    fi

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    local iconset_dir="$tmp_dir/AppIcon.iconset"
    mkdir -p "$iconset_dir"

    render_icon() {
        local size="$1"
        local out_name="$2"
        local out_path="$iconset_dir/$out_name"
        rsvg-convert -w "$size" -h "$size" "$ICON_SVG" -o "$out_path"
    }

    echo "Generating $ICON_ICNS from $ICON_SVG..."
    render_icon 16 "icon_16x16.png"
    render_icon 32 "icon_16x16@2x.png"
    render_icon 32 "icon_32x32.png"
    render_icon 64 "icon_32x32@2x.png"
    render_icon 128 "icon_128x128.png"
    render_icon 256 "icon_128x128@2x.png"
    render_icon 256 "icon_256x256.png"
    render_icon 512 "icon_256x256@2x.png"
    render_icon 512 "icon_512x512.png"
    render_icon 1024 "icon_512x512@2x.png"

    iconutil -c icns "$iconset_dir" -o "$ICON_ICNS"
    rm -rf "$tmp_dir"
}

# Build universal binary (arm64 + x86_64)
echo "Building release binary (arm64)..."
swift build -c release --arch arm64

echo "Building release binary (x86_64)..."
swift build -c release --arch x86_64

echo "Creating universal binary..."
mkdir -p .build/universal
lipo -create \
    .build/arm64-apple-macosx/release/$APP_NAME \
    .build/x86_64-apple-macosx/release/$APP_NAME \
    -output .build/universal/$APP_NAME

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp ".build/universal/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
generate_app_icon
cp "$ICON_ICNS" "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
</dict>
</plist>
PLIST

echo "Done: $APP_DIR"
echo ""
echo "To install:  cp -R \"$APP_DIR\" /Applications/"
echo "To open:     open \"$APP_DIR\""
