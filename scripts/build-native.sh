#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-"${XDG_CACHE_HOME:-$HOME/.cache}/skylofi-rust-target"}
case "$CARGO_TARGET_DIR" in /*) ;; *) CARGO_TARGET_DIR="$PWD/$CARGO_TARGET_DIR" ;; esac
if ! command -v cargo >/dev/null 2>&1; then
  toolchain="$HOME/.local/share/skylofi-rust/bin"
  if [ ! -x "$toolchain/cargo" ] || [ ! -x "$toolchain/rustc" ]; then
    printf '%s\n' 'Cargo is missing. Install Rust 1.99.0 or add its bin directory to PATH.' >&2
    exit 1
  fi
  export PATH="$toolchain:$PATH"
fi
# rustup chooses rust-toolchain.toml from cwd, not --manifest-path.
cd "$root/native"
cargo build --locked --release
printf '%s\n' "$CARGO_TARGET_DIR/release/skylofi"
