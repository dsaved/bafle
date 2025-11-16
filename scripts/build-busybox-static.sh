#!/usr/bin/env bash
# build-busybox-static.sh - Build BusyBox with musl libc and static linking
# This script compiles BusyBox as a statically-linked binary for PRoot compatibility

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
    jq -r ".packages.busybox.${field}" "$CONFIG_FILE"
}

# Extract BusyBox source
extract_busybox_source() {
    log_info "Extracting BusyBox source..."
    
    local version=$(get_package_info "version")
    local source_url=$(get_package_info "source")
    local filename=$(basename "$source_url")
    local cache_file="$CACHE_DIR/busybox/$filename"
    
    if [ ! -f "$cache_file" ]; then
        log_error "BusyBox source not found: $cache_file"
        log_error "Please run download-sources.sh first"
        exit 1
    fi
    
    # Extract to build directory
    local extract_dir="$BUILD_DIR/busybox-$version"
    
    if [ -d "$extract_dir" ]; then
        log_info "Removing existing source directory..."
        rm -rf "$extract_dir"
    fi
    
    mkdir -p "$BUILD_DIR"
    tar -xjf "$cache_file" -C "$BUILD_DIR"
    
    if [ ! -d "$extract_dir" ]; then
        log_error "Failed to extract BusyBox source"
        exit 1
    fi
    
    log_success "BusyBox source extracted to $extract_dir"
}

# Configure BusyBox for static build
configure_busybox() {
    local source_dir=$1
    
    log_info "Configuring BusyBox for static build..."
    
    cd "$source_dir"
    
    # Start with default configuration
    make defconfig > /dev/null 2>&1
    
    # Enable static linking in configuration
    log_info "Enabling static linking..."
    sed -i.bak 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config || \
        sed -i '' 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config 2>/dev/null || true
    
    # Disable features that might cause issues with static linking
    log_info "Adjusting configuration for static build..."
    
    # Disable features that require dynamic loading
    sed -i.bak 's/CONFIG_FEATURE_SEAMLESS_LZMA=y/# CONFIG_FEATURE_SEAMLESS_LZMA is not set/' .config 2>/dev/null || \
        sed -i '' 's/CONFIG_FEATURE_SEAMLESS_LZMA=y/# CONFIG_FEATURE_SEAMLESS_LZMA is not set/' .config 2>/dev/null || true
    
    # Verify static is enabled
    if grep -q "CONFIG_STATIC=y" .config; then
        log_success "BusyBox configured for static linking"
    else
        log_error "Failed to enable static linking in configuration"
        exit 1
    fi
}

# Build BusyBox
build_busybox() {
    local source_dir=$1
    
    log_info "Building BusyBox..."
    
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
    
    # Build with multiple cores
    local num_cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    log_info "Building with $num_cores parallel jobs..."
    
    # Build BusyBox
    if make -j"$num_cores" \
        CC="$cc" \
        CFLAGS="$cflags" \
        LDFLAGS="$ldflags" \
        EXTRA_CFLAGS="$cflags" \
        EXTRA_LDFLAGS="$ldflags" \
        > "$BUILD_DIR/busybox-build.log" 2>&1; then
        log_success "BusyBox built successfully"
    else
        log_error "BusyBox build failed"
        log_error "Check build log: $BUILD_DIR/busybox-build.log"
        tail -50 "$BUILD_DIR/busybox-build.log"
        exit 1
    fi
    
    # Verify binary exists
    if [ ! -f "busybox" ]; then
        log_error "BusyBox binary not found after build"
        exit 1
    fi
    
    # Strip the binary
    log_info "Stripping debug symbols..."
    strip --strip-all busybox 2>/dev/null || strip busybox 2>/dev/null || true
    
    local size=$(stat -f%z busybox 2>/dev/null || stat -c%s busybox 2>/dev/null)
    local size_mb=$(echo "scale=2; $size / 1048576" | bc 2>/dev/null || echo "?")
    log_success "BusyBox binary size: ${size_mb} MB"
}

# Verify BusyBox is statically linked
verify_busybox() {
    local source_dir=$1
    
    log_info "Verifying BusyBox is statically linked..."
    
    cd "$source_dir"
    
    if [ ! -f "busybox" ]; then
        log_error "BusyBox binary not found"
        exit 1
    fi
    
    # Check with ldd
    local ldd_output=$(ldd busybox 2>&1 || true)
    
    if echo "$ldd_output" | grep -q "not a dynamic executable"; then
        log_success "BusyBox is statically linked ✓"
    elif echo "$ldd_output" | grep -q "statically linked"; then
        log_success "BusyBox is statically linked ✓"
    else
        log_error "BusyBox has dynamic dependencies:"
        echo "$ldd_output"
        exit 1
    fi
    
    # Test basic functionality
    log_info "Testing BusyBox functionality..."
    if ./busybox echo "BusyBox test" > /dev/null 2>&1; then
        log_success "BusyBox basic functionality test passed ✓"
    else
        log_error "BusyBox failed basic functionality test"
        exit 1
    fi
    
    # Show available applets
    local applet_count=$(./busybox --list 2>/dev/null | wc -l | tr -d ' ')
    log_info "BusyBox provides $applet_count applets"
}

# Install BusyBox to output directory
install_busybox() {
    local source_dir=$1
    
    log_info "Installing BusyBox to output directory..."
    
    cd "$source_dir"
    
    # Copy main binary
    mkdir -p "$OUTPUT_DIR/bin"
    cp busybox "$OUTPUT_DIR/bin/busybox"
    chmod 755 "$OUTPUT_DIR/bin/busybox"
    
    log_success "BusyBox installed to $OUTPUT_DIR/bin/busybox"
    
    # Create symlinks for all applets
    log_info "Creating symlinks for BusyBox applets..."
    
    # Get list of applets
    "$OUTPUT_DIR/bin/busybox" --list > "$OUTPUT_DIR/busybox-applets.txt" 2>/dev/null || {
        log_error "Failed to get BusyBox applet list"
        return 1
    }
    
    local symlink_count=0
    while IFS= read -r applet; do
        # Skip busybox itself
        [ "$applet" = "busybox" ] && continue
        
        # Create symlink
        ln -sf busybox "$OUTPUT_DIR/bin/$applet" 2>/dev/null || true
        ((symlink_count++))
    done < "$OUTPUT_DIR/busybox-applets.txt"
    
    log_success "Created $symlink_count symlinks for BusyBox applets"
    log_info "Applet list saved to $OUTPUT_DIR/busybox-applets.txt"
}

# Main function
main() {
    log_info "Starting BusyBox static build..."
    echo ""
    
    # Extract source
    extract_busybox_source
    local version=$(get_package_info "version")
    local source_dir="$BUILD_DIR/busybox-$version"
    echo ""
    
    # Configure
    configure_busybox "$source_dir"
    echo ""
    
    # Build
    build_busybox "$source_dir"
    echo ""
    
    # Verify
    verify_busybox "$source_dir"
    echo ""
    
    # Install
    install_busybox "$source_dir"
    echo ""
    
    log_success "BusyBox static build completed successfully!"
}

# Run main function
main "$@"
