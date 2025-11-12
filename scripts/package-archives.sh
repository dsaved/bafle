#!/bin/bash

# Archive Packaging Script
# Creates tar.gz archives from bootstrap directories
# Usage: ./package-archives.sh <version>

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# Configuration
DOWNLOAD_DIR="bootstrap-downloads"
OUTPUT_DIR="bootstrap-archives"

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

# Set correct permissions on bootstrap directories
set_permissions() {
    local bootstrap_dir="$1"
    local arch="$2"
    
    log_info "Setting permissions for $arch..."
    
    # Set executable permissions on usr/bin
    if [ -d "${bootstrap_dir}/usr/bin" ]; then
        chmod +x "${bootstrap_dir}/usr/bin"/* 2>/dev/null || true
        log_info "Set executable permissions on usr/bin"
    else
        log_warn "usr/bin directory not found in $arch bootstrap"
    fi
    
    # Set executable permissions on usr/libexec (if exists)
    if [ -d "${bootstrap_dir}/usr/libexec" ]; then
        chmod +x "${bootstrap_dir}/usr/libexec"/* 2>/dev/null || true
        log_info "Set executable permissions on usr/libexec"
    fi
    
    return 0
}

# Create tar.gz archive for a specific architecture
create_archive() {
    local arch="$1"
    local version="$2"
    local bootstrap_dir="${DOWNLOAD_DIR}/${arch}"
    local archive_name="bootstrap-${arch}-${version}.tar.gz"
    local archive_path="${OUTPUT_DIR}/${archive_name}"
    
    log_info "Creating archive for $arch..."
    
    # Check if bootstrap directory exists
    if [ ! -d "$bootstrap_dir" ]; then
        log_error "Bootstrap directory not found: $bootstrap_dir"
        return 1
    fi
    
    # Check if usr directory exists
    if [ ! -d "${bootstrap_dir}/usr" ]; then
        log_error "usr directory not found in $bootstrap_dir"
        return 1
    fi
    
    # Set correct permissions
    if ! set_permissions "$bootstrap_dir" "$arch"; then
        log_error "Failed to set permissions for $arch"
        return 1
    fi
    
    # Create archive with specific options:
    # -c: create archive
    # -z: compress with gzip
    # -f: output file
    # --owner=0: set owner to root (UID 0)
    # --group=0: set group to root (GID 0)
    # --numeric-owner: use numeric UIDs/GIDs instead of names
    # -C: change to directory before archiving
    # -9: maximum compression level (passed via GZIP env var)
    log_info "Compressing $arch bootstrap (this may take a moment)..."
    
    if ! GZIP=-9 tar -czf "$archive_path" \
        --owner=0 \
        --group=0 \
        --numeric-owner \
        -C "$bootstrap_dir" \
        usr; then
        log_error "Failed to create archive for $arch"
        return 1
    fi
    
    # Get archive size for reporting
    local size
    size=$(stat -f%z "$archive_path" 2>/dev/null || stat -c%s "$archive_path" 2>/dev/null)
    local size_mb=$((size / 1024 / 1024))
    
    log_info "Successfully created: $archive_name (${size_mb}MB)"
    
    return 0
}

# Main execution
main() {
    # Check if version argument is provided
    if [ $# -eq 0 ]; then
        log_error "Version number is required"
        echo "Usage: $0 <version>"
        echo "Example: $0 1.0.0"
        exit 1
    fi
    
    local version="$1"
    
    log_info "Starting archive packaging process..."
    log_info "Version: $version"
    
    # Validate version format
    if ! validate_version "$version"; then
        exit 1
    fi
    
    # Check if download directory exists
    if [ ! -d "$DOWNLOAD_DIR" ]; then
        log_error "Download directory not found: $DOWNLOAD_DIR"
        log_error "Please run download-bootstraps.sh first"
        exit 1
    fi
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Package archives for all architectures
    local failed_archs=()
    local successful_archs=()
    
    for arch in "${ARCHITECTURES[@]}"; do
        if create_archive "$arch" "$version"; then
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
