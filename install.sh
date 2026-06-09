#!/usr/bin/env bash
# install.sh — build and install BrainDump.app into /Applications
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/narulaskaran/brain-dump/main/install.sh | bash
# or after cloning:
#   ./install.sh

set -e

# ── 1. Check for Xcode Command Line Tools ────────────────────────────────────
echo "==> Checking for Xcode Command Line Tools..."
if ! xcode-select -p &>/dev/null; then
    echo ""
    echo "ERROR: Xcode Command Line Tools are not installed."
    echo ""
    echo "Install them with:"
    echo "  xcode-select --install"
    echo ""
    echo "Then re-run this script."
    exit 1
fi
echo "    Found: $(xcode-select -p)"

# ── 2. Locate the repo root ───────────────────────────────────────────────────
# When piped through curl the script has no file path, so we use $PWD.
# When run as ./install.sh from inside the clone, $PWD is the repo root.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || pwd)"
echo "==> Working directory: $SCRIPT_DIR"

# If Package.swift isn't here, try cloning
if [ ! -f "$SCRIPT_DIR/Package.swift" ]; then
    echo "==> Package.swift not found — cloning repository..."
    CLONE_DIR="$(mktemp -d)/brain-dump"
    git clone --depth 1 https://github.com/narulaskaran/brain-dump.git "$CLONE_DIR"
    SCRIPT_DIR="$CLONE_DIR"
    echo "==> Cloned to $SCRIPT_DIR"
fi

cd "$SCRIPT_DIR"

# ── 3. Build ──────────────────────────────────────────────────────────────────
echo "==> Building BrainDump (release)..."
swift build -c release
echo "    Build complete."

# ── 4. Locate the release binary ─────────────────────────────────────────────
BINARY=".build/release/BrainDump"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Release binary not found at $BINARY"
    exit 1
fi

# ── 5. Assemble .app bundle ───────────────────────────────────────────────────
APP_DIR="/Applications/BrainDump.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

echo "==> Creating app bundle at $APP_DIR..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$BINARY" "$MACOS_DIR/BrainDump"
chmod +x "$MACOS_DIR/BrainDump"
echo "    Binary installed."

# ── 6. Write Info.plist ───────────────────────────────────────────────────────
PLIST_SRC="Sources/macOS/Info.plist"
if [ -f "$PLIST_SRC" ]; then
    cp "$PLIST_SRC" "$APP_DIR/Contents/Info.plist"
    echo "    Info.plist copied from source."
else
    echo "    WARNING: $PLIST_SRC not found — writing minimal Info.plist."
    cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.braindump.app</string>
    <key>CFBundleName</key>
    <string>BrainDump</string>
    <key>CFBundleDisplayName</key>
    <string>BrainDump</string>
    <key>CFBundleExecutable</key>
    <string>BrainDump</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
</dict>
</plist>
PLIST
fi

# ── 7. Done ───────────────────────────────────────────────────────────────────
echo ""
echo "✓ BrainDump installed to /Applications/BrainDump.app"
echo ""
echo "FIRST LAUNCH — Gatekeeper bypass:"
echo "  Right-click BrainDump.app in /Applications → Open → Open"
echo ""
echo "After launch, open Settings (Cmd+,) to enter your API key and vault path."
