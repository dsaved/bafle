#!/usr/bin/env bash
# build-linux-native.sh - Main Linux-native build orchestrator
# This script orchestrates the Linux-native compilation of all packages for PRoot compatibility

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/build/linux-native}"
SYSROOT_DIR="${SYSROOT_DIR:-$BUILD_DIR/linux-sysroot}"
CONFIG_FILE="${CONFIG_FILE:-$PROJECT_ROOT/build-config.json}"
BUILD_VERSION="${BUILD_VERSION:-1.0.0}"

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

# Check if required tools are available
check_dependencies() {
    log_info "Checking build dependencies..."
    
    local missing_deps=()
    
    for cmd in gcc make jq readelf; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Please install them before running this script"
        log_error ""
        log_error "On Debian/Ubuntu: sudo apt-get install build-essential binutils jq"
        log_error "On Fedora/RHEL: sudo dnf install gcc make binutils jq"
        log_error "On Arch: sudo pacman -S gcc make binutils jq"
        exit 1
    fi
    
    log_success "All required dependencies are available"
}

# Setup build directories
setup_build_directories() {
    log_info "Setting up build directories..."
    
    mkdir -p "$BUILD_DIR"
    mkdir -p "$OUTPUT_DIR/bin"
    mkdir -p "$OUTPUT_DIR/lib"
    
    log_success "Build directories created"
}

# Setup or verify sysroot
setup_sysroot() {
    local arch=$1
    
    log_info "Setting up Linux sysroot for $arch..."
    
    if [ -d "$SYSROOT_DIR" ]; then
        log_info "Sysroot already exists: $SYSROOT_DIR"
    else
        log_info "Creating new sysroot..."
        
        # Export environment variables for sysroot setup script
        export SYSROOT_DIR
        export PROJECT_ROOT
        export BUILD_DIR
        
        # Run sysroot setup script
        if bash "$SCRIPT_DIR/setup-linux-sysroot.sh" --arch "$arch"; then
            log_success "Sysroot setup completed"
        else
            log_error "Failed to setup sysroot"
            exit 1
        fi
    fi
}

# Get package information from config
get_package_info() {
    local package_name=$1
    local field=$2
    
    jq -r ".packages.${package_name}.${field}" "$CONFIG_FILE"
}

# Build a package with Linux-native configuration
build_package() {
    local package_name=$1
    local arch=$2
    
    log_info "Building $package_name for Linux-native ($arch)..."
    
    # Generate build ID for metrics
    local build_id="linux-native-${package_name}-${TARGET_ARCH:-$arch}-$(date +%s)"
    
    # Check cache first
    local cache_hit=false
    if bash "$SCRIPT_DIR/build-cache.sh" check "$package_name" "linux-native" "${TARGET_ARCH:-$arch}" "$CONFIG_FILE" 2>/dev/null; then
        log_info "Restoring $package_name from cache..."
        if bash "$SCRIPT_DIR/build-cache.sh" restore "$package_name" "linux-native" "${TARGET_ARCH:-$arch}" "$OUTPUT_DIR"; then
            log_success "Restored $package_name from cache (skipping build)"
            cache_hit=true
            
            # Record metrics for cache hit
            bash "$SCRIPT_DIR/build-metrics.sh" start "$build_id" "$package_name" "linux-native" "${TARGET_ARCH:-$arch}" > /dev/null 2>&1 || true
            bash "$SCRIPT_DIR/build-metrics.sh" stop "$build_id" "success" "true" > /dev/null 2>&1 || true
            
            return 0
        else
            log_warning "Cache restore failed, will build from source"
        fi
    fi
    
    # Start build timer
    bash "$SCRIPT_DIR/build-metrics.sh" start "$build_id" "$package_name" "linux-native" "${TARGET_ARCH:-$arch}" > /dev/null 2>&1 || true
    
    # Check if package-specific linux-native build script exists
    local build_script="$SCRIPT_DIR/build-${package_name}-linux-native.sh"
    
    if [ ! -f "$build_script" ]; then
        log_warning "Linux-native build script not found: $build_script"
        log_info "Attempting to use static build script with modifications..."
        
        # Fall back to static build script if linux-native specific doesn't exist
        build_script="$SCRIPT_DIR/build-${package_name}-static.sh"
        
        if [ ! -f "$build_script" ]; then
            log_error "No build script found for $package_name"
            bash "$SCRIPT_DIR/build-metrics.sh" stop "$build_id" "failed" "false" > /dev/null 2>&1 || true
            return 1
        fi
    fi
    
    # Export environment variables for build scripts
    export BUILD_DIR
    export OUTPUT_DIR
    export SYSROOT_DIR
    export CONFIG_FILE
    export PROJECT_ROOT
    export TARGET_ARCH="$arch"
    export BUILD_MODE="linux-native"
    
    # Run the build script
    if bash "$build_script"; then
        log_success "Successfully built $package_name"
        
        # Store in cache
        bash "$SCRIPT_DIR/build-cache.sh" store "$package_name" "linux-native" "${TARGET_ARCH:-$arch}" "$CONFIG_FILE" "$OUTPUT_DIR" 2>/dev/null || true
        
        # Stop build timer
        bash "$SCRIPT_DIR/build-metrics.sh" stop "$build_id" "success" "false" > /dev/null 2>&1 || true
        
        return 0
    else
        log_error "Failed to build $package_name"
        bash "$SCRIPT_DIR/build-metrics.sh" stop "$build_id" "failed" "false" > /dev/null 2>&1 || true
        return 1
    fi
}

