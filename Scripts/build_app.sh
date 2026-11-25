#!/bin/zsh
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

MODULE_CACHE="/tmp/mateviewgt_module_cache"
BUILD_DIR="$REPO_ROOT/.build"
DIST_DIR="$REPO_ROOT/dist"
APP_BUNDLE_NAME="MateView GT Control.app"
APP_NAME="$DIST_DIR/$APP_BUNDLE_NAME"
CONTENTS_DIR="$APP_NAME/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MODULE_CACHE" "$BUILD_DIR" "$MACOS_DIR" "$RESOURCES_DIR"

echo "1. Generating AppIcon.icns and MenuBarIcon.png..."
swiftc -O -disable-sandbox \
    -module-cache-path "$MODULE_CACHE" \
    "$REPO_ROOT/Scripts/generate_icon.swift" \
    -o "$BUILD_DIR/generate_icon"
"$BUILD_DIR/generate_icon" "$RESOURCES_DIR"

echo "2. Compiling Objective-C IOAVServiceBridge..."
clang -c -O2 -fobjc-arc \
    -fmodules-cache-path="$MODULE_CACHE" \
    -I Sources/CBridge/include \
    Sources/CBridge/IOAVServiceBridge.m \
    -o "$BUILD_DIR/IOAVServiceBridge.o"

echo "3. Compiling Swift MateViewGTApp..."
swiftc -O -disable-sandbox \
    -module-cache-path "$MODULE_CACHE" \
    -import-objc-header Sources/CBridge/include/IOAVServiceBridge.h \
    Sources/MateViewGTApp/Hardware/HuaweiDDCEngine.swift \
    Sources/MateViewGTApp/Hardware/HiDPIManager.swift \
    Sources/MateViewGTApp/Hardware/MediaKeyInterceptor.swift \
    Sources/MateViewGTApp/Hardware/LaunchAtLoginManager.swift \
    Sources/MateViewGTApp/UI/LiquidGlassTheme.swift \
    Sources/MateViewGTApp/UI/LiquidHUDWindow.swift \
    Sources/MateViewGTApp/UI/ControlPanelView.swift \
    Sources/MateViewGTApp/MateViewGTApp.swift \
    "$BUILD_DIR/IOAVServiceBridge.o" \
    -framework Foundation \
    -framework AppKit \
    -framework SwiftUI \
    -framework IOKit \
    -framework ApplicationServices \
    -framework CoreAudio \
    -framework AudioToolbox \
    -framework ColorSync \
    -framework Carbon \
    -framework ServiceManagement \
    -F /System/Library/PrivateFrameworks \
    -framework IOMobileFramebuffer \
    -framework DisplayServices \
    -o "$MACOS_DIR/MateViewGT"

chmod +x "$MACOS_DIR/MateViewGT"

cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MateViewGT</string>
    <key>CFBundleIdentifier</key>
    <string>com.ruoshui.MateViewGT</string>
    <key>CFBundleName</key>
    <string>MateView GT Control</string>
    <key>CFBundleDisplayName</key>
    <string>MateView GT Control</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "4. Ad-hoc signing $APP_BUNDLE_NAME..."
codesign --force --deep --sign - "$APP_NAME"
touch "$APP_NAME"

echo "Successfully built and packaged $APP_NAME"
