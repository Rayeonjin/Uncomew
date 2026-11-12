#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
[ "$#" -eq 0 ] || { echo 'Usage: bash rollback.sh' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Run rollback as your normal user, without sudo.' >&2; exit 1; }
DEST_DIR="${UNCOMEW_APPLICATIONS_DIR:-$HOME/Applications}"
[ -d "$DEST_DIR/Uncomew.previous.app" ] || {
  echo 'No previous version is available. Build an earlier release source ZIP using bash setup.sh.' >&2
  exit 1
}
source "$ROOT/scripts/installation_common.sh"
replace_uncomew_app "$DEST_DIR/Uncomew.previous.app" "$DEST_DIR" "$ROOT/scripts/validate_app.sh"
printf 'Rollback complete. Open with:\n  open %q\n' "$DEST_DIR/Uncomew.app"
