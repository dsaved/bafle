#!/bin/bash

# Script to generate SHA-256 checksums and calculate file sizes for bootstrap archives
# Outputs checksums.txt file and JSON data structure for manifest updates
# Supports multiple build modes (static, linux-native, android-native)
# Usage: ./generate-checksums.sh [options]
#   Options:
#     --version <version>       Version number (required if VERSION env var not set)
#     --mode <mode>            Build mode: static, linux-native, or android-native (default: static)
#     --arch <arch>            Specific architecture to process (optional, processes all if not specified)
#     --compression <format>   Compression format: xz, zstd, or gzip (default: xz)
#     --archive-dir <dir>      Directory containing archives (default: bootstrap-archives/)

set -e  # Exit on first error
set -u  # Fail on undefined variables
set -o pipefail  # Catch errors in pipes

# Configuration
ARCHIVE_DIR="${ARCHIVE_DIR:-bootstrap-archives}"
ARCHITECTURES=("arm64-v8a" "armeabi-v7a" "x86_64" "x86")
BUILD_MODE="static"
COMPRESSION="xz"
SPECIFIC_ARCH=""
VERSION="${VERSION:-}"

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
            --archive-dir)
                ARCHIVE_DIR="$2"
                shift 2
                ;;
            *)
                log_error "Unknown argument: $1"
                echo "Usage: $0 [--version <version>] [--mode <mode>] [--arch <arch>] [--compression <format>] [--archive-dir <dir>]"
                exit 1
                ;;
        esac
    done
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

# Parse arguments if provided
if [ $# -gt 0 ]; then
    parse_arguments "$@"
fi

# Check if version is provided
if [ -z "$VERSION" ]; then
    log_error "VERSION is not set"
    log_error "Please provide version via --version flag or VERSION environment variable"
    log_error "Example: $0 --version 1.0.0"
    log_error "Example: export VERSION=1.0.0 && $0"
    exit 1
fi

log_info "Starting checksum generation for version $VERSION..."
log_info "Build mode: $BUILD_MODE"
log_info "Compression: $COMPRESSION"
log_info "Archive directory: $ARCHIVE_DIR"

# Ensure archive directory exists
if [ ! -d "$ARCHIVE_DIR" ]; then
    log_error "Archive directory not found: $ARCHIVE_DIR"
    log_error "Please ensure archives have been created before generating checksums"
    exit 1
fi

# Get file extension
EXTENSION=$(get_compression_extension "$COMPRESSION")

# Initialize checksums file
CHECKSUMS_FILE="${ARCHIVE_DIR}/checksums.txt"
> "$CHECKSUMS_FILE"

# Initialize JSON output
JSON_OUTPUT="{"

first=true

log_info "Generating checksums and calculating file sizes..."

# Track failures
failed_archs=()

# Determine which architectures to process
if [ -n "$SPECIFIC_ARCH" ]; then
    ARCHS_TO_PROCESS=("$SPECIFIC_ARCH")
    log_info "Processing specific architecture: $SPECIFIC_ARCH"
else
    ARCHS_TO_PROCESS=("${ARCHITECTURES[@]}")
    log_info "Processing all architectures"
fi

for arch in "${ARCHS_TO_PROCESS[@]}"; do
    archive_file="${ARCHIVE_DIR}/bootstrap-${BUILD_MODE}-${arch}-${VERSION}.${EXTENSION}"
    
    log_info "Processing $arch..."
    
    # Check if archive exists
    if [ ! -f "$archive_file" ]; then
        log_error "Archive file not found: $archive_file"
        log_error "Please ensure package-archives.sh has been run successfully"
        failed_archs+=("$arch")
        continue
    fi
    
    # Calculate SHA-256 checksum
    log_info "  Calculating SHA-256 checksum..."
    if command -v sha256sum &> /dev/null; then
        if ! checksum=$(sha256sum "$archive_file" 2>/dev/null | awk '{print $1}'); then
            log_error "  Failed to calculate checksum using sha256sum for $arch"
            failed_archs+=("$arch")
            continue
        fi
    elif command -v shasum &> /dev/null; then
        if ! checksum=$(shasum -a 256 "$archive_file" 2>/dev/null | awk '{print $1}'); then
            log_error "  Failed to calculate checksum using shasum for $arch"
            failed_archs+=("$arch")
            continue
        fi
    else
        log_error "Neither sha256sum nor shasum command found"
        log_error "Please install one of these tools to calculate checksums"
        exit 1
    fi
    
    # Get file size in bytes
    log_info "  Calculating file size..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if ! size=$(stat -f%z "$archive_file" 2>/dev/null); then
            log_error "  Failed to get file size for $arch (macOS)"
            failed_archs+=("$arch")
            continue
        fi
    else
        # Linux
        if ! size=$(stat -c%s "$archive_file" 2>/dev/null); then
            log_error "  Failed to get file size for $arch (Linux)"
            failed_archs+=("$arch")
            continue
        fi
    fi
    
    # Append to checksums.txt file
    echo "${checksum}  bootstrap-${BUILD_MODE}-${arch}-${VERSION}.${EXTENSION}" >> "$CHECKSUMS_FILE"
    
    # Format checksum for manifest (with sha256: prefix)
    formatted_checksum="sha256:${checksum}"
    
    # Build JSON output
    if [ "$first" = true ]; then
        first=false
    else
        JSON_OUTPUT+=","
    fi
    
    JSON_OUTPUT+="\"${arch}\":{\"checksum\":\"${formatted_checksum}\",\"size\":${size}}"
    
    # Convert size to MB for display
    size_mb=$((size / 1024 / 1024))
    
    log_info "  ✓ Checksum: ${checksum:0:16}...${checksum: -8}"
    log_info "  ✓ Size: $size bytes (${size_mb}MB)"
done

JSON_OUTPUT+="}"

# Check if any architectures failed
if [ ${#failed_archs[@]} -gt 0 ]; then
    echo ""
    log_error "Failed to process the following architectures:"
    for arch in "${failed_archs[@]}"; do
        echo "  ✗ $arch"
    done
    exit 1
fi

echo ""
log_info "Checksums file created: $CHECKSUMS_FILE"
echo ""
log_info "JSON output for manifest update:"
echo "$JSON_OUTPUT"

# Save JSON to mode-specific file for workflow consumption
if [ -n "$SPECIFIC_ARCH" ]; then
    # Single architecture - create mode-arch specific file
    JSON_FILE="${ARCHIVE_DIR}/checksums-${BUILD_MODE}-${SPECIFIC_ARCH}.json"
    CHECKSUMS_SPECIFIC="${ARCHIVE_DIR}/checksums-${BUILD_MODE}-${SPECIFIC_ARCH}.txt"
    
    # Copy the main checksums file to mode-arch specific file
    cp "$CHECKSUMS_FILE" "$CHECKSUMS_SPECIFIC"
else
    # Multiple architectures - create general file
    JSON_FILE="${ARCHIVE_DIR}/checksums.json"
fi

if ! echo "$JSON_OUTPUT" > "$JSON_FILE"; then
    log_error "Failed to write $JSON_FILE file"
    exit 1
fi

echo ""
log_info "Checksum generation complete!"
log_info "Generated files:"
echo "  ✓ $CHECKSUMS_FILE"
if [ -n "$SPECIFIC_ARCH" ]; then
    echo "  ✓ $CHECKSUMS_SPECIFIC"
fi
echo "  ✓ $JSON_FILE"
