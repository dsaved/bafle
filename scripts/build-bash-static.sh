#!/usr/bin/env bash
# build-bash-static.sh - Build Bash with musl libc and static linking
# This script compiles Bash as a statically-linked binary for PRoot compatibility

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/build/static}"
CONFIG_FILE="${CONFIG_FILE:-$PROJECT_ROOT/build-config.json}"
CACHE_DIR="$PROJECT_ROOT/.cache/sources"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get package information from config
get_package_info() {
    local field=$1
    jq -r ".packages.bash.${field}" "$CONFIG_FILE"
}

# Extract Bash source
extract_bash_source() {
    log_info "Extracting Bash source..."
    
    local version=$(get_package_info "version")
    local source_url=$(get_package_info "source")
    local filename=$(basename "$source_url")
    local cache_file="$CACHE_DIR/bash/$filename"
    
    if [ ! -f "$cache_file" ]; then
        log_error "Bash source not found: $cache_file"
        log_error "Please run download-sources.sh first"
        exit 1
    fi
    
    # Extract to build directory
    local extract_dir="$BUILD_DIR/bash-$version"
    
    if [ -d "$extract_dir" ]; then
        log_info "Removing existing source directory..."
        rm -rf "$extract_dir"
    fi
    
    mkdir -p "$BUILD_DIR"
    tar -xzf "$cache_file" -C "$BUILD_DIR"
    
    if [ ! -d "$extract_dir" ]; then
        log_error "Failed to extract Bash source"
        exit 1
    fi
    
    log_success "Bash source extracted to $extract_dir"
}

# Configure Bash for static build
configure_bash() {
    local source_dir=$1
    
    log_info "Configuring Bash for static build..." >&2
    
    cd "$source_dir" || { log_error "Failed to cd to $source_dir" >&2; exit 1; }
    
    # Get build configuration
    local libc=$(jq -r '.staticOptions.libc // "musl"' "$CONFIG_FILE")
    local opt_level=$(jq -r '.staticOptions.optimizationLevel // "Os"' "$CONFIG_FILE")
    
    # Set compiler based on libc choice and cross-compilation
    local cc="gcc"
    local host_flag=""
    
    if [ -n "$CROSS_COMPILE" ]; then
        cc="${CROSS_COMPILE}gcc"
        log_info "Using cross-compiler: $cc"
        
        # Determine host triplet for configure
        case "$TARGET_ARCH" in
            arm64-v8a)
                host_flag="--host=aarch64-linux-gnu"
                ;;
            armeabi-v7a)
                host_flag="--host=arm-linux-gnueabihf"
                ;;
            x86_64)
                host_flag="--host=x86_64-linux-gnu"
                ;;
            x86)
                host_flag="--host=i686-linux-gnu"
                ;;
        esac
    elif [ "$libc" = "musl" ] && command -v musl-gcc &> /dev/null; then
        cc="musl-gcc"
        log_info "Using musl-gcc for compilation"
    else
        log_info "Using gcc for compilation"
    fi
    
    # Build flags for static linking and size optimization
    local cflags="-$opt_level -ffunction-sections -fdata-sections -static"
    local ldflags="-static -s -Wl,--gc-sections"
    
    # Add architecture-specific flags
    if [ -n "$ARCH_CFLAGS" ]; then
        cflags="$cflags $ARCH_CFLAGS"
    fi
    
    log_info "Compiler: $cc"
    log_info "CFLAGS: $cflags"
    log_info "LDFLAGS: $ldflags"
    if [ -n "$host_flag" ]; then
        log_info "Host: $host_flag"
    fi
    
    # Configure with static linking
    # Disable features that might cause issues with static linking
    log_info "Running configure script..."
    
    if ./configure \
        CC="$cc" \
        CFLAGS="$cflags" \
        LDFLAGS="$ldflags" \
        $host_flag \
        --enable-static-link \
        --without-bash-malloc \
        --disable-nls \
        --disable-net-redirections \
        > "$BUILD_DIR/bash-configure.log" 2>&1; then
        log_success "Bash configured successfully"
    else
        log_error "Bash configuration failed"
        log_error "Check configure log: $BUILD_DIR/bash-configure.log"
        tail -50 "$BUILD_DIR/bash-configure.log"
        exit 1
    fi
}

