#!/usr/bin/env bash
# build-static.sh - Main static build orchestrator
# This script orchestrates the static compilation of all packages for PRoot compatibility

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/build/static}"
CONFIG_FILE="${CONFIG_FILE:-$PROJECT_ROOT/build-config.json}"
TARGET_ARCH="${TARGET_ARCH:-}"
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

# Check if required tools are available
check_dependencies() {
    log_info "Checking build dependencies..."
    
    local missing_deps=()
    
    for cmd in gcc make jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Check for musl-gcc if musl is specified
    local libc=$(jq -r '.staticOptions.libc // "musl"' "$CONFIG_FILE")
    if [ "$libc" = "musl" ]; then
        if ! command -v musl-gcc &> /dev/null; then
            log_warning "musl-gcc not found, will attempt to use gcc with static flags"
        fi
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Please install them before running this script"
        log_error ""
        log_error "On Debian/Ubuntu: sudo apt-get install build-essential musl-tools"
        log_error "On Fedora/RHEL: sudo dnf install gcc make musl-gcc"
        log_error "On Arch: sudo pacman -S gcc make musl"
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

# Get package information from config
get_package_info() {
    local package_name=$1
    local field=$2
    
    jq -r ".packages.${package_name}.${field}" "$CONFIG_FILE"
}

# Build a package
build_package() {
    local package_name=$1
    
    log_info "Building $package_name..."
    
    # Check if package should be built statically
    local build_static=$(get_package_info "$package_name" "buildStatic")
    if [ "$build_static" != "true" ]; then
        log_info "Skipping $package_name (not configured for static build)"
        return 0
    fi
    
    # Generate build ID for metrics
    local build_id="static-${package_name}-${TARGET_ARCH}-$(date +%s)"
    
    # Check cache first
    local cache_hit=false
    if bash "$SCRIPT_DIR/build-cache.sh" check "$package_name" "static" "$TARGET_ARCH" "$CONFIG_FILE" 2>/dev/null; then
        log_info "Restoring $package_name from cache..."
        if bash "$SCRIPT_DIR/build-cache.sh" restore "$package_name" "static" "$TARGET_ARCH" "$OUTPUT_DIR"; then
            log_success "Restored $package_name from cache (skipping build)"
            cache_hit=true
            
            # Record metrics for cache hit
            bash "$SCRIPT_DIR/build-metrics.sh" start "$build_id" "$package_name" "static" "$TARGET_ARCH" > /dev/null 2>&1 || true
            bash "$SCRIPT_DIR/build-metrics.sh" stop "$build_id" "success" "true" > /dev/null 2>&1 || true
            
            return 0
        else
            log_warning "Cache restore failed, will build from source"
        fi
    fi
    
    # Start build timer
    bash "$SCRIPT_DIR/build-metrics.sh" start "$build_id" "$package_name" "static" "$TARGET_ARCH" > /dev/null 2>&1 || true
    
    # Call package-specific build script
    local build_script="$SCRIPT_DIR/build-${package_name}-static.sh"
    
    if [ ! -f "$build_script" ]; then
        log_error "Build script not found: $build_script"
        bash "$SCRIPT_DIR/build-metrics.sh" stop "$build_id" "failed" "false" > /dev/null 2>&1 || true
        return 1
    fi
    
    # Export environment variables for build scripts
    export BUILD_DIR
    export OUTPUT_DIR
    export CONFIG_FILE
    export PROJECT_ROOT
    
    # Run the build script
    if bash "$build_script"; then
        log_success "Successfully built $package_name"
        
        # Store in cache
        bash "$SCRIPT_DIR/build-cache.sh" store "$package_name" "static" "$TARGET_ARCH" "$CONFIG_FILE" "$OUTPUT_DIR" 2>/dev/null || true
        
        # Stop build timer
        bash "$SCRIPT_DIR/build-metrics.sh" stop "$build_id" "success" "false" > /dev/null 2>&1 || true
        
        return 0
    else
        log_error "Failed to build $package_name"
        bash "$SCRIPT_DIR/build-metrics.sh" stop "$build_id" "failed" "false" > /dev/null 2>&1 || true
        return 1
    fi
}

# Verify binary is statically linked
verify_static_binary() {
    local binary=$1
    local binary_name=$(basename "$binary")
    
    log_info "Verifying $binary_name is statically linked..."
    
    if [ ! -f "$binary" ]; then
        log_error "Binary not found: $binary"
        return 1
    fi
    
    # Check if binary is executable
    if [ ! -x "$binary" ]; then
        log_error "Binary is not executable: $binary"
        return 1
    fi
    
    # Use ldd to check for dynamic dependencies
    local ldd_output=$(ldd "$binary" 2>&1 || true)
    
    if echo "$ldd_output" | grep -q "not a dynamic executable"; then
        log_success "$binary_name is statically linked ✓"
        return 0
    elif echo "$ldd_output" | grep -q "statically linked"; then
        log_success "$binary_name is statically linked ✓"
        return 0
    else
        log_error "$binary_name has dynamic dependencies:"
        echo "$ldd_output" | head -10
        return 1
    fi
}

# Verify all built binaries
verify_all_binaries() {
    log_info "Verifying all built binaries..."
    
    local failed_binaries=()
    local verified_count=0
    
    # Find all binaries in output directory
    while IFS= read -r binary; do
        if verify_static_binary "$binary"; then
            ((verified_count++))
        else
            failed_binaries+=("$(basename "$binary")")
        fi
        echo ""
    done < <(find "$OUTPUT_DIR/bin" -type f -executable 2>/dev/null || true)
    
    # Report results
    echo "=========================================="
    if [ ${#failed_binaries[@]} -eq 0 ]; then
        log_success "All $verified_count binaries verified as statically linked"
        return 0
    else
        log_error "Failed verification for ${#failed_binaries[@]} binaries: ${failed_binaries[*]}"
        return 1
    fi
}

# Generate build report
generate_build_report() {
    local report_file="$OUTPUT_DIR/build-report.txt"
    
    log_info "Generating build report..."
    
    {
        echo "Static Build Report"
        echo "==================="
        echo ""
        echo "Build Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
        echo "Build Directory: $BUILD_DIR"
        echo "Output Directory: $OUTPUT_DIR"
        echo ""
        echo "Configuration:"
        echo "  libc: $(jq -r '.staticOptions.libc // "musl"' "$CONFIG_FILE")"
        echo "  Optimization: $(jq -r '.staticOptions.optimizationLevel // "Os"' "$CONFIG_FILE")"
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
        echo "Total Size:"
        local total_size=$(du -sh "$OUTPUT_DIR/bin" 2>/dev/null | awk '{print $1}')
        echo "  $total_size"
        
    } > "$report_file"
    
    log_success "Build report saved to $report_file"
    cat "$report_file"
}

# Map Android architecture to cross-compilation target
map_android_to_target() {
    local android_arch=$1
    case "$android_arch" in
        arm64-v8a)
            echo "aarch64-linux-gnu"
            ;;
        armeabi-v7a)
            echo "arm-linux-gnueabihf"
            ;;
        x86_64)
            echo "x86_64-linux-gnu"
            ;;
        x86)
            echo "i686-linux-gnu"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Get architecture-specific compiler flags
