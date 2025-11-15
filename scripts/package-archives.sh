#!/bin/bash

# Archive Packaging Script
# Creates compressed archives from bootstrap directories with support for multiple build modes
# Usage: ./package-archives.sh [options]
#   Options:
#     --version <version>       Version number (required)
#     --mode <mode>            Build mode: static, linux-native, or android-native (default: static)
#     --arch <arch>            Specific architecture to package (optional, packages all if not specified)
#     --compression <format>   Compression format: xz, zstd, or gzip (default: xz)
#     --strip                  Strip debug symbols from binaries (default: enabled)
#     --no-strip               Skip stripping debug symbols
#     --config <file>          Path to build configuration file (optional)
#     --input-dir <dir>        Input directory containing bootstrap (default: build/)
#     --output-dir <dir>       Output directory for archives (default: bootstrap-archives/)

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# Default configuration
BUILD_MODE="static"
INPUT_DIR="build"
OUTPUT_DIR="bootstrap-archives"
COMPRESSION="xz"
STRIP_BINARIES=true
CONFIG_FILE=""
VERSION=""
SPECIFIC_ARCH=""

# Supported architectures
ARCHITECTURES=("arm64-v8a" "armeabi-v7a" "x86_64" "x86")

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                VERSION="$2"
                shift 2
                ;;
            --mode)
                BUILD_MODE="$2"
                shift 2
                ;;
            --arch)
                SPECIFIC_ARCH="$2"
                shift 2
                ;;
            --compression)
                COMPRESSION="$2"
                shift 2
                ;;
            --strip)
                STRIP_BINARIES=true
                shift
                ;;
            --no-strip)
                STRIP_BINARIES=false
                shift
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --input-dir)
                INPUT_DIR="$2"
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            *)
                # Support legacy positional version argument
                if [ -z "$VERSION" ]; then
                    VERSION="$1"
                    shift
                else
                    log_error "Unknown argument: $1"
                    exit 1
                fi
                ;;
        esac
    done
}

# Load configuration from file
load_config() {
    if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
        log_info "Loading configuration from $CONFIG_FILE..."
        
        # Parse JSON config using basic tools
        if command -v jq &> /dev/null; then
            # Use jq if available
            local config_mode=$(jq -r '.buildMode // "static"' "$CONFIG_FILE")
            local config_compression=$(jq -r '.compression // "xz"' "$CONFIG_FILE")
            local config_strip=$(jq -r '.stripSymbols // true' "$CONFIG_FILE")
            
            # Only override if not set via command line
            [ "$BUILD_MODE" = "static" ] && BUILD_MODE="$config_mode"
            [ "$COMPRESSION" = "xz" ] && COMPRESSION="$config_compression"
            [ "$config_strip" = "false" ] && STRIP_BINARIES=false
        else
            log_warn "jq not found, skipping config file parsing"
        fi
    fi
}

# Validate version format
validate_version() {
    local version="$1"
    
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Invalid version format: $version"
        log_error "Version must follow semantic versioning (X.Y.Z)"
        return 1
    fi
    
    return 0
}

# Validate build mode
validate_build_mode() {
    local mode="$1"
    
    case "$mode" in
        static|linux-native|android-native)
            return 0
            ;;
        *)
            log_error "Invalid build mode: $mode"
            log_error "Supported modes: static, linux-native, android-native"
            return 1
            ;;
    esac
}

# Validate compression format
validate_compression() {
    local format="$1"
    
    case "$format" in
        xz)
            if ! command -v xz &> /dev/null; then
                log_error "xz compression requested but xz command not found"
                return 1
            fi
            ;;
        zstd)
            if ! command -v zstd &> /dev/null; then
                log_error "zstd compression requested but zstd command not found"
                return 1
            fi
            ;;
        gzip)
            if ! command -v gzip &> /dev/null; then
                log_error "gzip compression requested but gzip command not found"
                return 1
            fi
            ;;
        *)
            log_error "Invalid compression format: $format"
            log_error "Supported formats: xz, zstd, gzip"
            return 1
            ;;
    esac
    
    return 0
}

# Get file extension for compression format
get_compression_extension() {
    local format="$1"
    
    case "$format" in
        xz)
            echo "tar.xz"
            ;;
        zstd)
            echo "tar.zst"
            ;;
        gzip)
            echo "tar.gz"
            ;;
        *)
            echo "tar.gz"
            ;;
    esac
}

