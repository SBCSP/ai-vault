#!/usr/bin/env bash
# ============================================================
# setup_lance.sh — One-time setup for the LanceDB Rust bridge
# Run from the project root: bash scripts/setup_lance.sh
# ============================================================
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── 1. Rust toolchain ───────────────────────────────────────
if ! command -v cargo &>/dev/null; then
  die "Rust not found. Install via: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
fi

RUST_VERSION=$(rustc --version)
info "Rust: $RUST_VERSION"

# macOS: need the aarch64 and x86_64 targets for universal binary
rustup target add aarch64-apple-darwin x86_64-apple-darwin 2>/dev/null || true

# ── 2. flutter_rust_bridge_codegen ─────────────────────────
if ! command -v flutter_rust_bridge_codegen &>/dev/null; then
  info "Installing flutter_rust_bridge_codegen…"
  cargo install flutter_rust_bridge_codegen
fi

FRB_VERSION=$(flutter_rust_bridge_codegen --version 2>/dev/null || echo "unknown")
info "flutter_rust_bridge_codegen: $FRB_VERSION"

# ── 3. Flutter dependencies ─────────────────────────────────
info "Running flutter pub get…"
flutter pub get

# ── 4. Generate Dart bindings ───────────────────────────────
info "Generating Dart bindings from Rust source…"
dart run flutter_rust_bridge_codegen generate

info "Bindings written to lib/src/rust/"

# ── 5. Test compile the Rust crate ─────────────────────────
info "Checking Rust crate compiles…"
pushd rust > /dev/null
cargo check --quiet
popd > /dev/null

echo ""
echo -e "${BOLD}${GREEN}Setup complete!${NC}"
echo ""
echo "Next steps:"
echo "  flutter build macos"
echo ""
echo "The app will now use LanceDB for vector storage."
echo "Open Settings → Vector Database to verify and build the search index."
