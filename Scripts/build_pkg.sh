#!/bin/zsh
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

DIST_DIR="$REPO_ROOT/dist"
APP_BUNDLE="MateView GT Control.app"
APP_SRC="$DIST_DIR/$APP_BUNDLE"
PKG_PATH="$DIST_DIR/MateView GT Control Installer.pkg"
PKG_ROOT="/tmp/MateViewGT_PKG_Root"
PKG_SCRIPTS="/tmp/MateViewGT_PKG_Scripts"
COMPONENT_PKG="/tmp/MateViewGT_Component.pkg"

if [ ! -d "$APP_SRC" ]; then
    zsh "$REPO_ROOT/Scripts/build_app.sh"
fi

rm -rf "$PKG_ROOT" "$PKG_SCRIPTS" "$COMPONENT_PKG" "$PKG_PATH"
mkdir -p "$PKG_ROOT/Applications" "$PKG_SCRIPTS" "$DIST_DIR"

echo "1. Staging $APP_BUNDLE into payload root..."
cp -R "$APP_SRC" "$PKG_ROOT/Applications/"

# Create hardened postinstall script using launchctl asuser
cat > "$PKG_SCRIPTS/postinstall" << 'EOF'
#!/bin/zsh
APP_DEST="/Applications/MateView GT Control.app"
if [ -d "$APP_DEST" ]; then
    chown -R root:wheel "$APP_DEST" 2>/dev/null || true
    chmod -R 755 "$APP_DEST" 2>/dev/null || true
    xattr -cr "$APP_DEST" 2>/dev/null || true
    killall MateViewGT 2>/dev/null || true
    CONSOLE_UID=$(stat -f "%u" /dev/console 2>/dev/null || echo "")
    if [ -n "$CONSOLE_UID" ] && [ "$CONSOLE_UID" != "0" ]; then
        launchctl asuser "$CONSOLE_UID" /usr/bin/open "$APP_DEST" 2>/dev/null || true
    fi
fi
exit 0
EOF
chmod +x "$PKG_SCRIPTS/postinstall"

echo "2. Building component package..."
pkgbuild \
    --root "$PKG_ROOT" \
    --identifier "com.ruoshui.MateViewGT.pkg" \
    --version "1.0.0" \
    --install-location "/" \
    --scripts "$PKG_SCRIPTS" \
    "$COMPONENT_PKG"

echo "3. Building final product installer package (.pkg)..."
productbuild \
    --package "$COMPONENT_PKG" \
    "$PKG_PATH"

rm -rf "$PKG_ROOT" "$PKG_SCRIPTS" "$COMPONENT_PKG"

echo "Successfully built $PKG_PATH"
