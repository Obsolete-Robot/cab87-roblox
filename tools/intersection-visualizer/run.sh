#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v npm >/dev/null 2>&1; then
  echo "[cab87] npm was not found. Install Node.js, then run this file again."
  exit 1
fi

if [[ ! -x "node_modules/.bin/vite" ]]; then
  echo "[cab87] Installing intersection visualizer dependencies..."
  npm install
fi

if command -v open >/dev/null 2>&1; then
  open "http://localhost:3000" >/dev/null 2>&1 || true
fi

npm run dev
