#!/usr/bin/env bash

# Test Static Build with Docker (Local)
# Simulates the GitHub Actions Docker build locally

set -e
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test configuration
TEST_VERSION="2.0.0"
TEST_MODE="static"
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
    log_error "Docker is not installed"
    log_error "Install Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    log_error "Docker daemon is not running"
    log_error "Please start Docker Desktop or Docker daemon"
    log_error ""
    log_error "macOS: Open Docker Desktop application"
    log_error "Linux: sudo systemctl start docker"
    exit 1
fi

log_info "=========================================="
log_info "Static Build Test (Docker)"
log_info "=========================================="
log_info "Architecture: $TEST_ARCH"
log_info "Version: $TEST_VERSION"
log_info "Mode: $TEST_MODE"
echo ""

cd "$PROJECT_ROOT"

log_info "Running Docker build (this may take several minutes)..."
echo ""

# Determine Docker platform based on target architecture
DOCKER_PLATFORM="linux/amd64"  # Default to x86_64 for most builds
if [ "$TEST_ARCH" = "arm64-v8a" ]; then
    DOCKER_PLATFORM="linux/arm64"
elif [ "$TEST_ARCH" = "armeabi-v7a" ]; then
    DOCKER_PLATFORM="linux/arm/v7"
fi

log_info "Using Docker platform: $DOCKER_PLATFORM"
echo ""

docker run --rm \
  --platform "$DOCKER_PLATFORM" \
  -v $(pwd):/workspace \
  -w /workspace \
  -e BUILD_MODE="$TEST_MODE" \
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
    elif [ "$TARGET_ARCH" = "x86_64" ]; then
      apt-get install -y -qq gcc g++
    fi
    
    echo ""
    echo "Running build..."
    ./scripts/build-static.sh --arch "$TARGET_ARCH" --version "$VERSION"
  '

echo ""
log_info "Checking build output..."

BUILD_DIR="build/static-${TEST_ARCH}"
if [ ! -d "$BUILD_DIR" ]; then
    log_error "Build directory not found: $BUILD_DIR"
    exit 1
fi

log_success "Build directory exists: $BUILD_DIR"

# Check for binaries
if [ -d "$BUILD_DIR/bin" ]; then
    BIN_COUNT=$(ls -1 "$BUILD_DIR/bin" 2>/dev/null | wc -l | tr -d ' ')
    log_info "Binaries found: $BIN_COUNT"
    
    if [ $BIN_COUNT -gt 0 ]; then
        log_info "Sample binaries:"
        ls -1 "$BUILD_DIR/bin" | head -5 | while read bin; do
            echo "  - $bin"
        done
    fi
fi

# Check build report
if [ -f "$BUILD_DIR/build-report.txt" ]; then
    log_success "Build report exists"
    echo ""
    log_info "Build report:"
    cat "$BUILD_DIR/build-report.txt"
fi

echo ""
log_success "Docker build test completed!"
log_info "Build output: $BUILD_DIR"
