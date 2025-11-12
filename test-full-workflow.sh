#!/bin/bash

# Full workflow test script
# Simulates the complete GitHub Actions workflow locally

set -e
set -u
set -o pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_step() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Test version
export VERSION="1.0.0"
export REPO_NAME="dsaved/bafle"

echo ""
echo "=================================================="
echo "    Full Bootstrap Build Workflow Test"
echo "=================================================="
echo ""
echo "Version: $VERSION"
echo "Repository: $REPO_NAME"
echo ""

# Step 1: Download bootstraps
log_step "Step 1/7: Downloading Termux Bootstrap Packages"
if ./scripts/download-bootstraps.sh; then
    log_success "Bootstrap download completed"
else
    log_error "Bootstrap download failed"
    exit 1
fi

# Step 2: Package archives
log_step "Step 2/7: Packaging Bootstrap Archives"
if ./scripts/package-archives.sh "$VERSION"; then
    log_success "Archive packaging completed"
else
    log_error "Archive packaging failed"
    exit 1
fi

# Step 3: Validate archives
log_step "Step 3/7: Validating Bootstrap Archives"
if ./scripts/validate-archives.sh; then
    log_success "Archive validation completed"
else
    log_error "Archive validation failed"
    exit 1
fi

# Step 4: Generate checksums
log_step "Step 4/7: Generating Checksums and Calculating Sizes"
cd bootstrap-archives
if ../scripts/generate-checksums.sh; then
    log_success "Checksum generation completed"
    
    # Move checksums files to root
    mv checksums.txt checksums.json ../ || {
        log_error "Failed to move checksum files"
        exit 1
    }
    cd ..
else
    log_error "Checksum generation failed"
    exit 1
fi

# Step 5: Update manifest
log_step "Step 5/7: Updating Bootstrap Manifest"
CHECKSUM_DATA=$(cat checksums.json)
if ./scripts/update-manifest.sh "$VERSION" "$REPO_NAME" "$CHECKSUM_DATA"; then
    log_success "Manifest update completed"
else
    log_error "Manifest update failed"
    exit 1
fi

# Step 6: Validate manifest JSON
log_step "Step 6/7: Validating Manifest JSON Syntax"
if jq empty bootstrap-manifest.json 2>/dev/null; then
    log_success "Manifest JSON validation passed"
    echo ""
    echo "Updated manifest:"
    jq '.' bootstrap-manifest.json
else
    log_error "Manifest JSON validation failed"
    exit 1
fi

# Step 7: Summary
log_step "Step 7/7: Workflow Summary"
echo "All steps completed successfully!"
echo ""
echo "Created Assets:"
echo "  ✓ bootstrap-arm64-v8a-$VERSION.tar.gz"
echo "  ✓ bootstrap-armeabi-v7a-$VERSION.tar.gz"
echo "  ✓ bootstrap-x86_64-$VERSION.tar.gz"
echo "  ✓ bootstrap-x86-$VERSION.tar.gz"
echo "  ✓ checksums.txt"
echo "  ✓ checksums.json"
echo "  ✓ bootstrap-manifest.json (updated)"
echo ""
echo "Archive sizes:"
ls -lh bootstrap-archives/*.tar.gz | awk '{print "  " $9 ": " $5}'
echo ""
echo "Checksums:"
cat checksums.txt
echo ""
log_success "Full workflow test completed successfully!"
echo ""
echo "=================================================="
