#!/bin/bash
set -euo pipefail
[ "$(uname -s)" = Darwin ] || { echo 'Uncomew requires macOS.' >&2; exit 1; }
VERSION="$(sw_vers -productVersion)"
[ "${VERSION%%.*}" -ge 13 ] || { echo 'Uncomew requires macOS 13 or newer.' >&2; exit 1; }
if ! xcrun --find swift >/dev/null 2>&1 || ! xcrun --show-sdk-path >/dev/null 2>&1; then
  echo 'Install Apple Command Line Tools: xcode-select --install' >&2
  exit 1
fi
