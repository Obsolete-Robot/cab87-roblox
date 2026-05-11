#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SRC_DIR="$SCRIPT_DIR/studio-plugin"
TARGET_DIR="${ROBLOX_PLUGIN_DIR:-$HOME/Library/Application Support/Roblox/Plugins}"

if [[ ! -d "$PLUGIN_SRC_DIR" ]]; then
  echo "[cab87] ERROR: plugin source folder not found:"
  echo "$PLUGIN_SRC_DIR"
  exit 1
fi

mkdir -p "$TARGET_DIR"

LEGACY_PLUGIN="$TARGET_DIR/Cab87RoadCurveTools.plugin.lua"
if [[ -e "$LEGACY_PLUGIN" ]]; then
  rm -f "$LEGACY_PLUGIN"
  echo "[cab87] Removed legacy plugin: Cab87RoadCurveTools.plugin.lua"
fi

COPIED=0
PLUGIN_FILES=(
  "Cab87MapTools.plugin.lua"
  "Cab87RoadGraphBuilder.plugin.lua"
  "Cab87ManagerTools.plugin.lua"
)

for plugin_file in "${PLUGIN_FILES[@]}"; do
  src="$PLUGIN_SRC_DIR/$plugin_file"
  dst="$TARGET_DIR/$plugin_file"

  if [[ -f "$src" ]]; then
    cp -f "$src" "$dst"
    echo "[cab87] Installed plugin: $plugin_file"
    COPIED=$((COPIED + 1))
  else
    echo "[cab87] WARNING: missing plugin file $plugin_file"
  fi
done

if [[ "$COPIED" -eq 0 ]]; then
  echo "[cab87] ERROR: no plugin files were installed."
  exit 1
fi

echo "[cab87] Done. Restart Roblox Studio to load plugin updates."
