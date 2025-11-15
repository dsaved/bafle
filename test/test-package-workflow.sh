#!/usr/bin/env bash

# Quick Package Workflow Test
# Tests organize and package steps with a mock bootstrap structure

set -e
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TEST_MODE="android-native"
TEST_ARCH="arm64-v8a"
TEST_VERSION="2.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
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

# Create mock bootstrap structure
create_mock_bootstrap() {
    log_info "Creating mock bootstrap structure..."
    
    local mock_dir="$PROJECT_ROOT/bootstrap-downloads/${TEST_ARCH}"
    rm -rf "$mock_dir"
    mkdir -p "$mock_dir"
    
    # Create flat structure (like Termux bootstrap)
    mkdir -p "$mock_dir/bin"
    mkdir -p "$mock_dir/lib"
    mkdir -p "$mock_dir/etc"
    mkdir -p "$mock_dir/var"
    mkdir -p "$mock_dir/tmp"
    
    # Create mock binaries
    echo '#!/bin/sh' > "$mock_dir/bin/sh"
    echo '#!/bin/bash' > "$mock_dir/bin/bash"
    echo '#!/bin/sh' > "$mock_dir/bin/ls"
    echo '#!/bin/sh' > "$mock_dir/bin/cat"
    
    chmod +x "$mock_dir/bin"/*
    
    # Create SYMLINKS.txt
    echo "Mock bootstrap symlinks" > "$mock_dir/SYMLINKS.txt"
    
    log_success "Mock bootstrap created at $mock_dir"
    log_info "Structure:"
    ls -la "$mock_dir"
}

# Test organize step
test_organize() {
    log_info ""
    log_info "=========================================="
    log_info "Testing: Organize Bootstrap"
    log_info "=========================================="
    
    BOOTSTRAP_NAME="bootstrap-${TEST_MODE}-${TEST_ARCH}-${TEST_VERSION}"
    SOURCE_DIR="$PROJECT_ROOT/bootstrap-downloads/${TEST_ARCH}"
    DEST_DIR="$PROJECT_ROOT/build/${BOOTSTRAP_NAME}"
    
    if [ ! -d "$SOURCE_DIR" ]; then
        log_error "Source directory not found: $SOURCE_DIR"
        return 1
    fi
    
    mkdir -p "$PROJECT_ROOT/build"
    rm -rf "$DEST_DIR"
    mv "$SOURCE_DIR" "$DEST_DIR"
    
    if [ ! -d "$DEST_DIR" ]; then
        log_error "Failed to move bootstrap"
        return 1
    fi
    
    # Verify structure
    if [ ! -d "$DEST_DIR/bin" ]; then
        log_error "bin directory not found"
        return 1
    fi
    
    log_success "Bootstrap organized successfully"
    log_info "Location: $DEST_DIR"
    log_info "Structure:"
    ls -la "$DEST_DIR"
    
    return 0
}

# Test package step
test_package() {
    log_info ""
    log_info "=========================================="
    log_info "Testing: Package Archive"
    log_info "=========================================="
    
    if ! bash "$PROJECT_ROOT/scripts/package-archives.sh" \
        --version "$TEST_VERSION" \
        --mode "$TEST_MODE" \
        --arch "$TEST_ARCH"; then
        log_error "Packaging failed"
        return 1
    fi
    
    local archive_name="bootstrap-${TEST_MODE}-${TEST_ARCH}-${TEST_VERSION}.tar.xz"
    if [ ! -f "$PROJECT_ROOT/bootstrap-archives/$archive_name" ]; then
        log_error "Archive not created"
        return 1
    fi
    
    log_success "Archive created successfully"
    log_info "Archive: $archive_name"
    
    return 0
}

# Test archive structure
test_archive_structure() {
    log_info ""
    log_info "=========================================="
    log_info "Testing: Archive Structure"
    log_info "=========================================="
    
    local archive_name="bootstrap-${TEST_MODE}-${TEST_ARCH}-${TEST_VERSION}.tar.xz"
    local archive_path="$PROJECT_ROOT/bootstrap-archives/$archive_name"
    
    log_info "Archive contents (first 30 entries):"
    tar -tJf "$archive_path" | head -30
    
    # CRITICAL: Check for nested usr/usr/
    log_info ""
    log_info "Checking for nested usr/usr/ structure..."
    if tar -tJf "$archive_path" | grep -q "usr/usr/"; then
        log_error "CRITICAL: Archive contains nested usr/usr/ structure!"
        tar -tJf "$archive_path" | grep "usr/usr/" | head -10
        return 1
    fi
    
    log_success "No nested usr/usr/ structure (correct)"
    
    # Verify expected structure
    log_info ""
    log_info "Verifying expected paths..."
    local expected_paths=(
        "bootstrap-${TEST_MODE}-${TEST_ARCH}-${TEST_VERSION}/bin/sh"
        "bootstrap-${TEST_MODE}-${TEST_ARCH}-${TEST_VERSION}/bin/bash"
    )
    
    for path in "${expected_paths[@]}"; do
        if tar -tJf "$archive_path" | grep -q "^${path}$"; then
            log_info "  ✓ Found: $path"
        else
            log_error "  ✗ Missing: $path"
            return 1
        fi
    done
    
    log_success "Archive structure validated"
    return 0
}

# Cleanup
cleanup() {
    log_info "Cleaning up..."
    rm -rf "$PROJECT_ROOT/bootstrap-downloads"
    rm -rf "$PROJECT_ROOT/build/bootstrap-${TEST_MODE}-${TEST_ARCH}-${TEST_VERSION}"
    rm -rf "$PROJECT_ROOT/bootstrap-archives/bootstrap-${TEST_MODE}-${TEST_ARCH}-${TEST_VERSION}"*
}

# Main
main() {
    log_info "=========================================="
    log_info "Package Workflow Test"
    log_info "=========================================="
    log_info "Mode: $TEST_MODE"
    log_info "Arch: $TEST_ARCH"
    log_info "Version: $TEST_VERSION"
    log_info ""
    
    cleanup
    
    local failed=0
    
    create_mock_bootstrap
    
    if ! test_organize; then
        log_error "Organize test failed"
        failed=1
    fi
    
    if [ $failed -eq 0 ] && ! test_package; then
        log_error "Package test failed"
        failed=1
    fi
    
    if [ $failed -eq 0 ] && ! test_archive_structure; then
        log_error "Archive structure test failed"
        failed=1
    fi
    
    cleanup
    
    log_info ""
    log_info "=========================================="
    if [ $failed -eq 0 ]; then
        log_success "All tests passed!"
        log_info "The workflow is working correctly"
        exit 0
    else
        log_error "Tests failed"
        exit 1
    fi
}

main "$@"
