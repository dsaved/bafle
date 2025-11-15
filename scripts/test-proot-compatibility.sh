#!/usr/bin/env bash

# test-proot-compatibility.sh - PRoot compatibility testing for bootstrap binaries
# Part of the GitHub Actions workflow integration

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Default values
BUILD_MODE=""
TARGET_ARCH=""
VERSION=""
BOOTSTRAP_DIR=""
OUTPUT_DIR="$PROJECT_ROOT/test-results"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging
log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_test() { echo -e "${BLUE}[TEST]${NC} $*"; }

# Usage
usage() {
    cat << EOF
Usage: $0 --mode MODE --arch ARCH --version VERSION

Test bootstrap binaries for PRoot compatibility.

OPTIONS:
    --mode MODE          Build mode (static, linux-native)
    --arch ARCH          Target architecture
    --version VERSION    Build version
    -h, --help          Show this help

EXAMPLE:
    $0 --mode static --arch arm64-v8a --version 1.0.0
EOF
    exit 0
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode) BUILD_MODE="$2"; shift 2 ;;
            --arch) TARGET_ARCH="$2"; shift 2 ;;
            --version) VERSION="$2"; shift 2 ;;
            -h|--help) usage ;;
            *) log_error "Unknown option: $1"; usage ;;
        esac
    done
    
    if [[ -z "$BUILD_MODE" ]] || [[ -z "$TARGET_ARCH" ]] || [[ -z "$VERSION" ]]; then
        log_error "Missing required arguments"
        usage
    fi
}

# Setup PRoot
setup_proot() {
    log_info "Setting up PRoot for testing..."
    
    if ! "$SCRIPT_DIR/setup-test-proot.sh" --arch "$TARGET_ARCH"; then
        log_error "Failed to setup PRoot"
        return 1
    fi
    
    log_info "PRoot setup complete"
}

# Run test command
run_test() {
    local test_name="$1"
    local command="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "Running: $test_name"
    
    if eval "$command" > /dev/null 2>&1; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ✅ PASSED"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ❌ FAILED"
        return 1
    fi
}

# Test bootstrap
test_bootstrap() {
    log_info "Testing bootstrap: $BOOTSTRAP_DIR"
    
    # Determine PRoot binary location
    local proot_bin="$PROJECT_ROOT/.cache/proot-${TARGET_ARCH}"
    
    if [[ ! -f "$proot_bin" ]]; then
        log_error "PRoot binary not found: $proot_bin"
        return 1
    fi
    
    # Basic tests
    run_test "Shell execution" \
        "$proot_bin -r '$BOOTSTRAP_DIR' /usr/bin/sh -c 'echo test'"
    
    run_test "Bash version" \
        "$proot_bin -r '$BOOTSTRAP_DIR' /usr/bin/bash --version"
    
    run_test "List binaries" \
        "$proot_bin -r '$BOOTSTRAP_DIR' /usr/bin/ls /usr/bin"
    
    run_test "File operations" \
        "$proot_bin -r '$BOOTSTRAP_DIR' /usr/bin/sh -c 'echo test > /tmp/test.txt && cat /tmp/test.txt'"
    
    run_test "Environment variables" \
        "$proot_bin -r '$BOOTSTRAP_DIR' /usr/bin/sh -c 'export TEST=value && echo \$TEST'"
    
    return 0
}

# Generate report
generate_report() {
    mkdir -p "$OUTPUT_DIR"
    
    local report_file="$OUTPUT_DIR/test-report-${BUILD_MODE}-${TARGET_ARCH}.json"
    
    cat > "$report_file" << EOF
{
  "bootstrapPath": "$BOOTSTRAP_DIR",
  "buildMode": "$BUILD_MODE",
  "architecture": "$TARGET_ARCH",
  "version": "$VERSION",
  "testDate": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "testsRun": $TESTS_RUN,
  "testsPassed": $TESTS_PASSED,
  "testsFailed": $TESTS_FAILED,
  "prootCompatible": $([ $TESTS_FAILED -eq 0 ] && echo "true" || echo "false")
}
EOF
    
    log_info "Test report saved: $report_file"
}

# Main
main() {
    log_info "PRoot Compatibility Testing"
    echo ""
    
    parse_args "$@"
    
    # Determine bootstrap directory
    BOOTSTRAP_DIR="$PROJECT_ROOT/build/${BUILD_MODE}/bootstrap-${BUILD_MODE}-${TARGET_ARCH}-${VERSION}"
    
    if [[ ! -d "$BOOTSTRAP_DIR" ]]; then
        log_error "Bootstrap directory not found: $BOOTSTRAP_DIR"
        exit 1
    fi
    
    # Setup PRoot
    if ! setup_proot; then
        exit 1
    fi
    
    # Run tests
    if ! test_bootstrap; then
        log_error "Bootstrap testing failed"
        generate_report
        exit 1
    fi
    
    # Generate report
    generate_report
    
    # Summary
    echo ""
    log_info "========================================="
    log_info "Test Summary"
    log_info "========================================="
    log_info "Tests Run:    $TESTS_RUN"
    log_info "Tests Passed: $TESTS_PASSED"
    log_info "Tests Failed: $TESTS_FAILED"
    log_info "========================================="
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_info "✅ All tests passed - Bootstrap is PRoot compatible"
        exit 0
    else
        log_error "❌ Some tests failed - Bootstrap may not be fully PRoot compatible"
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
