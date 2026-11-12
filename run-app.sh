#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT_DIR/dist/Uncomew.app"
if [[ ! -d "$APP" ]]; then
  echo "Uncomew.app has not been built yet. Run ./build-app.sh first."
  exit 1
fi
open "$APP"
