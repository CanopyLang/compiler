#!/usr/bin/env bash
# check-package-dag.sh -- Verify the Canopy package dependency DAG.
#
# The package layer ordering is:
#
#   canopy-core       (foundation -- no canopy dependencies)
#   canopy-query      (depends on: canopy-core)
#   canopy-driver     (depends on: canopy-core, canopy-query)
#   canopy-builder    (depends on: canopy-core, canopy-query, canopy-driver)
#   canopy-terminal   (depends on: canopy-core, canopy-query, canopy-driver, canopy-builder)
#
# This script exits non-zero if any package violates the DAG by
# depending on a package above it in the ordering.
#
# Usage:
#   bash scripts/check-package-dag.sh
#
# @since 0.19.2

set -euo pipefail

FAIL=0

# check_no_dep PKG FORBIDDEN...
#   Fail if PKG's .cabal file has any FORBIDDEN package in build-depends.
check_no_dep() {
  local pkg="$1"; shift
  local cabal="packages/$pkg/$pkg.cabal"

  if [ ! -f "$cabal" ]; then
    echo "WARNING: $cabal not found, skipping"
    return
  fi

  for forbidden in "$@"; do
    if grep -qE "^\s*,\s*$forbidden\b" "$cabal"; then
      echo "VIOLATION: $pkg depends on $forbidden (forbidden by DAG)"
      FAIL=1
    fi
  done
}

echo "Checking package dependency DAG..."
echo ""

# canopy-core is the foundation: must not depend on ANY other canopy package
check_no_dep canopy-core canopy-query canopy-driver canopy-builder canopy-terminal

# canopy-query may depend on canopy-core only
check_no_dep canopy-query canopy-driver canopy-builder canopy-terminal

# canopy-driver may depend on canopy-core, canopy-query only
check_no_dep canopy-driver canopy-builder canopy-terminal

# canopy-builder may depend on canopy-core, canopy-query, canopy-driver only
check_no_dep canopy-builder canopy-terminal

# canopy-terminal is the top layer: no restrictions

if [ "$FAIL" -eq 0 ]; then
  echo "Package DAG: OK"
  echo ""
  echo "  canopy-core        (no canopy deps)"
  echo "  canopy-query       -> canopy-core"
  echo "  canopy-driver      -> canopy-core, canopy-query"
  echo "  canopy-builder     -> canopy-core, canopy-query, canopy-driver"
  echo "  canopy-terminal    -> canopy-core, canopy-query, canopy-driver, canopy-builder"
  exit 0
else
  echo ""
  echo "Fix the above violations to restore the package DAG."
  exit 1
fi
