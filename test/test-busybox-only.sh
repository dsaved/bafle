#!/usr/bin/env bash

# Test BusyBox Build Only
# Quick test to isolate and fix BusyBox build issues

set -e
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TEST_VERSION="2.0.0"
TEST_ARCH="${1:-arm64-v8a}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check Docker
if ! command -v docker &> /dev/null; then
    log_error "Docker not installed"
    exit 1
fi

if ! docker info &> /dev/null; then
    log_error "Docker daemon not running"
    exit 1
fi

log_info "=========================================="
log_info "BusyBox Build Test"
log_info "=========================================="
log_info "Architecture: $TEST_ARCH"
log_info "Version: $TEST_VERSION"
echo ""

cd "$PROJECT_ROOT"

# Cleanup previous build
rm -rf build/busybox-* build/static-${TEST_ARCH}

log_info "Running BusyBox build in Docker..."
echo ""

# Determine Docker platform - use amd64 for x86/x86_64 to get multilib support
ARCH_PLATFORM="linux/amd64"
if [ "$TEST_ARCH" = "arm64-v8a" ]; then
  ARCH_PLATFORM="linux/arm64"
elif [ "$TEST_ARCH" = "armeabi-v7a" ]; then
  ARCH_PLATFORM="linux/arm/v7"
fi

log_info "Using Docker platform: $ARCH_PLATFORM"

docker run --rm \
  --platform "$ARCH_PLATFORM" \
  -v $(pwd):/workspace \
  -w /workspace \
  -e TARGET_ARCH="$TEST_ARCH" \
  -e VERSION="$TEST_VERSION" \
  -e FORCE_UNSAFE_CONFIGURE=1 \
  ubuntu:22.04 \
  bash -c '
    set -e
    
    echo "Installing dependencies..."
    apt-get update -qq
    apt-get install -y -qq \
      build-essential \
      wget curl make file bzip2 xz-utils jq
    
    # Install arch-specific cross-compiler
    if [ "$TARGET_ARCH" = "arm64-v8a" ]; then
      apt-get install -y -qq gcc-aarch64-linux-gnu g++-aarch64-linux-gnu libc6-dev-arm64-cross
    elif [ "$TARGET_ARCH" = "armeabi-v7a" ]; then
      apt-get install -y -qq gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf libc6-dev-armhf-cross
    elif [ "$TARGET_ARCH" = "x86" ]; then
      apt-get install -y -qq gcc-multilib g++-multilib libc6-dev-i386
    fi
    
    echo ""
    echo "Downloading BusyBox source..."
    mkdir -p .cache/sources/busybox
    cd .cache/sources/busybox
    
    if [ ! -f busybox-1.36.1.tar.bz2 ]; then
      wget -q https://busybox.net/downloads/busybox-1.36.1.tar.bz2
    fi
    
    cd /workspace
    
    echo ""
    echo "Building BusyBox..."
    export BUILD_DIR=/workspace/build
    export OUTPUT_DIR=/workspace/build/static-${TARGET_ARCH}
    export SOURCE_DIR=/workspace/.cache/sources
    export CONFIG_FILE=/workspace/build-config.json
    
    # Set architecture-specific flags
    if [ "$TARGET_ARCH" = "x86" ]; then
      export ARCH_CFLAGS="-march=i686 -m32"
    elif [ "$TARGET_ARCH" = "x86_64" ]; then
      export ARCH_CFLAGS="-march=x86-64"
    elif [ "$TARGET_ARCH" = "arm64-v8a" ]; then
      export CROSS_COMPILE="aarch64-linux-gnu-"
      export ARCH_CFLAGS="-march=armv8-a"
    elif [ "$TARGET_ARCH" = "armeabi-v7a" ]; then
      export CROSS_COMPILE="arm-linux-gnueabihf-"
      export ARCH_CFLAGS="-march=armv7-a -mfloat-abi=hard -mfpu=neon"
    fi
    
    bash scripts/build-busybox-static.sh
  '

echo ""
log_info "Checking build output..."

BUILD_DIR="build/static-${TEST_ARCH}"
if [ ! -d "$BUILD_DIR" ]; then
    log_error "Build directory not found: $BUILD_DIR"
    exit 1
fi

if [ ! -f "$BUILD_DIR/bin/busybox" ]; then
    log_error "BusyBox binary not found"
    exit 1
fi

log_success "BusyBox binary exists"

# Check symlinks
SYMLINK_COUNT=$(find "$BUILD_DIR/bin" -type l | wc -l | tr -d ' ')
log_info "Symlinks created: $SYMLINK_COUNT"

if [ $SYMLINK_COUNT -eq 0 ]; then
    log_error "No symlinks created!"
    exit 1
fi

log_success "Symlinks created successfully"

# Check applet list
if [ -f "$BUILD_DIR/busybox-applets.txt" ]; then
    APPLET_COUNT=$(wc -l < "$BUILD_DIR/busybox-applets.txt" | tr -d ' ')
    log_info "Applets listed: $APPLET_COUNT"
    log_success "Applet list exists"
else
    log_error "Applet list not found"
    exit 1
fi

# Test a few symlinks
log_info "Testing symlinks..."
for cmd in ls cat grep; do
    if [ -L "$BUILD_DIR/bin/$cmd" ]; then
        log_info "  ✓ $cmd -> $(readlink "$BUILD_DIR/bin/$cmd")"
    else
        log_error "  ✗ $cmd symlink missing"
    fi
done

echo ""
log_success "BusyBox build test passed!"
log_info "Binary: $BUILD_DIR/bin/busybox"
log_info "Symlinks: $SYMLINK_COUNT"
log_info "Applets: $APPLET_COUNT"
