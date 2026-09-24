#!/usr/bin/env bash
# build-busybox-linux-native.sh - Build BusyBox with Linux-native dynamic linking
# This script compiles BusyBox as a dynamically-linked binary using standard Linux linkers

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/build/linux-native}"
SYSROOT_DIR="${SYSROOT_DIR:-$BUILD_DIR/linux-sysroot}"
CONFIG_FILE="${CONFIG_FILE:-$PROJECT_ROOT/build-config.json}"
CACHE_DIR="$PROJECT_ROOT/.cache/sources"
TARGET_ARCH="${TARGET_ARCH:-aarch64}"

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

# Get cross-compilation toolchain prefix
get_toolchain_prefix() {
    local arch=$1
    case "$arch" in
        aarch64)
            echo "aarch64-linux-gnu"
            ;;
        arm)
            echo "arm-linux-gnueabihf"
            ;;
        x86_64)
            echo "x86_64-linux-gnu"
            ;;
        i686)
            echo "i686-linux-gnu"
            ;;
        *)
            log_error "Unknown architecture: $arch"
            exit 1
            ;;
    esac
}

# Get linker path for architecture
get_linker_path() {
    local arch=$1
    case "$arch" in
        aarch64)
            echo "/lib/ld-linux-aarch64.so.1"
            ;;
        arm)
            echo "/lib/ld-linux-armhf.so.3"
            ;;
        x86_64)
            echo "/lib64/ld-linux-x86-64.so.2"
            ;;
        i686)
            echo "/lib/ld-linux.so.2"
            ;;
        *)
            log_error "Unknown architecture: $arch"
            exit 1
            ;;
    esac
}

# Detect host architecture
detect_host_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        armv7l|armv7*)
            echo "arm"
            ;;
        i686|i386)
            echo "i686"
            ;;
        *)
            echo "unknown"
            ;;
    esac
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
    local extract_dir="$BUILD_DIR/busybox-$version-linux-native"
    
    if [ -d "$extract_dir" ]; then
        log_info "Removing existing source directory..."
        rm -rf "$extract_dir"
    fi
    
    mkdir -p "$BUILD_DIR"
    tar -xjf "$cache_file" -C "$BUILD_DIR"
    
    # Rename to include linux-native suffix
    mv "$BUILD_DIR/busybox-$version" "$extract_dir"
    
    if [ ! -d "$extract_dir" ]; then
        log_error "Failed to extract BusyBox source"
        exit 1
    fi
    
    log_success "BusyBox source extracted to $extract_dir"
    echo "$extract_dir"
}

# Configure BusyBox for Linux-native build
configure_busybox() {
    local source_dir=$1
    
    log_info "Configuring BusyBox for Linux-native build..."
    
    cd "$source_dir"
    
    # Start with default configuration
    make defconfig > /dev/null 2>&1
    
    # Disable static linking (we want dynamic)
    log_info "Disabling static linking..."
    sed -i.bak 's/CONFIG_STATIC=y/# CONFIG_STATIC is not set/' .config 2>/dev/null || \
        sed -i '' 's/CONFIG_STATIC=y/# CONFIG_STATIC is not set/' .config 2>/dev/null || true
    
    # Verify static is disabled
    if grep -q "# CONFIG_STATIC is not set" .config; then
        log_success "BusyBox configured for dynamic linking"
    else
        log_warning "Could not verify static linking is disabled"
    fi
}