# Verify binary uses Linux linker
verify_linux_native_binary() {
    local binary=$1
    local arch=$2
    local binary_name=$(basename "$binary")
    
    log_info "Verifying $binary_name uses Linux linker..."
    
    if [ ! -f "$binary" ]; then
        log_error "Binary not found: $binary"
        return 1
    fi
    
    # Check if binary is executable
    if [ ! -x "$binary" ]; then
        log_error "Binary is not executable: $binary"
        return 1
    fi
    
    # Use readelf to check interpreter (dynamic linker)
    local expected_linker=$(get_linker_path "$arch")
    local interpreter=$(readelf -l "$binary" 2>/dev/null | grep "interpreter" | sed 's/.*\[\(.*\)\]/\1/')
    
    if [ -z "$interpreter" ]; then
        log_error "$binary_name appears to be statically linked (no interpreter)"
        return 1
    fi
    
    if [ "$interpreter" = "$expected_linker" ]; then
        log_success "$binary_name uses Linux linker: $interpreter ✓"
        return 0
    else
        log_error "$binary_name uses unexpected linker: $interpreter"
        log_error "Expected: $expected_linker"
        return 1
    fi
}

# Verify RPATH is set correctly
verify_rpath() {
    local binary=$1
    local binary_name=$(basename "$binary")
    
    log_info "Verifying RPATH for $binary_name..."
    
    # Check RPATH using readelf
    local rpath=$(readelf -d "$binary" 2>/dev/null | grep "RPATH\|RUNPATH" | sed 's/.*\[\(.*\)\]/\1/' || true)
    
    if [ -n "$rpath" ]; then
        log_success "$binary_name has RPATH: $rpath ✓"
        
        # Verify it includes expected paths
        if echo "$rpath" | grep -q "/lib" && echo "$rpath" | grep -q "/usr/lib"; then
            log_success "RPATH includes expected library paths ✓"
            return 0
        else
            log_warning "RPATH may not include all expected paths"
            return 0
        fi
    else
        log_warning "$binary_name has no RPATH set (will use default library paths)"
        return 0
    fi
}

