#!/usr/bin/env bash

# test-github-workflow-simulation.sh - Simulate the complete GitHub Actions workflow locally
# This script tests the exact same flow that runs in GitHub Actions

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test configuration
TEST_VERSION="0.0.1"
TEST_MODE="static"
TEST_ARCH="arm64-v8a"
RUN_TESTS=true

# Counters
STEPS_TOTAL=0
STEPS_PASSED=0
STEPS_FAILED=0

# Logging
log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

# Run a step and track results
run_step() {
    local step_name="$1"
    shift
    
    STEPS_TOTAL=$((STEPS_TOTAL + 1))
    
    echo ""
    log_step "================================================"
    log_step "Step $STEPS_TOTAL: $step_name"
    log_step "================================================"
    
    if "$@"; then
        STEPS_PASSED=$((STEPS_PASSED + 1))
        log_info "✅ $step_name - PASSED"
        return 0
    else
        STEPS_FAILED=$((STEPS_FAILED + 1))
        log_error "❌ $step_name - FAILED"
        return 1
    fi
}

# Clean up previous test artifacts
cleanup() {
    log_info "Cleaning up previous test artifacts..."
    
    rm -rf "$PROJECT_ROOT/build/static/bootstrap-static-${TEST_ARCH}-${TEST_VERSION}"
    rm -rf "$PROJECT_ROOT/bootstrap-archives/bootstrap-static-${TEST_ARCH}-${TEST_VERSION}.tar.xz"
    rm -rf "$PROJECT_ROOT/bootstrap-archives/checksums-static-${TEST_ARCH}.txt"
    rm -rf "$PROJECT_ROOT/bootstrap-archives/checksums-static-${TEST_ARCH}.json"
    rm -rf "$PROJECT_ROOT/test-results/test-report-static-${TEST_ARCH}.json"
    
    log_info "Cleanup complete"
}

