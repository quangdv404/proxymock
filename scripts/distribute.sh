#!/bin/bash
set -e

# ============================================================
#  ProxyMock — Distribution Script
#  Builds the app, packages it, and creates a fix script
#  for other macOS machines to re-sign and bypass firewall
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="ProxyMock"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "🚀 Starting distribution build for $APP_NAME..."

# Step 1: Run install.sh to build the app and create the bundle
echo "🔨 Running build script..."
# Using yes 'n' to avoid installing to /Applications during distribution
yes 'n' | "$SCRIPT_DIR/install.sh"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ App bundle not found at $APP_BUNDLE"
    exit 1
fi

echo "📦 Preparing distribution folder..."
mkdir -p "$DIST_DIR"
rm -rf "$DIST_DIR/$APP_NAME"
mkdir -p "$DIST_DIR/$APP_NAME"

# Copy the app
cp -R "$APP_BUNDLE" "$DIST_DIR/$APP_NAME/"

# Create the fix script
FIX_SCRIPT="$DIST_DIR/$APP_NAME/Fix_ProxyMock_Firewall.command"
cat > "$FIX_SCRIPT" << 'EOF'
#!/bin/bash
set -e

echo "============================================================"
echo "    ProxyMock - Firewall & Quarantine Fix"
echo "============================================================"
echo "This script will fix issues with the macOS Application Firewall"
echo "blocking ProxyMock from starting its proxy server."
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$SCRIPT_DIR/ProxyMock.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Error: Could not find ProxyMock.app in the same folder."
    echo "Make sure this script is in the same folder as the app."
    read -p "Press Enter to exit..."
    exit 1
fi

echo "1️⃣ Removing Apple quarantine flags..."
xattr -rc "$APP_PATH" || true

echo "2️⃣ Re-signing the app specifically for this Mac..."
echo "    (This tells the firewall 'I built this app locally, trust it')"
codesign --force --deep --sign - "$APP_PATH"

echo "✅ Done! You can now move ProxyMock.app to your Applications folder and run it."
echo ""
read -p "Press Enter to exit..."
EOF

chmod +x "$FIX_SCRIPT"

# Zip the release
cd "$DIST_DIR"
FINAL_ZIP="ProxyMock_Release.zip"
rm -f "$FINAL_ZIP"
echo "🗜 Zipping release to $DIST_DIR/$FINAL_ZIP..."
zip -q -r "$FINAL_ZIP" "$APP_NAME"

echo "🎉 Distribution package ready at:"
echo "   $DIST_DIR/$FINAL_ZIP"
echo ""
echo "Share this ZIP file with the other Mac. They must run the Fix script before launching!"
