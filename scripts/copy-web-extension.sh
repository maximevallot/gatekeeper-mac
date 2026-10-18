#!/bin/sh
# Copies the Gatekeeper web extension into the Safari extension's Resources at build time. The source is read
# only: it belongs to ~/gatekeeper-app, owned and changed there. Override with GATEKEEPER_EXTENSION_DIR.
set -eu
SRC="${GATEKEEPER_EXTENSION_DIR:-$HOME/gatekeeper-app/extension}"
DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
if [ ! -f "$SRC/manifest.json" ]; then
  echo "error: no Gatekeeper extension at $SRC (clone github.com/maximevallot/gatekeeper-app to ~/gatekeeper-app, or set GATEKEEPER_EXTENSION_DIR)"
  exit 1
fi
mkdir -p "$DEST"
rsync -a --delete --exclude '.DS_Store' --exclude 'Assets.car' "$SRC/" "$DEST/"
echo "Copied the web extension from $SRC ($(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo 'no git'))"