# Step 1: Setup Build Environment
setup_environment() {
    log_info "Setting up build environment..."
    
    # Check required tools
    local missing_critical=()
    local missing_optional=()
    
    # Critical tools
    for tool in gcc make curl jq tar file; do
        if ! command -v "$tool" &> /dev/null; then
            missing_critical+=("$tool")
        fi
    done
    
    # Optional tools (wget can be replaced by curl)
    if ! command -v wget &> /dev/null; then
        log_warn "wget not found, will use curl as fallback"
    fi
    
    # Check for xz (required for .tar.xz)
    if ! command -v xz &> /dev/null && ! command -v xzcat &> /dev/null; then
        missing_critical+=("xz")
    fi
    
    if [ ${#missing_critical[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_critical[*]}"
        log_error "Please install them first"
        log_error ""
        log_error "On macOS: brew install ${missing_critical[*]}"
        log_error "On Ubuntu: sudo apt-get install ${missing_critical[*]}"
        return 1
    fi
    
    # Make scripts executable
    chmod +x "$PROJECT_ROOT/scripts"/*.sh
    
    log_info "Build environment ready"
    return 0
}

# Step 2: Configuration Validation
validate_configuration() {
    log_info "Validating configuration..."
    
    # Create temporary config
    cat > "$PROJECT_ROOT/build-config-test.json" << EOF
{
  "version": "$TEST_VERSION",
  "buildMode": "$TEST_MODE",
  "architectures": ["$TEST_ARCH"],
  "compression": "xz",
  "stripSymbols": true,
  "runTests": $RUN_TESTS,
  "staticOptions": {
    "libc": "musl",
    "optimizationLevel": "Os"
  },
  "packages": {
    "busybox": {
      "version": "1.36.1",
      "source": "https://busybox.net/downloads/busybox-1.36.1.tar.bz2",
      "checksum": "b8cc24c9574d809e7279c3be349795c5d5ceb6fdf19ca709f80cde50e47de314",
      "buildStatic": true
    },
    "bash": {
      "version": "5.2",
      "source": "https://ftp.gnu.org/gnu/bash/bash-5.2.tar.gz",
      "checksum": "a139c166df7ff4471c5e0733051642ee5556c1cc8a4a78f145583c5c81ab32fb",
      "buildStatic": true
    }
  }
}
EOF
    
    "$PROJECT_ROOT/scripts/config-validator.sh" "$PROJECT_ROOT/build-config-test.json"
    
    log_info "Configuration validated"
    return 0
}

# Step 3: Source Package Download
download_sources() {
    log_info "Downloading source packages..."
    
    export CONFIG_FILE="$PROJECT_ROOT/build-config-test.json"
    
    "$PROJECT_ROOT/scripts/download-sources.sh"
    
    # Verify sources were downloaded
    if [ ! -d "$PROJECT_ROOT/.cache/sources" ]; then
        log_error "Source cache directory not created"
        return 1
    fi
    
    log_info "Sources downloaded"
    return 0
}

# Step 4: Compilation
compile_binaries() {
    log_info "Compiling binaries for $TEST_MODE mode..."
    
    export TARGET_ARCH="$TEST_ARCH"
    export BUILD_VERSION="$TEST_VERSION"
    
    if [ "$TEST_MODE" = "static" ]; then
        "$PROJECT_ROOT/scripts/build-static.sh" --arch "$TEST_ARCH" --version "$TEST_VERSION"
    elif [ "$TEST_MODE" = "linux-native" ]; then
        "$PROJECT_ROOT/scripts/build-linux-native.sh" --android-arch "$TEST_ARCH" --version "$TEST_VERSION"
    else
        log_error "Unsupported build mode: $TEST_MODE"
        return 1
    fi
    
    # Verify binaries were created
    local build_dir="$PROJECT_ROOT/build/$TEST_MODE"
    if [ ! -d "$build_dir" ]; then
        log_error "Build directory not created: $build_dir"
        return 1
    fi
    
    log_info "Compilation complete"
    return 0
}

# Step 5: Bootstrap Assembly
assemble_bootstrap() {
    log_info "Assembling bootstrap..."
    
    "$PROJECT_ROOT/scripts/assemble-bootstrap.sh" \
        --mode "$TEST_MODE" \
        --arch "$TEST_ARCH" \
        --version "$TEST_VERSION"
    
    # Verify bootstrap was created
    local bootstrap_dir="$PROJECT_ROOT/build/$TEST_MODE/bootstrap-${TEST_MODE}-${TEST_ARCH}-${TEST_VERSION}"
    if [ ! -d "$bootstrap_dir" ]; then
        log_error "Bootstrap directory not created: $bootstrap_dir"
        return 1
    fi
    
    # Verify critical files exist
    if [ ! -f "$bootstrap_dir/usr/bin/bash" ]; then
        log_error "Critical binary missing: bash"
        return 1
    fi
    
    log_info "Bootstrap assembled"
    return 0
}

# Step 6: PRoot Compatibility Testing
test_proot_compatibility() {
    if [ "$RUN_TESTS" != "true" ] || [ "$TEST_MODE" = "android-native" ]; then
        log_info "Skipping PRoot tests"
        return 0
    fi
    
    log_info "Testing PRoot compatibility..."
    
    "$PROJECT_ROOT/scripts/test-proot-compatibility.sh" \
        --mode "$TEST_MODE" \
        --arch "$TEST_ARCH" \
        --version "$TEST_VERSION"
    
    # Verify test report was created
    local report_file="$PROJECT_ROOT/test-results/test-report-${TEST_MODE}-${TEST_ARCH}.json"
    if [ ! -f "$report_file" ]; then
        log_error "Test report not created: $report_file"
        return 1
    fi
    
    # Check if tests passed
    local tests_failed=$(jq -r '.testsFailed' "$report_file")
    if [ "$tests_failed" != "0" ]; then
        log_error "PRoot tests failed: $tests_failed failures"
        return 1
    fi
    
    log_info "PRoot tests passed"
    return 0
}

# Step 7: Archive Packaging
package_archive() {
    log_info "Packaging archive..."
    
    "$PROJECT_ROOT/scripts/package-archives.sh" \
        --version "$TEST_VERSION" \
        --mode "$TEST_MODE" \
        --arch "$TEST_ARCH"
    
    # Verify archive was created
    local archive_file="$PROJECT_ROOT/bootstrap-archives/bootstrap-${TEST_MODE}-${TEST_ARCH}-${TEST_VERSION}.tar.xz"
    if [ ! -f "$archive_file" ]; then
        log_error "Archive not created: $archive_file"
        return 1
    fi
    
    # Verify archive is not empty
    local archive_size=$(stat -f%z "$archive_file" 2>/dev/null || stat -c%s "$archive_file" 2>/dev/null)
    if [ "$archive_size" -lt 1000000 ]; then
        log_error "Archive seems too small: $archive_size bytes"
        return 1
    fi
    
    log_info "Archive packaged (size: $archive_size bytes)"
    return 0
}

# Step 8: Checksum Generation
generate_checksums() {
    log_info "Generating checksums..."
    
    cd "$PROJECT_ROOT/bootstrap-archives"
    
    "$PROJECT_ROOT/scripts/generate-checksums.sh" \
        --version "$TEST_VERSION" \
        --mode "$TEST_MODE" \
        --arch "$TEST_ARCH"
    
    cd "$PROJECT_ROOT"
    
    # Verify checksum files were created
    local checksum_txt="$PROJECT_ROOT/bootstrap-archives/checksums-${TEST_MODE}-${TEST_ARCH}.txt"
    local checksum_json="$PROJECT_ROOT/bootstrap-archives/checksums-${TEST_MODE}-${TEST_ARCH}.json"
    
    if [ ! -f "$checksum_txt" ]; then
        log_error "Checksum text file not created: $checksum_txt"
        return 1
    fi
    
    if [ ! -f "$checksum_json" ]; then
        log_error "Checksum JSON file not created: $checksum_json"
        return 1
    fi
    
    # Verify JSON is valid
    if ! jq empty "$checksum_json" 2>/dev/null; then
        log_error "Checksum JSON is invalid"
        return 1
    fi
    
    log_info "Checksums generated"
    return 0
}

# Step 9: Verify Archive Integrity
verify_archive() {
    log_info "Verifying archive integrity..."
    
    local archive_file="$PROJECT_ROOT/bootstrap-archives/bootstrap-${TEST_MODE}-${TEST_ARCH}-${TEST_VERSION}.tar.xz"
    local extract_dir="$PROJECT_ROOT/build/test-extract"
    
    # Clean extract directory
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"
    
    # Extract archive
    if ! tar -xJf "$archive_file" -C "$extract_dir"; then
        log_error "Failed to extract archive"
        return 1
    fi
    
    # Verify extracted contents
    local bootstrap_dir="$extract_dir/bootstrap-${TEST_MODE}-${TEST_ARCH}-${TEST_VERSION}"
    if [ ! -d "$bootstrap_dir" ]; then
        log_error "Bootstrap directory not found in archive"
        return 1
    fi
    
    # Verify critical binaries
    local critical_bins=("bash" "sh")
    for bin in "${critical_bins[@]}"; do
        if [ ! -f "$bootstrap_dir/usr/bin/$bin" ]; then
            log_error "Critical binary missing in archive: $bin"
            return 1
        fi
    done
    
    # Verify checksum
    cd "$PROJECT_ROOT/bootstrap-archives"
    if ! sha256sum -c "checksums-${TEST_MODE}-${TEST_ARCH}.txt" 2>/dev/null; then
        log_error "Checksum verification failed"
        return 1
    fi
    cd "$PROJECT_ROOT"
    
    log_info "Archive integrity verified"
    return 0
}

# Print summary
print_summary() {
    echo ""
    log_info "================================================"
    log_info "WORKFLOW SIMULATION SUMMARY"
    log_info "================================================"
    log_info "Version:       $TEST_VERSION"
    log_info "Mode:          $TEST_MODE"
    log_info "Architecture:  $TEST_ARCH"
    log_info "Steps Total:   $STEPS_TOTAL"
    log_info "Steps Passed:  $STEPS_PASSED"
    log_info "Steps Failed:  $STEPS_FAILED"
    log_info "================================================"
    
    if [ $STEPS_FAILED -eq 0 ]; then
        log_info "✅ ALL STEPS PASSED - Workflow simulation successful!"
        log_info ""
        log_info "Generated artifacts:"
        log_info "  - Bootstrap: build/$TEST_MODE/bootstrap-${TEST_MODE}-${TEST_ARCH}-${TEST_VERSION}/"
        log_info "  - Archive: bootstrap-archives/bootstrap-${TEST_MODE}-${TEST_ARCH}-${TEST_VERSION}.tar.xz"
        log_info "  - Checksums: bootstrap-archives/checksums-${TEST_MODE}-${TEST_ARCH}.{txt,json}"
        if [ "$RUN_TESTS" = "true" ]; then
            log_info "  - Test Report: test-results/test-report-${TEST_MODE}-${TEST_ARCH}.json"
        fi
        return 0
    else
        log_error "❌ WORKFLOW SIMULATION FAILED"
        log_error "$STEPS_FAILED out of $STEPS_TOTAL steps failed"
        return 1
    fi
}

# Main execution
main() {
    echo ""
    log_info "================================================"
    log_info "GitHub Actions Workflow Simulation"
    log_info "================================================"
    log_info "This script simulates the exact workflow that runs in GitHub Actions"
    echo ""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version) TEST_VERSION="$2"; shift 2 ;;
            --mode) TEST_MODE="$2"; shift 2 ;;
            --arch) TEST_ARCH="$2"; shift 2 ;;
            --no-tests) RUN_TESTS=false; shift ;;
            --help)
                cat << EOF
Usage: $0 [OPTIONS]

Simulate the GitHub Actions workflow locally for testing.

OPTIONS:
    --version VERSION    Test version (default: 0.0.1)
    --mode MODE         Build mode (default: static)
    --arch ARCH         Architecture (default: arm64-v8a)
    --no-tests          Skip PRoot tests
    --help              Show this help

EXAMPLES:
    $0
    $0 --mode static --arch arm64-v8a
    $0 --version 1.0.0 --no-tests

EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    log_info "Test Configuration:"
    log_info "  Version: $TEST_VERSION"
    log_info "  Mode: $TEST_MODE"
    log_info "  Architecture: $TEST_ARCH"
    log_info "  Run Tests: $RUN_TESTS"
    echo ""
    
    # Cleanup previous artifacts
    cleanup
    
    # Run workflow steps
    run_step "Setup Build Environment" setup_environment || exit 1
    run_step "Configuration Validation" validate_configuration || exit 1
    run_step "Source Package Download" download_sources || exit 1
    run_step "Compilation" compile_binaries || exit 1
    run_step "Bootstrap Assembly" assemble_bootstrap || exit 1
    run_step "PRoot Compatibility Testing" test_proot_compatibility || exit 1
    run_step "Archive Packaging" package_archive || exit 1
    run_step "Checksum Generation" generate_checksums || exit 1
    run_step "Archive Integrity Verification" verify_archive || exit 1
    
    # Print summary
    print_summary
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