get_arch_cflags() {
    local android_arch=$1
    case "$android_arch" in
        arm64-v8a)
            echo "-march=armv8-a"
            ;;
        armeabi-v7a)
            echo "-march=armv7-a -mfloat-abi=hard -mfpu=neon"
            ;;
        x86_64)
            echo "-march=x86-64"
            ;;
        x86)
            echo "-march=i686 -m32"
            ;;
        *)
            echo ""
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
            echo "arm64-v8a"
            ;;
        armv7l|armv7*)
            echo "armeabi-v7a"
            ;;
        i686|i386)
            echo "x86"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Check if cross-compilation is needed
needs_cross_compilation() {
    local target_arch=$1
    local host_arch=$(detect_host_arch)
    
    if [ "$target_arch" = "$host_arch" ]; then
        return 1  # No cross-compilation needed
    else
        return 0  # Cross-compilation needed
    fi
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Build statically-linked binaries for PRoot compatibility.

Options:
  --arch ARCH           Target architecture (arm64-v8a, armeabi-v7a, x86_64, x86)
  --version VERSION     Build version (default: 1.0.0)
  --config FILE         Path to build configuration file (default: build-config.json)
  --build-dir DIR       Build directory (default: build/)
  --output-dir DIR      Output directory for binaries (default: build/static/)
  --package NAME        Build specific package only
  --skip-verify         Skip binary verification step
  --help                Show this help message

Environment Variables:
  BUILD_DIR             Override build directory
  OUTPUT_DIR            Override output directory
  CONFIG_FILE           Override configuration file
  TARGET_ARCH           Target architecture

Examples:
  $0 --arch arm64-v8a --version 1.0.0   # Build for arm64-v8a
  $0 --arch x86_64 --package busybox    # Build only BusyBox for x86_64
  $0 --arch armeabi-v7a                 # Build for armeabi-v7a

EOF
}

