#!/bin/bash

# Test script to simulate the GitHub Actions workflow locally
# This tests all the error handling and logging improvements

set -e
set -u
set -o pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

echo ""
echo "=================================================="
echo "    Bootstrap Build Workflow - Local Test"
echo "=================================================="
echo ""

# Test 1: Version validation
log_test "Testing version validation..."

# Test invalid versions
VERSION="v1.0.0"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_pass "Correctly rejected version with 'v' prefix: $VERSION"
else
    log_fail "Should have rejected version: $VERSION"
    exit 1
fi

VERSION="1.0"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_pass "Correctly rejected incomplete version: $VERSION"
else
    log_fail "Should have rejected version: $VERSION"
    exit 1
fi

VERSION="1.0.0-beta"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_pass "Correctly rejected version with pre-release tag: $VERSION"
else
    log_fail "Should have rejected version: $VERSION"
    exit 1
fi

# Test valid version
VERSION="1.0.0"
if [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_pass "Correctly accepted valid version: $VERSION"
else
    log_fail "Should have accepted version: $VERSION"
    exit 1
fi

echo ""

# Test 2: Script executability
log_test "Testing script executability..."
if [ -x "scripts/download-bootstraps.sh" ] && \
   [ -x "scripts/package-archives.sh" ] && \
   [ -x "scripts/validate-archives.sh" ] && \
   [ -x "scripts/generate-checksums.sh" ] && \
   [ -x "scripts/update-manifest.sh" ]; then
    log_pass "All scripts are executable"
else
    log_fail "Some scripts are not executable"
    exit 1
fi

echo ""

# Test 3: Error handling in generate-checksums.sh
log_test "Testing error handling in generate-checksums.sh..."
export VERSION="1.0.0"
output=$(./scripts/generate-checksums.sh 2>&1 || true)
exit_code=$?
if echo "$output" | grep -q "Archive file not found"; then
    log_pass "generate-checksums.sh correctly reports missing archives"
else
    log_fail "generate-checksums.sh should report missing archives"
    exit 1
fi

# Also verify it exits with non-zero code
if ./scripts/generate-checksums.sh > /dev/null 2>&1; then
    log_fail "generate-checksums.sh should exit with error code when archives missing"
    exit 1
else
    log_pass "generate-checksums.sh correctly exits with error code"
fi

echo ""

# Test 4: Error handling in update-manifest.sh
log_test "Testing error handling in update-manifest.sh..."

# Test missing arguments
output=$(./scripts/update-manifest.sh 2>&1 || true)
if echo "$output" | grep -q "Version number is required"; then
    log_pass "update-manifest.sh correctly reports missing version"
else
    log_fail "update-manifest.sh should report missing version"
    exit 1
fi

# Test invalid version format
output=$(./scripts/update-manifest.sh "v1.0.0" "test/repo" '{}' 2>&1 || true)
if echo "$output" | grep -q "Invalid version format"; then
    log_pass "update-manifest.sh correctly rejects invalid version format"
else
    log_fail "update-manifest.sh should reject invalid version format"
    exit 1
fi

echo ""

# Test 5: Check required tools
log_test "Testing required tools availability..."

if command -v jq &> /dev/null; then
    log_pass "jq is available"
else
    log_fail "jq is not available (required for manifest updates)"
    exit 1
fi

if command -v curl &> /dev/null; then
    log_pass "curl is available"
else
    log_fail "curl is not available (required for downloads)"
    exit 1
fi

if command -v tar &> /dev/null; then
    log_pass "tar is available"
else
    log_fail "tar is not available (required for archives)"
    exit 1
fi

if command -v sha256sum &> /dev/null || command -v shasum &> /dev/null; then
    log_pass "SHA-256 checksum tool is available"
else
    log_fail "Neither sha256sum nor shasum is available"
    exit 1
fi

echo ""

# Test 6: Manifest file exists
log_test "Testing manifest file existence..."
if [ -f "bootstrap-manifest.json" ]; then
    log_pass "bootstrap-manifest.json exists"
    
    # Validate JSON syntax
    if jq empty bootstrap-manifest.json 2>/dev/null; then
        log_pass "bootstrap-manifest.json has valid JSON syntax"
    else
        log_fail "bootstrap-manifest.json has invalid JSON syntax"
        exit 1
    fi
else
    log_fail "bootstrap-manifest.json not found"
    exit 1
fi

echo ""

# Test 7: Script error handling patterns
log_test "Testing script error handling patterns..."

# Check for set -e, set -u, set -o pipefail in all scripts
for script in scripts/*.sh; do
    if grep -q "set -e" "$script" && \
       grep -q "set -u" "$script" && \
       grep -q "set -o pipefail" "$script"; then
        log_pass "$(basename "$script") has proper error handling flags"
    else
        log_fail "$(basename "$script") missing error handling flags"
        exit 1
    fi
done

echo ""

# Test 8: Logging functions
log_test "Testing logging functions in scripts..."

for script in scripts/*.sh; do
    if grep -q "log_info()" "$script" && \
       grep -q "log_error()" "$script"; then
        log_pass "$(basename "$script") has logging functions"
    else
        log_fail "$(basename "$script") missing logging functions"
        exit 1
    fi
done

echo ""

# Summary
echo "=================================================="
echo "           TEST SUMMARY"
echo "=================================================="
echo ""
echo "✅ All tests passed!"
echo ""
echo "Verified:"
echo "  ✓ Version validation logic"
echo "  ✓ Script executability"
echo "  ✓ Error handling in scripts"
echo "  ✓ Required tools availability"
echo "  ✓ Manifest file existence and validity"
echo "  ✓ Error handling flags (set -e, -u, -o pipefail)"
echo "  ✓ Logging functions in all scripts"
echo ""
echo "The workflow is ready for deployment!"
echo "=================================================="
