#!/bin/sh
set -eu

cd "$(dirname "$0")"

URL="http://127.0.0.1:8000/index.html"

if command -v python3 >/dev/null 2>&1; then
	open "$URL"
	python3 -m http.server 8000
	exit 0
fi

if command -v python >/dev/null 2>&1; then
	open "$URL"
	python -m http.server 8000
	exit 0
fi

echo "[cab87] Python was not found. Opening the static file directly instead."
open "$(pwd)/index.html"
