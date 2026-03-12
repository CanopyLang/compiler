#!/bin/sh
# Canopy installer script
# Usage: curl -fsSL https://canopy-lang.org/install.sh | sh
#    or: sh install.sh [--version VERSION] [--install-dir DIR] [--modify-path]
#
# Installs a pre-built Canopy binary from GitHub Releases.

set -eu

REPO="canopy-lang/canopy"
DEFAULT_INSTALL_DIR="$HOME/.canopy/bin"

# --- Argument parsing ---

VERSION=""
INSTALL_DIR="$DEFAULT_INSTALL_DIR"
MODIFY_PATH=false

while [ $# -gt 0 ]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --install-dir)
      INSTALL_DIR="$2"
      shift 2
      ;;
    --modify-path)
      MODIFY_PATH=true
      shift
      ;;
    --help|-h)
      echo "Usage: install.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --version VERSION    Install a specific version (default: latest)"
      echo "  --install-dir DIR    Install to DIR (default: ~/.canopy/bin)"
      echo "  --modify-path        Add install dir to PATH in shell config"
      echo "  --help               Show this help"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# --- Platform detection ---

detect_os() {
  case "$(uname -s)" in
    Linux*)  echo "linux" ;;
    Darwin*) echo "darwin" ;;
    *)
      echo "Error: Unsupported operating system: $(uname -s)" >&2
      echo "For Windows, use installers/install.ps1 instead." >&2
      exit 1
      ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)  echo "x86_64" ;;
    arm64|aarch64) echo "aarch64" ;;
    *)
      echo "Error: Unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

# --- Version resolution ---

get_latest_version() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
      | grep '"tag_name"' \
      | sed 's/.*"tag_name": *"v\([^"]*\)".*/\1/'
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "https://api.github.com/repos/$REPO/releases/latest" \
      | grep '"tag_name"' \
      | sed 's/.*"tag_name": *"v\([^"]*\)".*/\1/'
  else
    echo "Error: curl or wget is required" >&2
    exit 1
  fi
}

# --- Download helpers ---

download() {
  url="$1"
  output="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$output"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$url" -O "$output"
  fi
}

# --- Checksum verification ---

verify_checksum() {
  file="$1"
  expected="$2"

  if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$file" | cut -d' ' -f1)
  elif command -v shasum >/dev/null 2>&1; then
    actual=$(shasum -a 256 "$file" | cut -d' ' -f1)
  else
    echo "Warning: No sha256sum or shasum found, skipping checksum verification" >&2
    return 0
  fi

  if [ "$actual" != "$expected" ]; then
    echo "Error: Checksum verification failed" >&2
    echo "  Expected: $expected" >&2
    echo "  Actual:   $actual" >&2
    exit 1
  fi
}

# --- PATH modification ---

add_to_path() {
  dir="$1"
  path_line="export PATH=\"$dir:\$PATH\""

  for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [ -f "$rc" ]; then
      if ! grep -qF "$dir" "$rc" 2>/dev/null; then
        echo "" >> "$rc"
        echo "# Added by Canopy installer" >> "$rc"
        echo "$path_line" >> "$rc"
        echo "  Added to $rc"
      fi
    fi
  done
}

# --- Main ---

main() {
  OS=$(detect_os)
  ARCH=$(detect_arch)
  PLATFORM="${OS}-${ARCH}"

  echo "Canopy Installer"
  echo "================"
  echo ""
  echo "Platform: $PLATFORM"

  if [ -z "$VERSION" ]; then
    echo "Resolving latest version..."
    VERSION=$(get_latest_version)
    if [ -z "$VERSION" ]; then
      echo "Error: Could not determine latest version" >&2
      exit 1
    fi
  fi

  echo "Version:  $VERSION"
  echo "Install:  $INSTALL_DIR"
  echo ""

  ARCHIVE="canopy-${VERSION}-${PLATFORM}.tar.gz"
  BASE_URL="https://github.com/$REPO/releases/download/v${VERSION}"
  ARCHIVE_URL="${BASE_URL}/${ARCHIVE}"
  CHECKSUM_URL="${BASE_URL}/SHA256SUMS.txt"

  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT

  echo "Downloading $ARCHIVE..."
  download "$ARCHIVE_URL" "$TMPDIR/$ARCHIVE"

  echo "Downloading checksums..."
  download "$CHECKSUM_URL" "$TMPDIR/SHA256SUMS.txt"

  echo "Verifying checksum..."
  EXPECTED=$(grep "$ARCHIVE" "$TMPDIR/SHA256SUMS.txt" | cut -d' ' -f1)
  if [ -n "$EXPECTED" ]; then
    verify_checksum "$TMPDIR/$ARCHIVE" "$EXPECTED"
    echo "  Checksum verified."
  else
    echo "Warning: Archive not found in SHA256SUMS.txt, skipping verification" >&2
  fi

  echo "Extracting..."
  mkdir -p "$INSTALL_DIR"
  tar -xzf "$TMPDIR/$ARCHIVE" -C "$INSTALL_DIR"
  chmod +x "$INSTALL_DIR/canopy"

  echo ""
  echo "Canopy $VERSION installed to $INSTALL_DIR/canopy"

  if [ "$MODIFY_PATH" = true ]; then
    echo ""
    echo "Updating PATH..."
    add_to_path "$INSTALL_DIR"
  fi

  # Check if already on PATH
  case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
      echo ""
      echo "To add Canopy to your PATH, run:"
      echo ""
      echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
      echo ""
      echo "Or re-run with --modify-path to update your shell config automatically."
      ;;
  esac

  echo ""
  echo "Run 'canopy --help' to get started."
}

main
