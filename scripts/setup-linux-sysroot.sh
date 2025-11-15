#!/usr/bin/env bash
# setup-linux-sysroot.sh - Create sysroot with Linux dynamic linker and libraries
# This script sets up a Linux sysroot for cross-compilation with standard Linux linkers

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build}"
SYSROOT_DIR="${SYSROOT_DIR:-$BUILD_DIR/linux-sysroot}"
CONFIG_FILE="${CONFIG_FILE:-$PROJECT_ROOT/build-config.json}"

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
            log_error "Unsupported host architecture: $arch"
            exit 1
            ;;
    esac
}

# Map Android architecture to Linux architecture
map_android_to_linux_arch() {
    local android_arch=$1
    case "$android_arch" in
        arm64-v8a)
            echo "aarch64"
            ;;
        armeabi-v7a)
            echo "arm"
            ;;
        x86_64)
            echo "x86_64"
            ;;
        x86)
            echo "i686"
            ;;
        *)
            log_error "Unknown Android architecture: $android_arch"
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

# Check if cross-compilation toolchain is available
check_toolchain() {
    local arch=$1
    local host_arch=$(detect_host_arch)
    
    # If building for host architecture, no cross-compilation needed
    if [ "$arch" = "$host_arch" ]; then
        log_info "Building for host architecture ($arch), no cross-compilation needed"
        return 0
    fi
    
    local toolchain_prefix=$(get_toolchain_prefix "$arch")
    local gcc_cmd="${toolchain_prefix}-gcc"
    
    if command -v "$gcc_cmd" &> /dev/null; then
        log_success "Cross-compilation toolchain found: $gcc_cmd"
        return 0
    else
        log_warning "Cross-compilation toolchain not found: $gcc_cmd"
        log_info "Install with: sudo apt-get install gcc-${toolchain_prefix}"
        return 1
    fi
}

# Create sysroot directory structure
create_sysroot_structure() {
    local arch=$1
    
    log_info "Creating sysroot directory structure for $arch..."
    
    # Create directories
    mkdir -p "$SYSROOT_DIR/lib"
    mkdir -p "$SYSROOT_DIR/usr/lib"
    mkdir -p "$SYSROOT_DIR/usr/include"
    
    # Create lib64 symlink for x86_64
    if [ "$arch" = "x86_64" ]; then
        ln -sf lib "$SYSROOT_DIR/lib64"
        log_info "Created lib64 -> lib symlink"
    fi
    
    log_success "Sysroot directory structure created"
}

# Copy system libraries to sysroot
copy_system_libraries() {
    local arch=$1
    local host_arch=$(detect_host_arch)
    
    log_info "Copying system libraries to sysroot..."
    
    # Determine source library paths
    local lib_paths=()
    
    if [ "$arch" = "$host_arch" ]; then
        # Use host system libraries
        lib_paths+=("/lib" "/lib64" "/usr/lib")
    else
        # Use cross-compilation toolchain libraries
        local toolchain_prefix=$(get_toolchain_prefix "$arch")
        local toolchain_base="/usr/${toolchain_prefix}"
        
        if [ -d "$toolchain_base" ]; then
            lib_paths+=("$toolchain_base/lib")
        fi
    fi
    
    # Required libraries
    local required_libs=(
        "libc.so.6"
        "libm.so.6"
        "libdl.so.2"
        "libpthread.so.0"
        "librt.so.1"
        "libresolv.so.2"
    )
    
    # Copy dynamic linker
    local linker_path=$(get_linker_path "$arch")
    local linker_name=$(basename "$linker_path")
    local linker_found=false
    
    for lib_path in "${lib_paths[@]}"; do
        if [ -f "$lib_path/$linker_name" ]; then
            cp -L "$lib_path/$linker_name" "$SYSROOT_DIR/lib/"
            log_success "Copied dynamic linker: $linker_name"
            linker_found=true
            break
        fi
    done
    
    if [ "$linker_found" = false ]; then
        log_error "Dynamic linker not found: $linker_name"
        log_error "Searched in: ${lib_paths[*]}"
        return 1
    fi
    
    # Copy required libraries
    local copied_count=0
    for lib in "${required_libs[@]}"; do
        local lib_found=false
        
        for lib_path in "${lib_paths[@]}"; do
            if [ -f "$lib_path/$lib" ]; then
                cp -L "$lib_path/$lib" "$SYSROOT_DIR/lib/"
                ((copied_count++))
                lib_found=true
                break
            fi
        done
        
        if [ "$lib_found" = false ]; then
            log_warning "Library not found: $lib (may not be required)"
        fi
    done
    
    log_success "Copied $copied_count libraries to sysroot"
}

