#!/usr/bin/env bash

# build-coreutils-linux-native.sh - Build GNU Coreutils for Linux-native
# Produces dynamically-linked coreutils binaries with Linux linker

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/build/linux-native}"
SOURCE_DIR="${SOURCE_DIR:-$PROJECT_ROOT/.cache/sources}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Extract source
log_info "Extracting Coreutils source..."
cd "$BUILD_DIR"
rm -rf coreutils-9.4
tar -xf "$SOURCE_DIR/coreutils-9.4.tar.xz"
log_success "Coreutils source extracted to $BUILD_DIR/coreutils-9.4"

cd coreutils-9.4

# Configure for dynamic build
log_info "Configuring Coreutils for Linux-native build..."
./configure \
  --prefix=/usr \
  --enable-single-binary=symlinks \
  CFLAGS="-Os" \
  || { log_error "Configuration failed"; exit 1; }

# Build
log_info "Building Coreutils..."
make -j$(nproc) || { log_error "Build failed"; exit 1; }

# Install to output directory
log_info "Installing Coreutils to $OUTPUT_DIR..."
mkdir -p "$OUTPUT_DIR/bin"
make install DESTDIR="$OUTPUT_DIR" || { log_error "Installation failed"; exit 1; }

# Move binaries from usr/bin to bin
if [ -d "$OUTPUT_DIR/usr/bin" ]; then
    cp -r "$OUTPUT_DIR/usr/bin"/* "$OUTPUT_DIR/bin/" 2>/dev/null || true
fi

log_success "Coreutils built successfully"
