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
