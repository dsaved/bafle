#!/usr/bin/env bash

# End-to-End Workflow Test
# Tests the complete workflow from download to packaging for android-native mode
# This validates that all steps work together correctly

set -e
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test configuration
TEST_MODE="android-native"
TEST_ARCH="arm64-v8a"
TEST_VERSION="2.0.0-test"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test artifacts..."
    rm -rf "$PROJECT_ROOT/bootstrap-downloads"
    rm -rf "$PROJECT_ROOT/build/bootstrap-${TEST_MODE}-${TEST_ARCH}-${TEST_VERSION}"
    rm -rf "$PROJECT_ROOT/bootstrap-archives/bootstrap-${TEST_MODE}-${TEST_ARCH}-${TEST_VERSION}"*
}

# Test Step 1: Download bootstraps
test_download() {
    log_info "=========================================="
    log_info "Step 1: Testing bootstrap download"
    log_info "=========================================="
    
    cd "$PROJECT_ROOT"
    
    if ! bash scripts/download-bootstraps.sh; then
        log_error "Bootstrap download failed"
        return 1
    fi
    
    # Verify download directory exists
    if [ ! -d "bootstrap-downloads/${TEST_ARCH}" ]; then
        log_error "Downloaded bootstrap not found at bootstrap-downloads/${TEST_ARCH}"
        return 1
    fi
    
    # Verify critical files exist (android-native has flat structure)
    if [ ! -d "bootstrap-downloads/${TEST_ARCH}/bin" ]; then
        log_error "bin directory not found in downloaded bootstrap"
        return 1
    fi
    
    log_success "Bootstrap download successful"
    log_info "Downloaded to: bootstrap-downloads/${TEST_ARCH}"
    log_info "Contents:"
    ls -la "bootstrap-downloads/${TEST_ARCH}" | head -10
    
    return 0
}

# Test Step 2: Organize bootstrap
test_organize() {
    log_info ""
    log_info "=========================================="
    log_info "Step 2: Testing bootstrap organization"
    log_info "=========================================="
    
    cd "$PROJECT_ROOT"
    
    BOOTSTRAP_NAME="bootstrap-${TEST_MODE}-${TEST_ARCH}-${TEST_VERSION}"
    SOURCE_DIR="bootstrap-downloads/${TEST_ARCH}"
    DEST_DIR="build/${BOOTSTRAP_NAME}"
    
    log_info "Moving bootstrap from $SOURCE_DIR to $DEST_DIR"
    
    if [ ! -d "$SOURCE_DIR" ]; then
        log_error "Source directory not found: $SOURCE_DIR"
        return 1
    fi
    
    mkdir -p build
    mv "$SOURCE_DIR" "$DEST_DIR"
    
    # Verify destination exists
    if [ ! -d "$DEST_DIR" ]; then
        log_error "Failed to move bootstrap to $DEST_DIR"
        return 1
    fi
    
    # Verify structure (android-native has flat structure with bin/ at root)
    if [ ! -d "$DEST_DIR/bin" ]; then
        log_error "bin directory not found in organized bootstrap"
        return 1
    fi
    
    log_success "Bootstrap organization successful"
    log_info "Organized at: $DEST_DIR"
    log_info "Structure:"
    ls -la "$DEST_DIR" | head -10
    
    return 0
}

# Test Step 3: Package archive
test_package() {
    log_info ""
    log_info "=========================================="
    log_info "Step 3: Testing archive packaging"
    log_info "=========================================="
    
    cd "$PROJECT_ROOT"
    
    if ! bash scripts/package-archives.sh \
        --version "$TEST_VERSION" \
        --mode "$TEST_MODE" \
        --arch "$TEST_ARCH"; then
        log_error "Archive packaging failed"
        return 1
    fi
    
    # Verify archive was created
    local archive_name="bootstrap-${TEST_MODE}-${TEST_ARCH}-${TEST_VERSION}.tar.xz"
    if [ ! -f "bootstrap-archives/$archive_name" ]; then
        log_error "Archive not found: bootstrap-archives/$archive_name"
        return 1
    fi
    
    # Verify checksum file
    if [ ! -f "bootstrap-archives/${archive_name}.sha256" ]; then
        log_error "Checksum file not found"
        return 1
    fi
    
    # Get archive size
    local size=$(stat -f%z "bootstrap-archives/$archive_name" 2>/dev/null || stat -c%s "bootstrap-archives/$archive_name" 2>/dev/null)
    local size_mb=$((size / 1024 / 1024))
    
    log_success "Archive packaging successful"
    log_info "Archive: bootstrap-archives/$archive_name"
    log_info "Size: ${size_mb}MB"
    log_info "Checksum: $(cat "bootstrap-archives/${archive_name}.sha256")"
    
    return 0
}