# Main function
main() {
    local packages_to_build=()
    local skip_verify=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --arch)
                TARGET_ARCH="$2"
                shift 2
                ;;
            --version)
                BUILD_VERSION="$2"
                shift 2
                ;;
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
    
    # Validate architecture
    if [ -z "$TARGET_ARCH" ]; then
        log_error "Target architecture is required (--arch)"
        show_usage
        exit 1
    fi
    
    # Validate architecture value
    case "$TARGET_ARCH" in
        arm64-v8a|armeabi-v7a|x86_64|x86)
            ;;
        *)
            log_error "Invalid architecture: $TARGET_ARCH"
            log_error "Valid options: arm64-v8a, armeabi-v7a, x86_64, x86"
            exit 1
            ;;
    esac
    
    # Update output directory to include architecture
    OUTPUT_DIR="$BUILD_DIR/static-$TARGET_ARCH"
    
    # Check if config file exists
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    
    log_info "Starting static build process..."
    log_info "Target architecture: $TARGET_ARCH"
    log_info "Build version: $BUILD_VERSION"
    log_info "Configuration: $CONFIG_FILE"
    log_info "Build directory: $BUILD_DIR"
    log_info "Output directory: $OUTPUT_DIR"
    
    # Initialize cache and metrics
    bash "$SCRIPT_DIR/build-cache.sh" init > /dev/null 2>&1 || true
    bash "$SCRIPT_DIR/build-metrics.sh" init > /dev/null 2>&1 || true
    
    # Check if cross-compilation is needed
    if needs_cross_compilation "$TARGET_ARCH"; then
        local target_triplet=$(map_android_to_target "$TARGET_ARCH")
        log_info "Cross-compilation required for $TARGET_ARCH (target: $target_triplet)"
        
        # Check if cross-compiler is available
        if [ -n "$target_triplet" ]; then
            local cross_gcc="${target_triplet}-gcc"
            if ! command -v "$cross_gcc" &> /dev/null; then
                log_warning "Cross-compiler not found: $cross_gcc"
                log_warning "Attempting native build (may fail for incompatible architectures)"
            else
                log_info "Cross-compiler found: $cross_gcc"
                export CROSS_COMPILE="$target_triplet-"
            fi
        fi
    else
        log_info "Native compilation (host matches target architecture)"
    fi
    
    # Export architecture-specific flags
    local arch_cflags=$(get_arch_cflags "$TARGET_ARCH")
    if [ -n "$arch_cflags" ]; then
        export ARCH_CFLAGS="$arch_cflags"
        log_info "Architecture-specific CFLAGS: $arch_cflags"
    fi
    
    echo ""
    
    # Check dependencies
    check_dependencies
    echo ""
    
    # Setup build directories
    setup_build_directories
    echo ""
    
    # If no specific packages specified, build all that are marked for static build
    if [ ${#packages_to_build[@]} -eq 0 ]; then
        while IFS= read -r package; do
            local build_static=$(get_package_info "$package" "buildStatic")
            if [ "$build_static" = "true" ]; then
                packages_to_build+=("$package")
            fi
        done < <(jq -r '.packages | keys[]' "$CONFIG_FILE")
    fi
    
    if [ ${#packages_to_build[@]} -eq 0 ]; then
        log_warning "No packages configured for static build"
        exit 0
    fi
    
    log_info "Packages to build: ${packages_to_build[*]}"
    echo ""
    
    # Build packages
    local failed_packages=()
    for package in "${packages_to_build[@]}"; do
        if ! build_package "$package"; then
            failed_packages+=("$package")
        fi
        echo ""
    done
    
    # Verify binaries unless skipped
    if [ "$skip_verify" = false ]; then
        if ! verify_all_binaries; then
            log_warning "Some binaries failed verification"
        fi
        echo ""
    fi
    
    # Generate build report
    generate_build_report
    echo ""
    
    # Generate build metrics report
    log_info "Generating build performance metrics..."
    bash "$SCRIPT_DIR/build-metrics.sh" report "$OUTPUT_DIR/build-metrics-report.txt" > /dev/null 2>&1 || true
    echo ""
    
    # Report final results
    echo "=========================================="
    if [ ${#failed_packages[@]} -eq 0 ]; then
        log_success "Static build completed successfully!"
        log_info "Binaries location: $OUTPUT_DIR/bin"
        log_info "Build metrics: $OUTPUT_DIR/build-metrics-report.txt"
        exit 0
    else
        log_error "Failed to build packages: ${failed_packages[*]}"
        exit 1
    fi
}

# Run main function
main "$@"
