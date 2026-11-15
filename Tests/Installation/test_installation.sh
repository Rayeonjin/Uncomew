#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/scripts/installation_common.sh"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/uncomew-install-tests.XXXXXX")"
FIXTURE="$(cd "$FIXTURE" && pwd -P)"
RUNNING_PID=""
trap '[ -z "$RUNNING_PID" ] || kill "$RUNNING_PID" 2>/dev/null || true; rm -rf "$FIXTURE"' EXIT
DEST="$FIXTURE/설치 space"
APP="$ROOT/dist/Uncomew.app"
VALIDATOR="$ROOT/scripts/validate_app.sh"
bash "$VALIDATOR" "$APP"
make_version() {
  local version="$1" target="$FIXTURE/$1.app"
  /usr/bin/ditto "$APP" "$target"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$target/Contents/Info.plist"
  /usr/bin/codesign --force --sign - "$target" >/dev/null 2>&1
}
version_at() { /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist"; }
checks=0
expect_version() {
  [ "$(version_at "$1")" = "$2" ] || { echo "Wrong version at $1" >&2; exit 1; }
  checks=$((checks + 1))
}
expect_failure() {
  # Execute in a fresh bash: calling a function inside `if` disables errexit
  # throughout it, which would invalidate transaction failure tests.
  local status=0
  bash -c 'set -euo pipefail; source "$1"; replace_uncomew_app "$2" "$3" "$4"' _ \
    "$ROOT/scripts/installation_common.sh" "$1" "$2" "$3" >"$FIXTURE/failure.log" 2>&1 || status=$?
  [ "$status" -ne 0 ] || { echo 'Expected failure' >&2; exit 1; }
  checks=$((checks + 1))
}
make_version 1.0.0
make_version 2.0.0
make_version 3.0.0
replace_uncomew_app "$FIXTURE/1.0.0.app" "$DEST" "$VALIDATOR"
expect_version "$DEST/Uncomew.app" 1.0.0
[ ! -e "$DEST/Uncomew.previous.app" ]
replace_uncomew_app "$FIXTURE/2.0.0.app" "$DEST" "$VALIDATOR"
expect_version "$DEST/Uncomew.app" 2.0.0
expect_version "$DEST/Uncomew.previous.app" 1.0.0
UNCOMEW_APPLICATIONS_DIR="$DEST" bash "$ROOT/scripts/rollback.sh"
expect_version "$DEST/Uncomew.app" 1.0.0
expect_version "$DEST/Uncomew.previous.app" 2.0.0
replace_uncomew_app "$FIXTURE/3.0.0.app" "$DEST" "$VALIDATOR"
expect_version "$DEST/Uncomew.app" 3.0.0
expect_version "$DEST/Uncomew.previous.app" 1.0.0

# Inject one failing rename at each of the four update boundaries. The wrapper
# exists only in this subprocess; production has no failure-injection switches.
for boundary in 1 2 3 4; do
  status=0
  bash -c '
    set -euo pipefail
    source "$1"
    count=0
    fail_at="$5"
    mv() { count=$((count + 1)); if [ "$count" -eq "$fail_at" ]; then return 1; fi; /bin/mv "$@"; }
    replace_uncomew_app "$2" "$3" "$4"
  ' _ "$ROOT/scripts/installation_common.sh" "$FIXTURE/2.0.0.app" "$DEST" "$VALIDATOR" "$boundary" >"$FIXTURE/failure.log" 2>&1 || status=$?
  [ "$status" -ne 0 ]
  expect_version "$DEST/Uncomew.app" 3.0.0
  expect_version "$DEST/Uncomew.previous.app" 1.0.0
  [ ! -e "$DEST/.uncomew-install.lock" ]
done

# Reject a failed validation after publication, recovering both app slots.
cat > "$FIXTURE/fail-validator.sh" <<SCRIPT
#!/bin/bash
[ "\$1" != '$DEST/Uncomew.app' ] || exit 1
bash '$VALIDATOR' "\$1"
SCRIPT
expect_failure "$FIXTURE/2.0.0.app" "$DEST" "$FIXTURE/fail-validator.sh"
expect_version "$DEST/Uncomew.app" 3.0.0
expect_version "$DEST/Uncomew.previous.app" 1.0.0

mkdir "$DEST/.uncomew-install.lock"
expect_failure "$FIXTURE/2.0.0.app" "$DEST" "$VALIDATOR"
[ -d "$DEST/.uncomew-install.lock" ]
rmdir "$DEST/.uncomew-install.lock"
ln -s "$DEST" "$FIXTURE/linked"
expect_failure "$FIXTURE/2.0.0.app" "$FIXTURE/linked/nested" "$VALIDATOR"
mkdir "$FIXTURE/symlink-slot"
ln -s "$DEST/Uncomew.app" "$FIXTURE/symlink-slot/Uncomew.app"
expect_failure "$FIXTURE/2.0.0.app" "$FIXTURE/symlink-slot" "$VALIDATOR"
mkdir -p "$FIXTURE/unrelated/Uncomew.app"
expect_failure "$FIXTURE/2.0.0.app" "$FIXTURE/unrelated" "$VALIDATOR"
expect_failure "$FIXTURE/missing.app" "$DEST" "$VALIDATOR"
expect_failure "$FIXTURE/2.0.0.app" relative-path "$VALIDATOR"

# Invalid signature and executable redirects must not disturb the current app.
/usr/bin/ditto "$FIXTURE/2.0.0.app" "$FIXTURE/tampered.app"
echo altered >> "$FIXTURE/tampered.app/Contents/MacOS/Uncomew"
expect_failure "$FIXTURE/tampered.app" "$DEST" "$VALIDATOR"
/usr/bin/ditto "$FIXTURE/2.0.0.app" "$FIXTURE/redirect.app"
rm "$FIXTURE/redirect.app/Contents/MacOS/Uncomew"
ln -s "$APP/Contents/MacOS/Uncomew" "$FIXTURE/redirect.app/Contents/MacOS/Uncomew"
expect_failure "$FIXTURE/redirect.app" "$DEST" "$VALIDATOR"
expect_version "$DEST/Uncomew.app" 3.0.0
expect_version "$DEST/Uncomew.previous.app" 1.0.0
# Refuse replacement of a running process without killing it. This is a disposable
# sleep executable named Uncomew, never an installed user app.
cp /bin/sleep "$FIXTURE/Uncomew"
# Re-sign the copied system binary for its disposable location.
/usr/bin/codesign --force --sign - "$FIXTURE/Uncomew" >/dev/null 2>&1
"$FIXTURE/Uncomew" 60 &
RUNNING_PID=$!
expect_failure "$FIXTURE/2.0.0.app" "$DEST" "$VALIDATOR"
kill -0 "$RUNNING_PID"
kill "$RUNNING_PID"
wait "$RUNNING_PID" 2>/dev/null || true
RUNNING_PID=""
expect_version "$DEST/Uncomew.app" 3.0.0

# First installation failing after publication must leave no current app.
FIRST="$FIXTURE/first-failure"
cat > "$FIXTURE/first-validator.sh" <<SCRIPT
#!/bin/bash
[ "\$1" != '$FIRST/Uncomew.app' ] || exit 1
bash '$VALIDATOR' "\$1"
SCRIPT
expect_failure "$FIXTURE/2.0.0.app" "$FIRST" "$FIXTURE/first-validator.sh"
[ ! -e "$FIRST/Uncomew.app" ]

# Exercise the public entry point from an extracted-source-like path, without
# executable script permissions or pre-existing build output.
SOURCE="$FIXTURE/소스 ZIP space"
mkdir -p "$SOURCE"
for item in Package.swift Sources Resources scripts setup.sh; do
  /usr/bin/ditto "$ROOT/$item" "$SOURCE/$item"
done
find "$SOURCE" -name '*.sh' -exec chmod -x {} +
UNCOMEW_APPLICATIONS_DIR="$FIXTURE/setup destination" bash "$SOURCE/setup.sh" >"$FIXTURE/setup.log" 2>&1 || {
  cat "$FIXTURE/setup.log" >&2; exit 1;
}
bash "$VALIDATOR" "$FIXTURE/setup destination/Uncomew.app"
expect_version "$FIXTURE/setup destination/Uncomew.app" "$(version_at "$APP")"
printf 'Passed %s installation/rollback assertions using disposable app copies.\n' "$checks"