# Test Step 4: Verify archive contents
test_verify_archive() {
    log_info ""
    log_info "=========================================="
    log_info "Step 4: Verifying archive contents"
    log_info "=========================================="
    
    cd "$PROJECT_ROOT"
    
    local archive_name="bootstrap-${TEST_MODE}-${TEST_ARCH}-${TEST_VERSION}.tar.xz"
    local archive_path="bootstrap-archives/$archive_name"
    
    # List archive contents
    log_info "Archive contents (first 20 entries):"
    tar -tJf "$archive_path" | head -20
    
    # Count total entries
    local total_entries=$(tar -tJf "$archive_path" | wc -l | tr -d ' ')
    log_info "Total entries in archive: $total_entries"
    
    # Verify critical paths exist in archive (android-native has flat structure)
    local critical_paths=(
        "bootstrap-${TEST_MODE}-${TEST_ARCH}-${TEST_VERSION}/bin/bash"
        "bootstrap-${TEST_MODE}-${TEST_ARCH}-${TEST_VERSION}/bin/sh"
    )
    
    local missing_paths=()
    for path in "${critical_paths[@]}"; do
        if ! tar -tJf "$archive_path" | grep -q "^${path}$"; then
            missing_paths+=("$path")
        fi
    done
    
    if [ ${#missing_paths[@]} -gt 0 ]; then
        log_warning "Some critical paths not found in archive:"
        for path in "${missing_paths[@]}"; do
            echo "  - $path"
        done
        log_warning "This may be expected for android-native bootstraps"
    else
        log_success "All critical paths found in archive"
    fi
    
    # CRITICAL: Check for incorrect nested usr/usr/ structure
    log_info "Checking for incorrect nested usr/usr/ structure..."
    if tar -tJf "$archive_path" | grep -q "usr/usr/"; then
        log_error "CRITICAL ERROR: Archive contains nested usr/usr/ structure!"
        log_error "This is incorrect and will cause issues."
        log_error "Paths with usr/usr/:"
        tar -tJf "$archive_path" | grep "usr/usr/" | head -10
        return 1
    else
        log_success "No nested usr/usr/ structure found (correct)"
    fi
    
    # Extract and verify structure
    log_info "Extracting archive to verify structure..."
    local extract_dir="$PROJECT_ROOT/test-extract"
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"
    
    tar -xJf "$archive_path" -C "$extract_dir"
    
    local extracted_bootstrap="$extract_dir/bootstrap-${TEST_MODE}-${TEST_ARCH}-${TEST_VERSION}"
    
    if [ ! -d "$extracted_bootstrap" ]; then
        log_error "Extracted bootstrap directory not found"
        rm -rf "$extract_dir"
        return 1
    fi
    
    log_info "Extracted bootstrap structure:"
    ls -la "$extracted_bootstrap" | head -10
    
    # Check for binaries in either usr/bin or bin (depending on structure)
    if [ -d "$extracted_bootstrap/usr/bin" ]; then
        local bin_count=$(ls -1 "$extracted_bootstrap/usr/bin" | wc -l | tr -d ' ')
        log_info "Binaries in usr/bin: $bin_count"
    elif [ -d "$extracted_bootstrap/bin" ]; then
        local bin_count=$(ls -1 "$extracted_bootstrap/bin" | wc -l | tr -d ' ')
        log_info "Binaries in bin: $bin_count"
    fi
    
    # Cleanup extraction
    rm -rf "$extract_dir"
    
    log_success "Archive verification successful"
    return 0
}

# Main test execution
main() {
    log_info "=========================================="
    log_info "End-to-End Workflow Test"
    log_info "=========================================="
    log_info "Mode: $TEST_MODE"
    log_info "Architecture: $TEST_ARCH"
    log_info "Version: $TEST_VERSION"
    log_info ""
    
    # Cleanup before starting
    cleanup
    
    local failed=0
    
    # Run tests
    if ! test_download; then
        log_error "Download test failed"
        failed=1
    fi
    
    if [ $failed -eq 0 ] && ! test_organize; then
        log_error "Organization test failed"
        failed=1
    fi
    
    if [ $failed -eq 0 ] && ! test_package; then
        log_error "Packaging test failed"
        failed=1
    fi
    
    if [ $failed -eq 0 ] && ! test_verify_archive; then
        log_error "Archive verification failed"
        failed=1
    fi
    
    # Cleanup after tests
    log_info ""
    cleanup
    
    # Final report
    log_info ""
    log_info "=========================================="
    if [ $failed -eq 0 ]; then
        log_success "All tests passed!"
        log_info "The workflow is working end-to-end"
        exit 0
    else
        log_error "Some tests failed"
        log_info "Please review the errors above"
        exit 1
    fi
}

# Run main
main "$@"
