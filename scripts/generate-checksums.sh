#!/bin/bash

# Script to generate SHA-256 checksums and calculate file sizes for bootstrap archives
# Outputs checksums.txt file and JSON data structure for manifest updates

set -e  # Exit on first error
set -u  # Fail on undefined variables
set -o pipefail  # Catch errors in pipes

# Configuration
# If ARCHIVE_DIR is not set, use current directory (for when run from bootstrap-archives/)
ARCHIVE_DIR="${ARCHIVE_DIR:-.}"
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

# Check if version is provided
if [ -z "${VERSION:-}" ]; then
    log_error "VERSION environment variable is not set"
    log_error "Please set VERSION before running this script"
    log_error "Example: export VERSION=1.0.0"
    exit 1
fi

log_info "Starting checksum generation for version $VERSION..."

# Initialize checksums file
CHECKSUMS_FILE="checksums.txt"
> "$CHECKSUMS_FILE"

# Initialize JSON output
JSON_OUTPUT="{"

first=true

log_info "Generating checksums and calculating file sizes..."

# Track failures
failed_archs=()

for arch in "${ARCHITECTURES[@]}"; do
    archive_file="${ARCHIVE_DIR}/bootstrap-${arch}-${VERSION}.tar.gz"
    
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
    echo "${checksum}  bootstrap-${arch}-${VERSION}.tar.gz" >> "$CHECKSUMS_FILE"
    
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

# Also save JSON to a file for easier consumption by other scripts
if ! echo "$JSON_OUTPUT" > checksums.json; then
    log_error "Failed to write checksums.json file"
    exit 1
fi

echo ""
log_info "Checksum generation complete!"
log_info "Generated files:"
echo "  ✓ $CHECKSUMS_FILE"
echo "  ✓ checksums.json"