# Validate bootstrap directory structure
validate_structure() {
    local bootstrap_dir="$1"
    local arch="$2"
    
    log_info "Validating directory structure for $arch..."
    
    # Check if directory exists
    if [ ! -d "$bootstrap_dir" ]; then
        log_error "Bootstrap directory not found: $bootstrap_dir"
        return 1
    fi
    
    # Check if usr directory exists (or bin at root for some structures)
    if [ ! -d "${bootstrap_dir}/usr" ] && [ ! -d "${bootstrap_dir}/bin" ]; then
        log_error "Neither usr nor bin directory found in $bootstrap_dir"
        return 1
    fi
    
    # Check for incorrect nested usr/usr/ structure
    if [ -d "${bootstrap_dir}/usr/usr" ]; then
        log_error "Incorrect nested usr/usr/ structure detected in $arch"
        log_error "This indicates the bootstrap was incorrectly restructured"
        return 1
    fi
    
    # Verify critical directories exist
    if [ -d "${bootstrap_dir}/usr" ] && [ ! -d "${bootstrap_dir}/usr/bin" ]; then
        log_error "usr/bin directory not found in $arch bootstrap"
        return 1
    fi
    
    log_info "Directory structure validation passed for $arch"
    return 0
}

# Set correct permissions on bootstrap directories
set_permissions() {
    local bootstrap_dir="$1"
    local arch="$2"
    
    log_info "Setting permissions for $arch..."
    
    # Set executable permissions on usr/bin
    if [ -d "${bootstrap_dir}/usr/bin" ]; then
        local bin_count=$(ls -1 "${bootstrap_dir}/usr/bin" 2>/dev/null | wc -l | tr -d ' ')
        log_info "Setting executable permissions on $bin_count files in usr/bin/"
        chmod +x "${bootstrap_dir}/usr/bin"/* 2>/dev/null || true
        log_info "✓ Executable permissions set on usr/bin"
    fi
    
    # Set executable permissions on usr/libexec (if exists)
    if [ -d "${bootstrap_dir}/usr/libexec" ]; then
        local libexec_count=$(find "${bootstrap_dir}/usr/libexec" -type f 2>/dev/null | wc -l | tr -d ' ')
        log_info "Setting executable permissions on $libexec_count files in usr/libexec/"
        find "${bootstrap_dir}/usr/libexec" -type f -exec chmod +x {} \; 2>/dev/null || true
        log_info "✓ Executable permissions set on usr/libexec"
    fi
    
    # Set executable permissions on bin (if exists at root level)
    if [ -d "${bootstrap_dir}/bin" ]; then
        local root_bin_count=$(ls -1 "${bootstrap_dir}/bin" 2>/dev/null | wc -l | tr -d ' ')
        log_info "Setting executable permissions on $root_bin_count files in bin/"
        chmod +x "${bootstrap_dir}/bin"/* 2>/dev/null || true
        log_info "✓ Executable permissions set on bin"
    fi
    
    return 0
}

# Create compressed archive for a specific architecture
create_archive() {
    local arch="$1"
    local version="$2"
    local mode="$3"
    local compression="$4"
    
    # Determine bootstrap directory name based on mode
    local bootstrap_name="bootstrap-${mode}-${arch}-${version}"
    local bootstrap_dir="${INPUT_DIR}/${bootstrap_name}"
    
    # Get appropriate file extension
    local extension=$(get_compression_extension "$compression")
    local archive_name="${bootstrap_name}.${extension}"
    local archive_path="${OUTPUT_DIR}/${archive_name}"
    
    log_info "Creating archive for $arch ($mode mode, $compression compression)..."
    
    # Check if bootstrap directory exists
    if [ ! -d "$bootstrap_dir" ]; then
        log_error "Bootstrap directory not found: $bootstrap_dir"
        return 1
    fi
    
    # Validate directory structure
    if ! validate_structure "$bootstrap_dir" "$arch"; then
        log_error "Directory structure validation failed for $arch"
        return 1
    fi
    
    # Strip binaries if requested
    if [ "$STRIP_BINARIES" = true ]; then
        log_info "Stripping debug symbols from binaries..."
        if [ -f "scripts/strip-binaries.sh" ]; then
            if ! bash scripts/strip-binaries.sh "$bootstrap_dir"; then
                log_warn "Failed to strip binaries, continuing anyway..."
            fi
        else
            log_warn "strip-binaries.sh not found, skipping stripping"
        fi
    fi
    
    # Set correct permissions
    if ! set_permissions "$bootstrap_dir" "$arch"; then
        log_error "Failed to set permissions for $arch"
        return 1
    fi
    
    # Log the contents being archived for debugging
    log_info "Archive contents preview for $arch:"
    log_info "Root level directories and files:"
    ls -1 "$bootstrap_dir" | while read -r item; do
        if [ -d "${bootstrap_dir}/${item}" ]; then
            echo "  📁 $item/"
        else
            echo "  📄 $item"
        fi
    done
    
    # Show usr/ subdirectories if it exists
    if [ -d "${bootstrap_dir}/usr" ]; then
        log_info "Contents of usr/ directory:"
        ls -1 "${bootstrap_dir}/usr" | head -15 | while read -r item; do
            if [ -d "${bootstrap_dir}/usr/${item}" ]; then
                echo "  📁 usr/$item/"
            else
                echo "  📄 usr/$item"
            fi
        done
        
        # Count binaries in usr/bin
        if [ -d "${bootstrap_dir}/usr/bin" ]; then
            local bin_count=$(ls -1 "${bootstrap_dir}/usr/bin" | wc -l | tr -d ' ')
            log_info "Total binaries in usr/bin/: $bin_count"
            log_info "Sample binaries (first 10):"
            ls -1 "${bootstrap_dir}/usr/bin" | head -10 | while read -r bin; do
                echo "    - $bin"
            done
        fi
        
        # Count libraries in usr/lib
        if [ -d "${bootstrap_dir}/usr/lib" ]; then
            local lib_count=$(ls -1 "${bootstrap_dir}/usr/lib" | wc -l | tr -d ' ')
            log_info "Total items in usr/lib/: $lib_count"
        fi
    fi
    
    # Create archive with compression
    log_info "Compressing $arch bootstrap with $compression (this may take a moment)..."
    
    case "$compression" in
        xz)
            # Create tar archive and compress with xz
            # -c: create archive
            # -J: compress with xz
            # -f: output file
            # --owner=0: set owner to root (UID 0)
            # --group=0: set group to root (GID 0)
            # --numeric-owner: use numeric UIDs/GIDs instead of names
            # -C: change to directory before archiving
            if ! XZ_OPT="-9 -T0" tar -cJf "$archive_path" \
                --owner=0 \
                --group=0 \
                --numeric-owner \
                -C "$INPUT_DIR" \
                "$bootstrap_name"; then
                log_error "Failed to create xz archive for $arch"
                return 1
            fi
            ;;
        zstd)
            # Create tar archive and compress with zstd
            if ! tar -c \
                --owner=0 \
                --group=0 \
                --numeric-owner \
                -C "$INPUT_DIR" \
                "$bootstrap_name" | zstd -19 -T0 -o "$archive_path"; then
                log_error "Failed to create zstd archive for $arch"
                return 1
            fi
            ;;
        gzip)
            # Create tar archive and compress with gzip
            if ! GZIP=-9 tar -czf "$archive_path" \
                --owner=0 \
                --group=0 \
                --numeric-owner \
                -C "$INPUT_DIR" \
                "$bootstrap_name"; then
                log_error "Failed to create gzip archive for $arch"
                return 1
            fi
            ;;
        *)
            log_error "Unsupported compression format: $compression"
            return 1
            ;;
    esac
    
    log_info "Archive creation completed successfully"
    
    # Preview archive contents (first 20 entries)
    log_info "Archive contents preview (first 20 entries):"
    case "$compression" in
        xz)
            tar -tJf "$archive_path" | head -20 | while read -r entry; do
                echo "    $entry"
            done
            local total_entries=$(tar -tJf "$archive_path" | wc -l | tr -d ' ')
            ;;
        zstd)
            tar -tf "$archive_path" --use-compress-program=zstd | head -20 | while read -r entry; do
                echo "    $entry"
            done
            local total_entries=$(tar -tf "$archive_path" --use-compress-program=zstd | wc -l | tr -d ' ')
            ;;
        gzip)
            tar -tzf "$archive_path" | head -20 | while read -r entry; do
                echo "    $entry"
            done
            local total_entries=$(tar -tzf "$archive_path" | wc -l | tr -d ' ')
            ;;
    esac
    
    log_info "Total entries in archive: $total_entries"
    
    # Get archive size for reporting
    local size
    size=$(stat -f%z "$archive_path" 2>/dev/null || stat -c%s "$archive_path" 2>/dev/null)
    local size_mb=$((size / 1024 / 1024))
    
    # Generate checksum
    log_info "Generating SHA256 checksum..."
    local checksum
    if command -v sha256sum &> /dev/null; then
        checksum=$(sha256sum "$archive_path" | awk '{print $1}')
    elif command -v shasum &> /dev/null; then
        checksum=$(shasum -a 256 "$archive_path" | awk '{print $1}')
    else
        log_warn "Neither sha256sum nor shasum found, skipping checksum"
        checksum="N/A"
    fi
    
    # Save checksum to file
    if [ "$checksum" != "N/A" ]; then
        echo "${checksum}  ${archive_name}" > "${archive_path}.sha256"
    fi
    
    # Save size to file
    echo "$size" > "${archive_path}.size"
    
    log_info "Successfully created: $archive_name (${size_mb}MB)"
    log_info "  Checksum: ${checksum:0:16}...${checksum: -8}"
    log_info "  Size: $size bytes"
    
    return 0
}

# Main execution
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check if version is provided
    if [ -z "$VERSION" ]; then
        log_error "Version number is required"
        echo "Usage: $0 --version <version> [options]"
        echo "Example: $0 --version 1.0.0 --mode static --compression xz"
        echo ""
        echo "Options:"
        echo "  --version <version>       Version number (required)"
        echo "  --mode <mode>            Build mode: static, linux-native, or android-native (default: static)"
        echo "  --arch <arch>            Specific architecture to package (optional)"
        echo "  --compression <format>   Compression format: xz, zstd, or gzip (default: xz)"
        echo "  --strip                  Strip debug symbols from binaries (default: enabled)"
        echo "  --no-strip               Skip stripping debug symbols"
        echo "  --config <file>          Path to build configuration file (optional)"
        echo "  --input-dir <dir>        Input directory containing bootstrap (default: build/)"
        echo "  --output-dir <dir>       Output directory for archives (default: bootstrap-archives/)"
        exit 1
    fi
    
    log_info "Starting archive packaging process..."
    log_info "Version: $VERSION"
    log_info "Build mode: $BUILD_MODE"
    log_info "Compression: $COMPRESSION"
    log_info "Strip binaries: $STRIP_BINARIES"
    log_info "Input directory: $INPUT_DIR"
    log_info "Output directory: $OUTPUT_DIR"
    
    # Load configuration from file if provided
    load_config
    
    # Validate version format
    if ! validate_version "$VERSION"; then
        exit 1
    fi
    
    # Validate build mode
    if ! validate_build_mode "$BUILD_MODE"; then
        exit 1
    fi
    
    # Validate compression format
    if ! validate_compression "$COMPRESSION"; then
        exit 1
    fi
    
    # Check if input directory exists
    if [ ! -d "$INPUT_DIR" ]; then
        log_error "Input directory not found: $INPUT_DIR"
        log_error "Please ensure the build has completed successfully"
        exit 1
    fi
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Package archives for specified or all architectures
    local failed_archs=()
    local successful_archs=()
    
    # Determine which architectures to process
    local archs_to_process
    if [ -n "$SPECIFIC_ARCH" ]; then
        archs_to_process=("$SPECIFIC_ARCH")
        log_info "Processing specific architecture: $SPECIFIC_ARCH"
    else
        archs_to_process=("${ARCHITECTURES[@]}")
        log_info "Processing all architectures"
    fi
    
    for arch in "${archs_to_process[@]}"; do
        if create_archive "$arch" "$VERSION" "$BUILD_MODE" "$COMPRESSION"; then
            successful_archs+=("$arch")
        else
            failed_archs+=("$arch")
        fi
    done
    
    # Report results
    echo ""
    log_info "Archive packaging complete!"
    log_info "Output directory: $OUTPUT_DIR"
    
    if [ ${#successful_archs[@]} -gt 0 ]; then
        log_info "Successfully packaged architectures:"
        for arch in "${successful_archs[@]}"; do
            echo "  ✓ $arch"
        done
    fi
    
    if [ ${#failed_archs[@]} -eq 0 ]; then
        log_info "All archives created successfully!"
        exit 0
    else
        log_error "Failed to package the following architectures:"
        for arch in "${failed_archs[@]}"; do
            echo "  ✗ $arch"
        done
        exit 1
    fi
}

# Run main function
main "$@"