# Verify all built binaries
verify_all_binaries() {
    local arch=$1
    
    log_info "Verifying all built binaries..."
    
    local failed_binaries=()
    local verified_count=0
    
    # Find all binaries in output directory
    while IFS= read -r binary; do
        if verify_linux_native_binary "$binary" "$arch"; then
            verify_rpath "$binary"
            ((verified_count++))
        else
            failed_binaries+=("$(basename "$binary")")
        fi
        echo ""
    done < <(find "$OUTPUT_DIR/bin" -type f -executable 2>/dev/null || true)
    
    # Report results
    echo "=========================================="
    if [ ${#failed_binaries[@]} -eq 0 ]; then
        log_success "All $verified_count binaries verified as Linux-native"
        return 0
    else
        log_error "Failed verification for ${#failed_binaries[@]} binaries: ${failed_binaries[*]}"
        return 1
    fi
}

# Copy sysroot libraries to output
copy_sysroot_libraries() {
    log_info "Copying sysroot libraries to output directory..."
    
    if [ ! -d "$SYSROOT_DIR/lib" ]; then
        log_error "Sysroot lib directory not found: $SYSROOT_DIR/lib"
        return 1
    fi
    
    # Copy all libraries from sysroot
    cp -r "$SYSROOT_DIR/lib"/* "$OUTPUT_DIR/lib/" 2>/dev/null || true
    
    # Count copied libraries
    local lib_count=$(find "$OUTPUT_DIR/lib" -type f -name "*.so*" | wc -l | tr -d ' ')
    log_success "Copied $lib_count libraries to output directory"
}

# Generate build report
generate_build_report() {
    local arch=$1
    local report_file="$OUTPUT_DIR/build-report.txt"
    
    log_info "Generating build report..."
    
    {
        echo "Linux-Native Build Report"
        echo "========================="
        echo ""
        echo "Build Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
        echo "Architecture: $arch"
        echo "Build Directory: $BUILD_DIR"
        echo "Output Directory: $OUTPUT_DIR"
        echo "Sysroot Directory: $SYSROOT_DIR"
        echo ""
        echo "Configuration:"
        echo "  Dynamic Linker: $(get_linker_path "$arch")"
        echo "  Toolchain: $(get_toolchain_prefix "$arch")"
        echo ""
        echo "Built Binaries:"
        echo "---------------"
        
        if [ -d "$OUTPUT_DIR/bin" ]; then
            find "$OUTPUT_DIR/bin" -type f -executable | while read -r binary; do
                local size=$(stat -f%z "$binary" 2>/dev/null || stat -c%s "$binary" 2>/dev/null || echo "unknown")
                local size_mb=$(echo "scale=2; $size / 1048576" | bc 2>/dev/null || echo "?")
                echo "  $(basename "$binary"): ${size_mb} MB"
            done
        fi
        
        echo ""
        echo "Libraries:"
        echo "----------"
        
        if [ -d "$OUTPUT_DIR/lib" ]; then
            find "$OUTPUT_DIR/lib" -type f -name "*.so*" | while read -r lib; do
                local size=$(stat -f%z "$lib" 2>/dev/null || stat -c%s "$lib" 2>/dev/null || echo "unknown")
                local size_kb=$(echo "scale=2; $size / 1024" | bc 2>/dev/null || echo "?")
                echo "  $(basename "$lib"): ${size_kb} KB"
            done
        fi
        
        echo ""
        echo "Total Size:"
        local total_size=$(du -sh "$OUTPUT_DIR" 2>/dev/null | awk '{print $1}')
        echo "  $total_size"
        
    } > "$report_file"
    
    log_success "Build report saved to $report_file"
    cat "$report_file"
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Build Linux-native dynamically-linked binaries for PRoot compatibility.

Options:
  --config FILE         Path to build configuration file (default: build-config.json)
  --build-dir DIR       Build directory (default: build/)
  --output-dir DIR      Output directory for binaries (default: build/linux-native/)
  --sysroot-dir DIR     Sysroot directory (default: build/linux-sysroot/)
  --arch ARCH           Target architecture (aarch64, arm, x86_64, i686)
  --android-arch ARCH   Android architecture (arm64-v8a, armeabi-v7a, x86_64, x86)
  --version VERSION     Build version (default: 1.0.0)
  --package NAME        Build specific package only
  --skip-verify         Skip binary verification step
  --help                Show this help message

Environment Variables:
  BUILD_DIR             Override build directory
  OUTPUT_DIR            Override output directory
  SYSROOT_DIR           Override sysroot directory
  CONFIG_FILE           Override configuration file

Examples:
  $0 --arch aarch64                    # Build for aarch64
  $0 --android-arch arm64-v8a          # Build for arm64-v8a
  $0 --package busybox                 # Build only BusyBox

EOF
}

# Main function
main() {
    local packages_to_build=()
    local skip_verify=false
    local target_arch=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --build-dir)
                BUILD_DIR="$2"
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --sysroot-dir)
                SYSROOT_DIR="$2"
                shift 2
                ;;
            --arch)
                target_arch="$2"
                shift 2
                ;;
            --android-arch)
                target_arch=$(map_android_to_linux_arch "$2")
                # Store Android arch for output directory naming
                export TARGET_ARCH="$2"
                shift 2
                ;;
            --version)
                BUILD_VERSION="$2"
                shift 2
                ;;
            --package)
                packages_to_build+=("$2")
                shift 2
                ;;
            --skip-verify)
                skip_verify=true
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
    
    # Update output directory to include architecture if TARGET_ARCH is set
    if [ -n "$TARGET_ARCH" ]; then
        OUTPUT_DIR="$BUILD_DIR/linux-native-$TARGET_ARCH"
    fi
    
    # Default to host architecture if not specified
    if [ -z "$target_arch" ]; then
        target_arch=$(detect_host_arch)
        log_info "No architecture specified, using host architecture: $target_arch"
    fi
    
    # Check if config file exists
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    
    log_info "Starting Linux-native build process..."
    log_info "Architecture: $target_arch"
    if [ -n "$TARGET_ARCH" ]; then
        log_info "Android architecture: $TARGET_ARCH"
    fi
    log_info "Build version: $BUILD_VERSION"
    log_info "Configuration: $CONFIG_FILE"
    log_info "Build directory: $BUILD_DIR"
    log_info "Output directory: $OUTPUT_DIR"
    log_info "Sysroot directory: $SYSROOT_DIR"
    
    # Initialize cache and metrics
    bash "$SCRIPT_DIR/build-cache.sh" init > /dev/null 2>&1 || true
    bash "$SCRIPT_DIR/build-metrics.sh" init > /dev/null 2>&1 || true
    
    # Export architecture information for build scripts
    export LINUX_ARCH="$target_arch"
    export CROSS_COMPILE_TARGET=$(get_toolchain_prefix "$target_arch")
    
    # Check if cross-compilation toolchain is available
    local cross_gcc="${CROSS_COMPILE_TARGET}-gcc"
    if command -v "$cross_gcc" &> /dev/null; then
        log_info "Cross-compiler found: $cross_gcc"
        export CROSS_COMPILE="${CROSS_COMPILE_TARGET}-"
    else
        log_warning "Cross-compiler not found: $cross_gcc"
        log_warning "Attempting native build (may fail for incompatible architectures)"
    fi
    
    echo ""
    
    # Check dependencies
    check_dependencies
    echo ""
    
    # Setup build directories
    setup_build_directories
    echo ""
    
    # Setup sysroot
    setup_sysroot "$target_arch"
    echo ""
    
    # If no specific packages specified, build all packages
    if [ ${#packages_to_build[@]} -eq 0 ]; then
        while IFS= read -r package; do
            packages_to_build+=("$package")
        done < <(jq -r '.packages | keys[]' "$CONFIG_FILE")
    fi
    
    if [ ${#packages_to_build[@]} -eq 0 ]; then
        log_warning "No packages configured for build"
        exit 0
    fi
    
    log_info "Packages to build: ${packages_to_build[*]}"
    echo ""
    
    # Build packages
    local failed_packages=()
    for package in "${packages_to_build[@]}"; do
        if ! build_package "$package" "$target_arch"; then
            failed_packages+=("$package")
        fi
        echo ""
    done
    
    # Copy sysroot libraries to output
    copy_sysroot_libraries
    echo ""
    
    # Verify binaries unless skipped
    if [ "$skip_verify" = false ]; then
        if ! verify_all_binaries "$target_arch"; then
            log_warning "Some binaries failed verification"
        fi
        echo ""
    fi
    
    # Generate build report
    generate_build_report "$target_arch"
    echo ""
    
    # Generate build metrics report
    log_info "Generating build performance metrics..."
    bash "$SCRIPT_DIR/build-metrics.sh" report "$OUTPUT_DIR/build-metrics-report.txt" > /dev/null 2>&1 || true
    echo ""
    
    # Report final results
    echo "=========================================="
    if [ ${#failed_packages[@]} -eq 0 ]; then
        log_success "Linux-native build completed successfully!"
        log_info "Binaries location: $OUTPUT_DIR/bin"
        log_info "Libraries location: $OUTPUT_DIR/lib"
        log_info "Build metrics: $OUTPUT_DIR/build-metrics-report.txt"
        exit 0
    else
        log_error "Failed to build packages: ${failed_packages[*]}"
        exit 1
    fi
}

# Run main function
main "$@"
