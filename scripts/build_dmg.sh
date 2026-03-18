#!/bin/bash
set -e

# ─── Configuration ───────────────────────────────────────────────
APP_NAME="AI VaultIO"
DMG_NAME="AI-VaultIO-macOS"
VOLUME_NAME="AI VaultIO"
BUILD_DIR="build/macos/Build/Products/Release"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_DIR="build/dmg"
DMG_PATH="$DMG_DIR/$DMG_NAME.dmg"

# Extract version from pubspec.yaml
VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | sed 's/+.*//')
DMG_VERSIONED="$DMG_DIR/${DMG_NAME}-v${VERSION}.dmg"

echo "╔══════════════════════════════════════╗"
echo "║   Building AI VaultIO macOS .dmg     ║"
echo "║   Version: $VERSION                    ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ─── Step 1: Flutter build ────────────────────────────────────────
echo "→ Building Flutter macOS release..."
flutter build macos --release

if [ ! -d "$APP_PATH" ]; then
  echo "✗ Build failed: $APP_PATH not found"
  exit 1
fi

echo "✓ Build complete: $APP_PATH"

# ─── Step 2: Create DMG staging area ──────────────────────────────
echo "→ Preparing DMG staging area..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR/staging"

# Copy the .app bundle
cp -R "$APP_PATH" "$DMG_DIR/staging/"

# Create a symbolic link to /Applications for drag-and-drop install
ln -s /Applications "$DMG_DIR/staging/Applications"

# ─── Step 3: Create DMG ──────────────────────────────────────────
echo "→ Creating DMG..."

# Check if create-dmg is available (prettier DMG with background)
if command -v create-dmg &> /dev/null; then
  echo "  Using create-dmg for styled installer..."
  create-dmg \
    --volname "$VOLUME_NAME" \
    --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "$APP_NAME.app" 150 185 \
    --icon "Applications" 450 185 \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link 450 185 \
    "$DMG_VERSIONED" \
    "$DMG_DIR/staging/"
else
  echo "  Using hdiutil (install create-dmg for a styled installer)..."
  hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_DIR/staging" \
    -ov \
    -format UDZO \
    "$DMG_VERSIONED"
fi

# Clean up staging
rm -rf "$DMG_DIR/staging"

# Also create an unversioned copy for convenience
cp "$DMG_VERSIONED" "$DMG_PATH"

# ─── Done ─────────────────────────────────────────────────────────
DMG_SIZE=$(du -h "$DMG_VERSIONED" | cut -f1)
echo ""
echo "╔══════════════════════════════════════╗"
echo "║   ✓ DMG created successfully!        ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "  File: $DMG_VERSIONED"
echo "  Size: $DMG_SIZE"
echo ""
echo "  To install: Open the .dmg and drag AI VaultIO to Applications."
echo ""
