#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
VENV_DIR="$BACKEND_DIR/venv"
REQ_FILE="$BACKEND_DIR/requirements.txt"

if [[ ! -d "$BACKEND_DIR" ]]; then
  echo "Backend directory not found: $BACKEND_DIR"
  exit 1
fi

cd "$BACKEND_DIR"

if [[ ! -d "$VENV_DIR" ]]; then
  echo "Creating virtual environment..."
  python3 -m venv "$VENV_DIR"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

# Install deps if missing or requirements changed.
MARKER_FILE="$VENV_DIR/.requirements.sha256"
CURRENT_HASH="$(shasum -a 256 "$REQ_FILE" | awk '{print $1}')"
PREV_HASH=""
if [[ -f "$MARKER_FILE" ]]; then
  PREV_HASH="$(cat "$MARKER_FILE")"
fi

if [[ "$CURRENT_HASH" != "$PREV_HASH" ]]; then
  echo "Installing backend dependencies..."
  pip install --upgrade pip
  pip install -r "$REQ_FILE"
  echo "$CURRENT_HASH" > "$MARKER_FILE"
fi

echo "Starting backend at http://0.0.0.0:8000"
exec python3 -m uvicorn server:app --host 0.0.0.0 --port 8000 --reload
