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
PROOT_BIN=""

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
    
    # Run setup script and capture the output path
    # The setup script outputs the path as the last line to stdout
    local setup_output
    setup_output=$("$SCRIPT_DIR/setup-test-proot.sh" --arch "$TARGET_ARCH" 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "Failed to setup PRoot (exit code: $exit_code)"
        log_error "Setup script output:"
        echo "$setup_output"
        log_error "Attempting to install PRoot via apt-get..."
        
        # Try to install PRoot as fallback
        if command -v apt-get &> /dev/null; then
            if sudo apt-get install -y proot &> /dev/null; then
                log_info "PRoot installed successfully"
                # Try setup again
                setup_output=$("$SCRIPT_DIR/setup-test-proot.sh" --arch "$TARGET_ARCH" 2>&1)
                exit_code=$?
                if [[ $exit_code -ne 0 ]]; then
                    log_error "Setup still failed after installing PRoot"
                    echo "$setup_output"
                    return 1
                fi
            else
                log_error "Failed to install PRoot via apt-get"
                return 1
            fi
        else
            return 1
        fi
    fi
    
    # Extract the path (last line of output)
    local proot_path
    proot_path=$(echo "$setup_output" | tail -1)
    
    # Validate the path
    if [[ ! -f "$proot_path" ]] || [[ ! -x "$proot_path" ]]; then
        log_error "PRoot binary not found or not executable: $proot_path"
        log_error "Full setup output:"
        echo "$setup_output"
        return 1
    fi
    
    # Store the path for use in tests
    PROOT_BIN="$proot_path"
    
    log_info "PRoot setup complete"
    log_info "PRoot binary: $PROOT_BIN"
}

# Run test command
run_test() {
    local test_name="$1"
    local command="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "Running: $test_name"
    
    # Capture output and error
    local output
    local exit_code
    output=$(eval "$command" 2>&1)
    exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ✅ PASSED"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ❌ FAILED (exit code: $exit_code)"
        if [[ -n "$output" ]]; then
            echo "     Output: ${output:0:200}"  # Show first 200 chars
        fi
        return 1
    fi
}

# Test bootstrap
test_bootstrap() {
    log_info "Testing bootstrap: $BOOTSTRAP_DIR"
    
    # Use the PRoot binary path from setup
    if [[ -z "$PROOT_BIN" ]] || [[ ! -f "$PROOT_BIN" ]]; then
        log_error "PRoot binary not available: $PROOT_BIN"
        return 1
    fi
    
    log_info "Using PRoot: $PROOT_BIN"
    
    # Determine if we need QEMU for cross-architecture testing
    local host_arch=$(uname -m)
    local qemu_arg=""
    
    # Map target architecture to QEMU binary
    case "$TARGET_ARCH" in
        arm64-v8a)
            if [[ "$host_arch" != "aarch64" ]]; then
                qemu_arg="-q /usr/bin/qemu-aarch64-static"
                log_info "Cross-arch testing: using qemu-aarch64-static"
            fi
            ;;
        armeabi-v7a)
            if [[ "$host_arch" != "armv7l" ]]; then
                qemu_arg="-q /usr/bin/qemu-arm-static"
                log_info "Cross-arch testing: using qemu-arm-static"
            fi
            ;;
        x86_64)
            if [[ "$host_arch" != "x86_64" ]]; then
                qemu_arg="-q /usr/bin/qemu-x86_64-static"
                log_info "Cross-arch testing: using qemu-x86_64-static"
            fi
            ;;
        x86)
            if [[ "$host_arch" != "i686" ]] && [[ "$host_arch" != "i386" ]]; then
                qemu_arg="-q /usr/bin/qemu-i386-static"
                log_info "Cross-arch testing: using qemu-i386-static"
            fi
            ;;
    esac
    
    # Basic tests
    run_test "Shell execution" \
        "$PROOT_BIN $qemu_arg -r '$BOOTSTRAP_DIR' /usr/bin/sh -c 'echo test'"
    
    run_test "Bash version" \
        "$PROOT_BIN $qemu_arg -r '$BOOTSTRAP_DIR' /usr/bin/bash --version"
    
    # List binaries - check if ls produces output (ignore errors about missing symlinks)
    run_test "List binaries" \
        "$PROOT_BIN $qemu_arg -r '$BOOTSTRAP_DIR' /usr/bin/ls /usr/bin 2>/dev/null | grep -q bash"
    
    run_test "File operations" \
        "$PROOT_BIN $qemu_arg -r '$BOOTSTRAP_DIR' /usr/bin/sh -c 'echo test > /tmp/test.txt && cat /tmp/test.txt'"
    
    run_test "Environment variables" \
        "$PROOT_BIN $qemu_arg -r '$BOOTSTRAP_DIR' /usr/bin/sh -c 'export TEST=value && echo \$TEST'"
    
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
    BOOTSTRAP_DIR="$PROJECT_ROOT/build/bootstrap-${BUILD_MODE}-${TARGET_ARCH}-${VERSION}"
    
    if [[ ! -d "$BOOTSTRAP_DIR" ]]; then
        log_error "Bootstrap directory not found: $BOOTSTRAP_DIR"
        log_info "Looking for bootstrap in: $BOOTSTRAP_DIR"
        log_info "Available directories in build/:"
        ls -la "$PROJECT_ROOT/build/" 2>/dev/null || true
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
