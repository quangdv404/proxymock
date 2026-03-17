#!/bin/bash
set -e

# ============================================================
#  ProxyMock — Build & Install Script
#  Creates a proper .app bundle and copies to /Applications
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="ProxyMock"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="/Applications"

echo "🔨 Building ProxyMock in release mode..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

EXECUTABLE="$BUILD_DIR/release/ProxyMock"
if [ ! -f "$EXECUTABLE" ]; then
    echo "❌ Build failed — executable not found at $EXECUTABLE"
    exit 1
fi
echo "✅ Build complete"

# Create .app bundle structure
echo "📦 Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist
if [ -f "$PROJECT_DIR/SupportFiles/Info.plist" ]; then
    cp "$PROJECT_DIR/SupportFiles/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
else
    # Generate a minimal Info.plist
    cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ProxyMock</string>
    <key>CFBundleIdentifier</key>
    <string>com.proxymock.app</string>
    <key>CFBundleName</key>
    <string>ProxyMock</string>
    <key>CFBundleDisplayName</key>
    <string>ProxyMock</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST
fi

# Add PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Sign the app with entitlements (ad-hoc signing)
echo "🔏 Signing app..."
if [ -f "$PROJECT_DIR/SupportFiles/ProxyMock.entitlements" ]; then
    codesign --force --sign - \
        --entitlements "$PROJECT_DIR/SupportFiles/ProxyMock.entitlements" \
        "$APP_BUNDLE"
else
    codesign --force --sign - "$APP_BUNDLE"
fi
echo "✅ Signed"

echo ""
echo "📍 App bundle created at:"
echo "   $APP_BUNDLE"
echo ""

# Ask to install to /Applications
read -p "📲 Install to $INSTALL_DIR? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "📲 Installing to $INSTALL_DIR..."
    cp -R "$APP_BUNDLE" "$INSTALL_DIR/"
    echo "✅ ProxyMock.app installed to $INSTALL_DIR"
    echo ""
    echo "🚀 You can now launch ProxyMock from:"
    echo "   • Spotlight: search 'ProxyMock'"
    echo "   • Finder: Applications → ProxyMock"
    echo "   • Terminal: open /Applications/ProxyMock.app"
else
    echo ""
    echo "ℹ️  To install later, copy the app bundle:"
    echo "   cp -R \"$APP_BUNDLE\" $INSTALL_DIR/"
fi

echo ""
echo "Done! 🎉"
