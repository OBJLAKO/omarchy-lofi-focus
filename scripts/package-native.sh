#!/usr/bin/env bash
set -euo pipefail

# Explicit developer/CI step; never executed by the plugin at runtime.
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|aarch64) ;;
  *) printf 'Unsupported bundle architecture: %s\n' "$ARCH" >&2; exit 1 ;;
esac
TARGET_DIR=${CARGO_TARGET_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/skylofi-rust-target}
SOURCE_BINARY=${SKYLOFI_NATIVE:-$TARGET_DIR/release/skylofi}
test -x "$SOURCE_BINARY" || {
  printf 'Build the release executable first: scripts/build-native.sh\n' >&2
  exit 1
}
install -Dm755 -- "$SOURCE_BINARY" "$ROOT/bin/linux-$ARCH/skylofi"
cd -- "$ROOT"
sha256sum bin/linux-*/skylofi > bin/SHA256SUMS
printf 'Bundled %s\n' "bin/linux-$ARCH/skylofi"
