#!/bin/bash
# Shared by install and rollback. Recovery uses filesystem state, not post-move flags.
set -euo pipefail

replace_uncomew_app() (
  source_app="$1"; destination_dir="$2"; validator="$3"
  current="$destination_dir/Uncomew.app"
  previous="$destination_dir/Uncomew.previous.app"
  lock="$destination_dir/.uncomew-install.lock"
  stage=""

  fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
  bash "$validator" "$source_app"
  case "$destination_dir" in /*) ;; *) fail "Installation directory must be absolute." ;; esac
  [ "$destination_dir" != / ] || fail "Cannot install into filesystem root."
  # Reject symlinks in every existing ancestor before creating or replacing anything.
  ancestor="$destination_dir"
  while [ "$ancestor" != / ]; do
    [ ! -L "$ancestor" ] || fail "Installation directory contains a symbolic link: $ancestor"
    ancestor="$(dirname "$ancestor")"
  done
  mkdir -p "$destination_dir"
  [ ! -L "$current" ] && [ ! -L "$previous" ] || fail "App paths must not be symbolic links."
  mkdir "$lock" 2>/dev/null || fail "Another install or rollback is running ($lock)."

  cleanup() {
    result=$?
    trap - EXIT HUP INT TERM
    restore_failed=0
    if [ -n "$stage" ] && [ -f "$stage/transaction-started" ] && [ ! -f "$stage/committed" ]; then
      restore_source=""
      if [ -d "$stage/current.app" ]; then
        restore_source="$stage/current.app"
      elif [ -f "$stage/rotating" ] && [ -d "$previous" ]; then
        # Original current app has already moved into the previous-version slot.
        restore_source="$previous"
      fi
      if [ -n "$restore_source" ]; then
        if [ -e "$current" ]; then
          mv "$current" "$stage/uncommitted.app" || restore_failed=1
        fi
        if [ "$restore_failed" -eq 0 ]; then
          mv "$restore_source" "$current" || restore_failed=1
        fi
      elif [ ! -f "$stage/had-current" ] && [ ! -e "$stage/new.app" ] && [ -e "$current" ]; then
        mv "$current" "$stage/uncommitted.app" || restore_failed=1
      fi
      if [ -d "$stage/older.app" ]; then
        if [ -e "$previous" ]; then restore_failed=1
        else mv "$stage/older.app" "$previous" || restore_failed=1; fi
      fi
    fi
    if [ "$restore_failed" -eq 1 ]; then
      printf 'ERROR: Automatic recovery could not finish. Keep this directory for manual recovery: %s\n' "$stage" >&2
      result=1
    elif [ -n "$stage" ]; then
      rm -rf "$stage"
    fi
    rmdir "$lock" 2>/dev/null || true
    exit "$result"
  }
  trap cleanup EXIT
  trap 'exit 130' HUP INT TERM
  for existing in "$current" "$previous"; do
    if [ -e "$existing" ]; then
      [ -d "$existing" ] || fail "Existing app path is not a directory: $existing"
      [ ! -L "$existing/Contents" ] && [ ! -L "$existing/Contents/Info.plist" ] || fail "Existing app metadata is a symbolic link."
      existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$existing/Contents/Info.plist" 2>/dev/null || true)"
      [ "$existing_id" = io.github.rayeonjin.uncomew ] || fail "Refusing to replace an unrelated app: $existing"
    fi
  done
  stage="$(mktemp -d "$destination_dir/.uncomew-stage.XXXXXX")"
  /usr/bin/ditto "$source_app" "$stage/new.app"
  bash "$validator" "$stage/new.app"

  if [ -e "$current" ]; then
    [ -d "$current" ] || fail "Existing app path is not a directory."
    touch "$stage/had-current"
  fi
  # Never terminate the user's scan. Check immediately before changing app paths.
  if /usr/bin/pgrep -x Uncomew >/dev/null; then
    fail "Quit Uncomew before installing or rolling back, then retry."
  else
    process_status=$?
    [ "$process_status" -eq 1 ] || fail "Could not check whether Uncomew is running."
  fi
  touch "$stage/transaction-started"
  if [ -f "$stage/had-current" ]; then
    mv "$current" "$stage/current.app"
  fi
  mv "$stage/new.app" "$current"
  bash "$validator" "$current"
  if [ -f "$stage/had-current" ]; then
    # The marker precedes rotation so recovery can recognize every rename boundary.
    touch "$stage/rotating"
    if [ -e "$previous" ]; then mv "$previous" "$stage/older.app"; fi
    mv "$stage/current.app" "$previous"
  fi
  touch "$stage/committed"
  printf 'Installed: %s\n' "$current"
  if [ -d "$previous" ]; then printf 'Previous version: %s\n' "$previous"; fi
  printf 'Personal settings are preserved.\n'
)
