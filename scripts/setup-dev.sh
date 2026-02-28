#!/usr/bin/env bash
# setup-dev.sh -- One-command development environment setup for Canopy.
#
# Usage:
#   ./scripts/setup-dev.sh
#
# This script installs the correct GHC version via Stack, builds all
# packages, and runs the full test suite. It is safe to run repeatedly;
# Stack will skip steps that are already complete.

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly NC='\033[0m'

info() { printf "${GREEN}[setup]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[setup]${NC} %s\n" "$1"; }
fail() { printf "${RED}[setup]${NC} %s\n" "$1"; exit 1; }

# -- Prerequisites ----------------------------------------------------------

check_command() {
    if ! command -v "$1" &>/dev/null; then
        fail "$1 is required but not found. $2"
    fi
}

info "Checking prerequisites..."
check_command stack "Install from https://docs.haskellstack.org/"
check_command node  "Install Node.js >= 18 from https://nodejs.org/"

STACK_VERSION=$(stack --numeric-version 2>/dev/null || echo "0")
info "  stack $STACK_VERSION"

NODE_VERSION=$(node --version 2>/dev/null || echo "v0")
info "  node  $NODE_VERSION"

# -- GHC Setup ---------------------------------------------------------------

info "Setting up GHC (this may take a few minutes on first run)..."
stack setup

# -- Build -------------------------------------------------------------------

info "Building all packages..."
stack build --fast --pedantic --ghc-options "-j +RTS -A128m -n2m -RTS" 2>&1 | tail -5

# -- Test --------------------------------------------------------------------

info "Running test suite..."
if stack test --fast canopy:canopy-test 2>&1 | tail -10; then
    info "All tests passed."
else
    warn "Some tests failed. Check the output above for details."
    exit 1
fi

# -- Optional tools ----------------------------------------------------------

if command -v hlint &>/dev/null; then
    info "  hlint $(hlint --numeric-version 2>/dev/null)"
else
    warn "hlint not found. Install with: stack install hlint"
fi

if command -v ormolu &>/dev/null; then
    info "  ormolu $(ormolu --version 2>/dev/null | head -1)"
else
    warn "ormolu not found. Install with: stack install ormolu"
fi

# -- Done --------------------------------------------------------------------

printf "\n"
info "Development environment is ready."
info ""
info "Useful commands:"
info "  make build              Build all packages"
info "  make test               Run all tests"
info "  make test-match PATTERN=\"Parser\"  Run matching tests"
info "  make lint               Run hlint"
info "  make format             Format with ormolu"
info "  make bench              Run benchmarks"
info ""
info "See CONTRIBUTING.md for the full development workflow."
