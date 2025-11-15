#!/usr/bin/env bash

# build-coreutils-static.sh - Build GNU Coreutils statically
# Produces statically-linked coreutils binaries

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/build/static}"
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

# Configure for static build
log_info "Configuring Coreutils for static build..."
./configure \
  --prefix=/usr \
  --enable-static \
  --disable-shared \
  --enable-single-binary=symlinks \
  LDFLAGS="-static" \
  CFLAGS="-Os -ffunction-sections -fdata-sections" \
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