# Build Bash
build_bash() {
    local source_dir=$1
    
    log_info "Building Bash..."
    
    cd "$source_dir"
    
    # Get build configuration
    local libc=$(jq -r '.staticOptions.libc // "musl"' "$CONFIG_FILE")
    local opt_level=$(jq -r '.staticOptions.optimizationLevel // "Os"' "$CONFIG_FILE")
    
    # Set compiler based on libc choice and cross-compilation
    local cc="gcc"
    if [ -n "$CROSS_COMPILE" ]; then
        cc="${CROSS_COMPILE}gcc"
        log_info "Using cross-compiler: $cc"
    elif [ "$libc" = "musl" ] && command -v musl-gcc &> /dev/null; then
        cc="musl-gcc"
    fi
    
    # Build flags
    local cflags="-$opt_level -ffunction-sections -fdata-sections -static"
    local ldflags="-static -s -Wl,--gc-sections"
    
    # Add architecture-specific flags
    if [ -n "$ARCH_CFLAGS" ]; then
        cflags="$cflags $ARCH_CFLAGS"
    fi
    
    # Build with multiple cores
    local num_cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    log_info "Building with $num_cores parallel jobs..."
    
    # Build Bash
    if make -j"$num_cores" \
        CC="$cc" \
        CFLAGS="$cflags" \
        LDFLAGS="$ldflags" \
        > "$BUILD_DIR/bash-build.log" 2>&1; then
        log_success "Bash built successfully"
    else
        log_error "Bash build failed"
        log_error "Check build log: $BUILD_DIR/bash-build.log"
        tail -50 "$BUILD_DIR/bash-build.log"
        exit 1
    fi
    
    # Verify binary exists
    if [ ! -f "bash" ]; then
        log_error "Bash binary not found after build"
        exit 1
    fi
    
    # Strip the binary
    log_info "Stripping debug symbols..."
    strip --strip-all bash 2>/dev/null || strip bash 2>/dev/null || true
    
    local size=$(stat -f%z bash 2>/dev/null || stat -c%s bash 2>/dev/null)
    local size_mb=$(echo "scale=2; $size / 1048576" | bc 2>/dev/null || echo "?")
    log_success "Bash binary size: ${size_mb} MB"
}

# Verify Bash is statically linked
verify_bash() {
    local source_dir=$1
    
    log_info "Verifying Bash is statically linked..."
    
    cd "$source_dir"
    
    if [ ! -f "bash" ]; then
        log_error "Bash binary not found"
        exit 1
    fi
    
    # Check with ldd
    local ldd_output=$(ldd bash 2>&1 || true)
    
    if echo "$ldd_output" | grep -q "not a dynamic executable"; then
        log_success "Bash is statically linked ✓"
    elif echo "$ldd_output" | grep -q "statically linked"; then
        log_success "Bash is statically linked ✓"
    else
        log_error "Bash has dynamic dependencies:"
        echo "$ldd_output"
        exit 1
    fi
    
    # Test basic functionality
    log_info "Testing Bash functionality..."
    if ./bash -c 'echo "Bash test"' > /dev/null 2>&1; then
        log_success "Bash basic functionality test passed ✓"
    else
        log_error "Bash failed basic functionality test"
        exit 1
    fi
    
    # Show version
    local version=$(./bash --version | head -1)
    log_info "Built: $version"
}

# Install Bash to output directory
install_bash() {
    local source_dir=$1
    
    log_info "Installing Bash to output directory..."
    
    cd "$source_dir"
    
    # Copy binary
    mkdir -p "$OUTPUT_DIR/bin"
    cp bash "$OUTPUT_DIR/bin/bash"
    chmod 755 "$OUTPUT_DIR/bin/bash"
    
    log_success "Bash installed to $OUTPUT_DIR/bin/bash"
    
    # Create sh symlink pointing to bash
    log_info "Creating sh symlink..."
    ln -sf bash "$OUTPUT_DIR/bin/sh"
    log_success "Created symlink: sh -> bash"
}

# Main function
main() {
    log_info "Starting Bash static build..."
    echo ""
    
    # Extract source
    extract_bash_source
    local version=$(get_package_info "version")
    local source_dir="$BUILD_DIR/bash-$version"
    echo ""
    
    # Configure
    configure_bash "$source_dir"
    echo ""
    
    # Build
    build_bash "$source_dir"
    echo ""
    
    # Verify
    verify_bash "$source_dir"
    echo ""
    
    # Install
    install_bash "$source_dir"
    echo ""
    
    log_success "Bash static build completed successfully!"
}

# Run main function
main "$@"
