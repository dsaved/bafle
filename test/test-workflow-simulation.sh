#!/usr/bin/env bash

# Workflow Simulation Test
# Simulates the exact GitHub Actions workflow steps for android-native mode

set -e
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Simulate workflow environment variables
export VERSION="2.0.0"
export BUILD_MODE="android-native"
export TARGET_ARCH="arm64-v8a"
export RUN_TESTS="false"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_step() {
    echo ""
    echo "================================================"
    echo "$1"
    echo "================================================"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Cleanup
cleanup() {
    log_info "Cleaning up test artifacts..."
    rm -rf "$PROJECT_ROOT/bootstrap-downloads"
    rm -rf "$PROJECT_ROOT/build/bootstrap-${BUILD_MODE}-${TARGET_ARCH}-${VERSION}"
    rm -rf "$PROJECT_ROOT/bootstrap-archives/bootstrap-${BUILD_MODE}-${TARGET_ARCH}-${VERSION}"*
}

# Create mock bootstrap (simulating download)
create_mock_download() {
    log_step "Step 2-3/7: Download Android-Native Bootstrap (SIMULATED)"
    echo "⚠️  WARNING: android-native mode is deprecated"
    echo "These binaries are NOT PRoot compatible"
    echo ""
    
    log_info "Creating mock downloaded bootstrap..."
    
    local download_dir="$PROJECT_ROOT/bootstrap-downloads/${TARGET_ARCH}"
    mkdir -p "$download_dir"
    
    # Simulate Termux bootstrap structure (flat)
    mkdir -p "$download_dir/bin"
    mkdir -p "$download_dir/lib"
    mkdir -p "$download_dir/libexec"
    mkdir -p "$download_dir/etc"
    mkdir -p "$download_dir/share"
    mkdir -p "$download_dir/var"
    mkdir -p "$download_dir/tmp"
    
    # Create mock binaries
    for bin in sh bash ls cat grep sed awk; do
        echo "#!/bin/sh" > "$download_dir/bin/$bin"
        chmod +x "$download_dir/bin/$bin"
    done
    
    echo "Mock bootstrap symlinks" > "$download_dir/SYMLINKS.txt"
    
    log_success "Android-native bootstrap downloaded (simulated)"
}

# Step 4: Organize
step_organize() {
    log_step "Step 4/7: Organize Android-Native Bootstrap"
    
    # This is the exact code from the workflow
    BOOTSTRAP_NAME="bootstrap-${BUILD_MODE}-${TARGET_ARCH}-${VERSION}"
    SOURCE_DIR="bootstrap-downloads/${TARGET_ARCH}"
    DEST_DIR="build/${BOOTSTRAP_NAME}"
    
    echo "Moving bootstrap from $SOURCE_DIR to $DEST_DIR"
    
    if [ ! -d "$SOURCE_DIR" ]; then
        echo "❌ Error: Downloaded bootstrap not found at $SOURCE_DIR"
        exit 1
    fi
    
    mkdir -p build
    mv "$SOURCE_DIR" "$DEST_DIR"
    
    echo "✅ Bootstrap organized at $DEST_DIR"
    echo ""
    echo "Bootstrap structure:"
    ls -la "$DEST_DIR"
}

# Step 6: Package
step_package() {
    log_step "Step 6/7: Archive Packaging"
    
    ./scripts/package-archives.sh --version "$VERSION" --mode "$BUILD_MODE" --arch "$TARGET_ARCH"
    
    # Verify archive structure (exact code from workflow)
    ARCHIVE_NAME="bootstrap-${BUILD_MODE}-${TARGET_ARCH}-${VERSION}.tar.xz"
    ARCHIVE_PATH="bootstrap-archives/${ARCHIVE_NAME}"
    
    echo ""
    echo "Verifying archive structure..."
    
    # Check for incorrect nested usr/usr/ structure
    if tar -tJf "$ARCHIVE_PATH" | grep -q "usr/usr/"; then
        echo "❌ CRITICAL ERROR: Archive contains nested usr/usr/ structure!"
        echo "This is incorrect and will cause issues."
        echo "Paths with usr/usr/:"
        tar -tJf "$ARCHIVE_PATH" | grep "usr/usr/" | head -10
        exit 1
    fi
    
    echo "✅ Archive structure validated (no nested usr/usr/)"
    echo "✅ Archive packaged"
}

# Step 7: Checksums
step_checksums() {
    log_step "Step 7/7: Checksum Generation"
    
    cd bootstrap-archives
    ../scripts/generate-checksums.sh --version "$VERSION" --mode "$BUILD_MODE" --arch "$TARGET_ARCH"
    cd ..
    
    echo "✅ Checksums generated"
}

# Main
main() {
    log_info "=========================================="
    log_info "GitHub Actions Workflow Simulation"
    log_info "=========================================="
    log_info "Mode: $BUILD_MODE"
    log_info "Architecture: $TARGET_ARCH"
    log_info "Version: $VERSION"
    
    cleanup
    
    # Run workflow steps
    create_mock_download
    step_organize
    step_package
    step_checksums
    
    # Final verification
    log_step "Final Verification"
    
    local archive_name="bootstrap-${BUILD_MODE}-${TARGET_ARCH}-${VERSION}.tar.xz"
    
    if [ -f "bootstrap-archives/$archive_name" ]; then
        log_success "Archive created: $archive_name"
        
        local size=$(stat -f%z "bootstrap-archives/$archive_name" 2>/dev/null || stat -c%s "bootstrap-archives/$archive_name" 2>/dev/null)
        log_info "Size: $size bytes"
        
        if [ -f "bootstrap-archives/${archive_name}.sha256" ]; then
            log_success "Checksum file created"
            log_info "Checksum: $(cat "bootstrap-archives/${archive_name}.sha256")"
        fi
        
        echo ""
        log_info "Archive structure:"
        tar -tJf "bootstrap-archives/$archive_name" | head -20
    else
        echo "❌ Archive not found!"
        exit 1
    fi
    
    cleanup
    
    echo ""
    log_step "WORKFLOW SIMULATION COMPLETE"
    log_success "All steps executed successfully!"
    log_info "The workflow is ready for GitHub Actions"
}

main "$@"
