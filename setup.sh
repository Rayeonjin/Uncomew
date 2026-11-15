#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
[ "$#" -eq 0 ] || { echo 'Usage: bash setup.sh' >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Run setup as your normal user, without sudo.' >&2; exit 1; }
DEST_DIR="${UNCOMEW_APPLICATIONS_DIR:-/Applications}"
if [ "$DEST_DIR" = /Applications ] && [ ! -w "$DEST_DIR" ]; then
  echo 'Cannot write to /Applications. Run setup from a Mac account with permission to install applications (normally an administrator). Do not run the build with sudo.' >&2
  exit 1
fi
bash "$ROOT/scripts/compatibility_check.sh"
printf 'Building Uncomew for this Mac. Installation folder: %s\n' "$DEST_DIR"
bash "$ROOT/scripts/build-app.sh"
source "$ROOT/scripts/installation_common.sh"
replace_uncomew_app "$ROOT/dist/Uncomew.app" "$DEST_DIR" "$ROOT/scripts/validate_app.sh"
printf '\nOpen the installed app with:\n  open %q\n' "$DEST_DIR/Uncomew.app"
echo 'If privacy-protected folders need access, add this installed app in System Settings > Privacy & Security > Full Disk Access.'
echo 'Updates are manual: download a new release source ZIP and run bash setup.sh there.'