# Verify sysroot setup
verify_sysroot() {
    local arch=$1
    
    log_info "Verifying sysroot setup..."
    
    local errors=()
    
    # Check dynamic linker exists
    local linker_path=$(get_linker_path "$arch")
    local linker_name=$(basename "$linker_path")
    
    if [ ! -f "$SYSROOT_DIR/lib/$linker_name" ]; then
        errors+=("Dynamic linker not found: $linker_name")
    fi
    
    # Check essential libraries
    local essential_libs=("libc.so.6")
    for lib in "${essential_libs[@]}"; do
        if [ ! -f "$SYSROOT_DIR/lib/$lib" ]; then
            errors+=("Essential library not found: $lib")
        fi
    done
    
    # Report results
    if [ ${#errors[@]} -gt 0 ]; then
        log_error "Sysroot verification failed:"
        for error in "${errors[@]}"; do
            echo "  - $error"
        done
        return 1
    fi
    
    log_success "Sysroot verification passed ✓"
    return 0
}

# Generate sysroot info file
generate_sysroot_info() {
    local arch=$1
    local info_file="$SYSROOT_DIR/sysroot-info.txt"
    
    log_info "Generating sysroot info file..."
    
    {
        echo "Linux Sysroot Information"
        echo "========================="
        echo ""
        echo "Architecture: $arch"
        echo "Sysroot Path: $SYSROOT_DIR"
        echo "Created: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
        echo ""
        echo "Dynamic Linker:"
        echo "  Path: $(get_linker_path "$arch")"
        echo "  File: $(basename "$(get_linker_path "$arch")")"
        echo ""
        echo "Libraries:"
        echo "----------"
        
        if [ -d "$SYSROOT_DIR/lib" ]; then
            find "$SYSROOT_DIR/lib" -type f -name "*.so*" | while read -r lib; do
                local size=$(stat -f%z "$lib" 2>/dev/null || stat -c%s "$lib" 2>/dev/null || echo "unknown")
                echo "  $(basename "$lib"): $size bytes"
            done
        fi
        
        echo ""
        echo "Toolchain:"
        echo "----------"
        local toolchain_prefix=$(get_toolchain_prefix "$arch")
        echo "  Prefix: $toolchain_prefix"
        
        local gcc_cmd="${toolchain_prefix}-gcc"
        if command -v "$gcc_cmd" &> /dev/null; then
            echo "  GCC: $($gcc_cmd --version | head -1)"
        else
            echo "  GCC: Not available (using host gcc)"
        fi
        
    } > "$info_file"
    
    log_success "Sysroot info saved to $info_file"
    cat "$info_file"
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Set up Linux sysroot for cross-compilation with standard Linux linkers.

Options:
  --arch ARCH           Target architecture (aarch64, arm, x86_64, i686)
  --android-arch ARCH   Android architecture (arm64-v8a, armeabi-v7a, x86_64, x86)
  --sysroot-dir DIR     Sysroot directory (default: build/linux-sysroot/)
  --clean               Remove existing sysroot before creating
  --help                Show this help message

Examples:
  $0 --arch aarch64                    # Set up sysroot for aarch64
  $0 --android-arch arm64-v8a          # Set up sysroot for arm64-v8a
  $0 --arch aarch64 --clean            # Clean and recreate sysroot

EOF
}

# Main function
main() {
    local target_arch=""
    local clean=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --arch)
                target_arch="$2"
                shift 2
                ;;
            --android-arch)
                target_arch=$(map_android_to_linux_arch "$2")
                shift 2
                ;;
            --sysroot-dir)
                SYSROOT_DIR="$2"
                shift 2
                ;;
            --clean)
                clean=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Default to host architecture if not specified
    if [ -z "$target_arch" ]; then
        target_arch=$(detect_host_arch)
        log_info "No architecture specified, using host architecture: $target_arch"
    fi
    
    log_info "Setting up Linux sysroot for $target_arch..."
    log_info "Sysroot directory: $SYSROOT_DIR"
    echo ""
    
    # Clean existing sysroot if requested
    if [ "$clean" = true ] && [ -d "$SYSROOT_DIR" ]; then
        log_info "Removing existing sysroot..."
        rm -rf "$SYSROOT_DIR"
        log_success "Existing sysroot removed"
        echo ""
    fi
    
    # Check if sysroot already exists
    if [ -d "$SYSROOT_DIR" ]; then
        log_warning "Sysroot already exists: $SYSROOT_DIR"
        log_info "Use --clean to recreate it"
        exit 0
    fi
    
    # Check toolchain availability
    check_toolchain "$target_arch"
    echo ""
    
    # Create sysroot structure
    create_sysroot_structure "$target_arch"
    echo ""
    
    # Copy system libraries
    if ! copy_system_libraries "$target_arch"; then
        log_error "Failed to copy system libraries"
        exit 1
    fi
    echo ""
    
    # Verify sysroot
    if ! verify_sysroot "$target_arch"; then
        log_error "Sysroot verification failed"
        exit 1
    fi
    echo ""
    
    # Generate info file
    generate_sysroot_info "$target_arch"
    echo ""
    
    log_success "Linux sysroot setup completed successfully!"
    log_info "Sysroot location: $SYSROOT_DIR"
}

# Run main function
main "$@"
