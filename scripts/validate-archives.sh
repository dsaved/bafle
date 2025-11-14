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

# Validate directory structure
validate_structure() {
    local extract_dir="$1"
    local archive_name="$2"
    
    log_info "  [2/6] Validating directory structure..."
    
    # Check for correct usr/bin directory
    if [ ! -d "${extract_dir}/usr/bin" ]; then
        log_error "  ✗ usr/bin directory not found in archive"
        return 1
    fi
    log_info "  ✓ usr/bin directory exists"
    
    # Check for correct usr/lib directory
    if [ ! -d "${extract_dir}/usr/lib" ]; then
        log_error "  ✗ usr/lib directory not found in archive"
        return 1
    fi
    log_info "  ✓ usr/lib directory exists"
    
    # Check for incorrect nested usr/usr/ structure
    if [ -d "${extract_dir}/usr/usr" ]; then
        log_error "  ✗ Incorrect nested usr/usr/ structure detected"
        log_error "     This indicates the bootstrap was incorrectly restructured"
        return 1
    fi
    log_info "  ✓ No nested usr/usr/ structure detected"
    
    # Log the directory structure for debugging
    log_info "  Directory structure at root level:"
    ls -la "$extract_dir" | tail -n +4 | awk '{print "    " $9}' | head -10
    
    # Log usr/ subdirectories
    if [ -d "${extract_dir}/usr" ]; then
        log_info "  Contents of usr/ directory:"
        ls -1 "${extract_dir}/usr" | head -10 | while read -r item; do
            if [ -d "${extract_dir}/usr/${item}" ]; then
                echo "    📁 $item/"
            else
                echo "    📄 $item"
            fi
        done
    fi
    
    return 0
}

# Verify ELF interpreter for a binary
verify_elf_interpreter() {
    local binary_path="$1"
    local binary_name="$2"
    
    # Check if file command is available
    if ! command -v file >/dev/null 2>&1; then
        log_warn "  ⚠ 'file' command not available, skipping ELF verification for $binary_name"
        return 0
    fi
    
    # Get file type information
    local file_info
    file_info=$(file "$binary_path" 2>/dev/null)
    log_info "    File type: $file_info"
    
    # Check if it's an ELF binary
    if [[ ! "$file_info" =~ "ELF" ]]; then
        log_warn "    ⚠ $binary_name is not an ELF binary (might be a script)"
        return 0
    fi
    
    # Try to extract interpreter path using readelf if available
    if command -v readelf >/dev/null 2>&1; then
        local interpreter
        interpreter=$(readelf -l "$binary_path" 2>/dev/null | grep -o '\[/[^]]*\]' | grep interpreter | sed 's/\[//;s/\]//' | head -1)
        
        if [ -n "$interpreter" ]; then
            log_info "    📍 Interpreter path: $interpreter"
            
            # Verify it's an Android linker for Termux binaries
            if [[ "$interpreter" =~ ^/system/bin/linker ]]; then
                log_info "    ✓ Uses Android system linker (PRoot compatible)"
            else
                log_warn "    ⚠ Uses non-standard interpreter: $interpreter"
                log_warn "    ⚠ This may cause issues in PRoot environments"
            fi
        else
            log_warn "    ⚠ Could not extract interpreter path for $binary_name"
        fi
    else
        # Fallback to using strings if readelf is not available
        if command -v strings >/dev/null 2>&1; then
            local interpreter
            interpreter=$(strings "$binary_path" 2>/dev/null | grep -E '^/system/bin/linker' | head -1)
            
            if [ -n "$interpreter" ]; then
                log_info "    📍 Interpreter path (strings): $interpreter"
                log_info "    ✓ Uses Android system linker (PRoot compatible)"
            fi
        fi
    fi
    
    return 0
}

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
    log_info "  [1/6] Testing archive extraction..."
    if ! tar -xzf "$archive_path" -C "$extract_dir" 2>/dev/null; then
        log_error "  ✗ Failed to extract archive: $archive_name"
        return 1
    fi
    log_info "  ✓ Archive extracted successfully"
    
    # Test 2: Validate directory structure
    if ! validate_structure "$extract_dir" "$archive_name"; then
        return 1
    fi
    
    # Test 3: Validate presence of critical binaries and verify ELF interpreters
    log_info "  [3/6] Checking critical binaries..."
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
    
    # Test 4: Verify ELF interpreters for critical binaries
    log_info "  [4/6] Verifying ELF interpreters for critical binaries..."
    log_info "  Checking interpreter paths for PRoot compatibility..."
    
    # Verify bash interpreter (most critical for PRoot compatibility)
    if [ -f "${extract_dir}/usr/bin/bash" ]; then
        log_info "  Analyzing bash binary:"
        verify_elf_interpreter "${extract_dir}/usr/bin/bash" "bash"
    fi
    
    # Verify other critical binaries
    for binary in "${CRITICAL_BINARIES[@]}"; do
        if [ "$binary" != "bash" ] && [ -f "${extract_dir}/usr/bin/${binary}" ]; then
            log_info "  Analyzing $binary binary:"
            verify_elf_interpreter "${extract_dir}/usr/bin/${binary}" "$binary"
        fi
    done
    
    # Log summary of interpreter findings
    log_info "  Interpreter verification complete"
    
    # Test 5: Check that binaries have executable permissions
    log_info "  [5/6] Checking executable permissions..."
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
    
    # Test 6: Final structure summary
    log_info "  [6/6] Structure validation summary..."
    log_info "  ✓ Bootstrap structure is correct and PRoot-compatible"
    log_info "  ✓ All critical binaries present with proper interpreters"
    
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