# Build BusyBox
build_busybox() {
    local source_dir=$1
    
    log_info "Building BusyBox for $TARGET_ARCH..."
    
    cd "$source_dir"
    
    # Determine if cross-compilation is needed
    local host_arch=$(detect_host_arch)
    local cc="gcc"
    local cross_compile=""
    
    if [ "$TARGET_ARCH" != "$host_arch" ]; then
        local toolchain_prefix=$(get_toolchain_prefix "$TARGET_ARCH")
        cross_compile="${toolchain_prefix}-"
        cc="${toolchain_prefix}-gcc"
        
        if ! command -v "$cc" &> /dev/null; then
            log_error "Cross-compiler not found: $cc"
            log_error "Install with: sudo apt-get install gcc-${toolchain_prefix}"
            exit 1
        fi
        
        log_info "Using cross-compiler: $cc"
    else
        log_info "Building for host architecture, no cross-compilation needed"
    fi
    
    # Get RPATH configuration
    local lib_paths=$(jq -r '.linuxNativeOptions.libPaths | join(":")' "$CONFIG_FILE")
    local rpath_flags="-Wl,-rpath,$lib_paths"
    
    # Build flags for dynamic linking with RPATH
    local cflags="-Os -ffunction-sections -fdata-sections"
    local ldflags="$rpath_flags -Wl,--gc-sections"
    
    # Add sysroot if cross-compiling
    if [ "$TARGET_ARCH" != "$host_arch" ]; then
        cflags="$cflags --sysroot=$SYSROOT_DIR"
        ldflags="$ldflags --sysroot=$SYSROOT_DIR"
    fi
    
    log_info "CFLAGS: $cflags"
    log_info "LDFLAGS: $ldflags"
    log_info "RPATH: $lib_paths"
    
    # Build with multiple cores
    local num_cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    log_info "Building with $num_cores parallel jobs..."
    
    # Build BusyBox
    if make -j"$num_cores" \
        CROSS_COMPILE="$cross_compile" \
        CC="$cc" \
        CFLAGS="$cflags" \
        LDFLAGS="$ldflags" \
        EXTRA_CFLAGS="$cflags" \
        EXTRA_LDFLAGS="$ldflags" \
        > "$BUILD_DIR/busybox-linux-native-build.log" 2>&1; then
        log_success "BusyBox built successfully"
    else
        log_error "BusyBox build failed"
        log_error "Check build log: $BUILD_DIR/busybox-linux-native-build.log"
        tail -50 "$BUILD_DIR/busybox-linux-native-build.log"
        exit 1
    fi
    
    # Verify binary exists
    if [ ! -f "busybox" ]; then
        log_error "BusyBox binary not found after build"
        exit 1
    fi
    
    # Strip the binary
    log_info "Stripping debug symbols..."
    local strip_cmd="strip"
    if [ "$TARGET_ARCH" != "$host_arch" ]; then
        strip_cmd="${cross_compile}strip"
    fi
    
    $strip_cmd --strip-all busybox 2>/dev/null || $strip_cmd busybox 2>/dev/null || true
    
    local size=$(stat -f%z busybox 2>/dev/null || stat -c%s busybox 2>/dev/null)
    local size_mb=$(echo "scale=2; $size / 1048576" | bc 2>/dev/null || echo "?")
    log_success "BusyBox binary size: ${size_mb} MB"
}

# Verify BusyBox uses Linux linker
verify_busybox() {
    local source_dir=$1
    
    log_info "Verifying BusyBox uses Linux linker..."
    
    cd "$source_dir"
    
    if [ ! -f "busybox" ]; then
        log_error "BusyBox binary not found"
        exit 1
    fi
    
    # Check interpreter with readelf
    local expected_linker=$(get_linker_path "$TARGET_ARCH")
    local interpreter=$(readelf -l busybox 2>/dev/null | grep "interpreter" | sed 's/.*\[\(.*\)\]/\1/')
    
    if [ -z "$interpreter" ]; then
        log_error "BusyBox appears to be statically linked (no interpreter)"
        exit 1
    fi
    
    if [ "$interpreter" = "$expected_linker" ]; then
        log_success "BusyBox uses Linux linker: $interpreter ✓"
    else
        log_error "BusyBox uses unexpected linker: $interpreter"
        log_error "Expected: $expected_linker"
        exit 1
    fi
    
    # Check RPATH
    local rpath=$(readelf -d busybox 2>/dev/null | grep "RPATH\|RUNPATH" | sed 's/.*\[\(.*\)\]/\1/' || true)
    if [ -n "$rpath" ]; then
        log_success "BusyBox has RPATH: $rpath ✓"
    else
        log_warning "BusyBox has no RPATH set"
    fi
    
    # Show available applets
    local applet_count=$(readelf -s busybox 2>/dev/null | grep -c "FUNC" || echo "unknown")
    log_info "BusyBox binary contains functions: $applet_count"
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
    
    local symlink_count=0
    while IFS= read -r applet; do
        # Skip busybox itself
        [ "$applet" = "busybox" ] && continue
        
        # Create symlink
        ln -sf busybox "$OUTPUT_DIR/bin/$applet" 2>/dev/null || true
        ((symlink_count++))
    done < <(./busybox --list 2>/dev/null)
    
    log_success "Created $symlink_count symlinks for BusyBox applets"
    
    # Create a list of installed applets
    ./busybox --list > "$OUTPUT_DIR/busybox-applets.txt"
    log_info "Applet list saved to $OUTPUT_DIR/busybox-applets.txt"
}

# Main function
main() {
    log_info "Starting BusyBox Linux-native build for $TARGET_ARCH..."
    echo ""
    
    # Extract source
    local source_dir=$(extract_busybox_source)
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
    
    log_success "BusyBox Linux-native build completed successfully!"
}

# Run main function
main "$@"
