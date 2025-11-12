#!/bin/bash

# Archive Validation Script
# Verifies bootstrap archive integrity and contents
# Usage: ./validate-archives.sh [archive1.tar.gz archive2.tar.gz ...]
#        If no archives specified, validates all archives in bootstrap-archives/

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# Configuration
ARCHIVE_DIR="bootstrap-archives"
TEMP_EXTRACT_DIR="temp-validation"

# Critical binaries that must be present in base Termux bootstrap
# Note: git, node, python are NOT in base bootstrap - they're installed via apt
CRITICAL_BINARIES=("bash" "apt" "dpkg")
# Alternative binaries (at least one from each group must exist)
# Using arrays instead of associative arrays for bash 3.2 compatibility
ALTERNATIVE_BINARIES=(
    "tar:tar"
    "gzip:gzip gunzip"
)

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

# Clean up temporary extraction directory
cleanup() {
    if [ -d "$TEMP_EXTRACT_DIR" ]; then
        rm -rf "$TEMP_EXTRACT_DIR"
    fi
}

# Set up cleanup trap
trap cleanup EXIT

# Validate a single archive
validate_archive() {
    local archive_path="$1"
    local archive_name
    archive_name=$(basename "$archive_path")
    
    log_info "Validating: $archive_name"
    
    # Check if archive file exists
    if [ ! -f "$archive_path" ]; then
        log_error "Archive file not found: $archive_path"
        return 1
    fi
    
    # Create temporary extraction directory
    local extract_dir="${TEMP_EXTRACT_DIR}/${archive_name%.tar.gz}"
    mkdir -p "$extract_dir"
    
    # Test 1: Check that archive can be extracted without errors
    log_info "  [1/4] Testing archive extraction..."
    if ! tar -xzf "$archive_path" -C "$extract_dir" 2>/dev/null; then
        log_error "  ✗ Failed to extract archive: $archive_name"
        return 1
    fi
    log_info "  ✓ Archive extracted successfully"
    
    # Test 2: Verify usr/bin directory exists
    log_info "  [2/4] Checking usr/bin directory..."
    if [ ! -d "${extract_dir}/usr/bin" ]; then
        log_error "  ✗ usr/bin directory not found in archive"
        return 1
    fi
    log_info "  ✓ usr/bin directory exists"
    
    # Test 3: Validate presence of critical binaries
    log_info "  [3/4] Checking critical binaries..."
    local missing_binaries=()
    
    # Check required binaries
    for binary in "${CRITICAL_BINARIES[@]}"; do
        if [ ! -f "${extract_dir}/usr/bin/${binary}" ]; then
            missing_binaries+=("$binary")
            log_error "  ✗ Critical binary missing: $binary"
        else
            log_info "  ✓ Found: $binary"
        fi
    done
    
    # Check alternative binaries (at least one from each group)
    for mapping in "${ALTERNATIVE_BINARIES[@]}"; do
        local group_name="${mapping%%:*}"
        local alternatives="${mapping##*:}"
        local found=false
        
        for binary in $alternatives; do
            if [ -f "${extract_dir}/usr/bin/${binary}" ]; then
                log_info "  ✓ Found: $binary"
                found=true
                break
            fi
        done
        
        if [ "$found" = false ]; then
            missing_binaries+=("$group_name (tried: $alternatives)")
            log_error "  ✗ No alternative found for: $group_name"
        fi
    done
    
    if [ ${#missing_binaries[@]} -gt 0 ]; then
        log_error "  Missing critical binaries in $archive_name"
        return 1
    fi
    
    # Test 4: Check that binaries have executable permissions
    log_info "  [4/4] Checking executable permissions..."
    local non_executable=()
    
    # Check critical binaries
    for binary in "${CRITICAL_BINARIES[@]}"; do
        local binary_path="${extract_dir}/usr/bin/${binary}"
        if [ -f "$binary_path" ] && [ ! -x "$binary_path" ]; then
            non_executable+=("$binary")
            log_error "  ✗ Binary not executable: $binary"
        fi
    done
    
    # Check alternative binaries that exist
    for mapping in "${ALTERNATIVE_BINARIES[@]}"; do
        local alternatives="${mapping##*:}"
        for binary in $alternatives; do
            local binary_path="${extract_dir}/usr/bin/${binary}"
            if [ -f "$binary_path" ] && [ ! -x "$binary_path" ]; then
                non_executable+=("$binary")
                log_error "  ✗ Binary not executable: $binary"
            fi
        done
    done
    
    if [ ${#non_executable[@]} -gt 0 ]; then
        log_error "  Binaries without executable permissions in $archive_name"
        return 1
    fi
    log_info "  ✓ All binaries have executable permissions"
    
    # Clean up extraction directory for this archive
    rm -rf "$extract_dir"
    
    log_info "✓ Validation passed: $archive_name"
    echo ""
    
    return 0
}

# Main execution
main() {
    log_info "Starting archive validation process..."
    echo ""
    
    local archives=()
    
    # Determine which archives to validate
    if [ $# -eq 0 ]; then
        # No arguments provided, validate all archives in ARCHIVE_DIR
        if [ ! -d "$ARCHIVE_DIR" ]; then
            log_error "Archive directory not found: $ARCHIVE_DIR"
            log_error "Please run package-archives.sh first or specify archive paths"
            exit 1
        fi
        
        # Find all .tar.gz files in archive directory
        while IFS= read -r -d '' archive; do
            archives+=("$archive")
        done < <(find "$ARCHIVE_DIR" -name "*.tar.gz" -type f -print0 2>/dev/null)
        
        if [ ${#archives[@]} -eq 0 ]; then
            log_error "No archives found in $ARCHIVE_DIR"
            exit 1
        fi
        
        log_info "Found ${#archives[@]} archive(s) to validate"
        echo ""
    else
        # Use provided archive paths
        archives=("$@")
    fi
    
    # Validate each archive
    local failed_archives=()
    local successful_archives=()
    
    for archive in "${archives[@]}"; do
        if validate_archive "$archive"; then
            successful_archives+=("$(basename "$archive")")
        else
            failed_archives+=("$(basename "$archive")")
            echo ""
        fi
    done
    
    # Report results
    log_info "Validation complete!"
    echo ""
    
    if [ ${#successful_archives[@]} -gt 0 ]; then
        log_info "Successfully validated archives:"
        for archive in "${successful_archives[@]}"; do
            echo "  ✓ $archive"
        done
        echo ""
    fi
    
    if [ ${#failed_archives[@]} -eq 0 ]; then
        log_info "All archives passed validation!"
        exit 0
    else
        log_error "Failed to validate the following archives:"
        for archive in "${failed_archives[@]}"; do
            echo "  ✗ $archive"
        done
        echo ""
        log_error "Validation failed for ${#failed_archives[@]} archive(s)"
        exit 1
    fi
}

# Run main function
main "$@"
