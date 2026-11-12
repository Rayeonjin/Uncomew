#!/bin/bash
set -euo pipefail
[ "$#" -eq 1 ] || { echo 'Usage: bash scripts/validate_app.sh /path/to/Uncomew.app' >&2; exit 2; }
APP="$1"
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[ -d "$APP" ] && [ ! -L "$APP" ] || fail "App is missing or is a symbolic link: $APP"
# Current Uncomew bundles need no symlinks. Do not accept redirected metadata/code.
LINKS="$(find "$APP" -type l -print)" || fail "Could not inspect bundle."
[ -z "$LINKS" ] || fail "Symbolic links are not supported in this app bundle."
PLIST="$APP/Contents/Info.plist"
BIN="$APP/Contents/MacOS/Uncomew"
/usr/bin/plutil -lint "$PLIST" >/dev/null || fail "Invalid Info.plist."
value() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null; }
[ "$(value CFBundleIdentifier)" = io.github.rayeonjin.uncomew ] || fail "Unexpected bundle identifier."
[ "$(value CFBundleExecutable)" = Uncomew ] || fail "Unexpected executable name."
[ "$(value CFBundlePackageType)" = APPL ] || fail "Not an application bundle."
[ "$(value LSMinimumSystemVersion)" = 13.0 ] || fail "Unexpected minimum macOS version."
VERSION="$(value CFBundleShortVersionString)"
[ -n "$VERSION" ] || fail "Missing app version."
[ -f "$BIN" ] && [ -x "$BIN" ] || fail "App executable is missing or not executable."
ARCHS="$(/usr/bin/lipo -archs "$BIN")" || fail "Cannot inspect executable architecture."
case " $ARCHS " in *" $(uname -m) "*) ;; *) fail "App does not support this Mac's architecture: $ARCHS" ;; esac
/usr/bin/codesign --verify --deep --strict "$APP" || fail "App signature verification failed."
printf 'Validated Uncomew %s (%s).\n' "$VERSION" "$ARCHS"
