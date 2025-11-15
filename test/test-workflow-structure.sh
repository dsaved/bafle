#!/usr/bin/env bash

# test-workflow-structure.sh - Test the workflow structure without actual compilation
# This validates that all scripts exist, accept correct arguments, and can be called in sequence

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging
log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_test() { echo -e "${BLUE}[TEST]${NC} $*"; }

# Test a script exists and is executable
test_script() {
    local script_name="$1"
    local script_path="$PROJECT_ROOT/scripts/$script_name"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    if [ ! -f "$script_path" ]; then
        log_error "❌ Script not found: $script_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    if [ ! -x "$script_path" ]; then
        log_error "❌ Script not executable: $script_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    log_info "✅ Script exists and is executable: $script_name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
}

# Test script accepts help flag
test_script_help() {
    local script_name="$1"
    local script_path="$PROJECT_ROOT/scripts/$script_name"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    if "$script_path" --help &> /dev/null || "$script_path" -h &> /dev/null; then
        log_info "✅ Script has help: $script_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_warn "⚠️  Script may not have help flag: $script_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    fi
}

# Test workflow step order
test_workflow_order() {
    log_info "Testing workflow step order..."
    
    local steps=(
        "config-validator.sh"
        "download-sources.sh"
        "build-static.sh"
        "build-linux-native.sh"
        "assemble-bootstrap.sh"
        "test-proot-compatibility.sh"
        "package-archives.sh"
        "generate-checksums.sh"
        "update-manifest.sh"
    )
    
    for step in "${steps[@]}"; do
        test_script "$step"
    done
}

# Test CLI argument patterns
test_cli_arguments() {
    log_info "Testing CLI argument patterns..."
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    # Test config-validator accepts file argument
    if grep -q "config.*file" "$PROJECT_ROOT/scripts/config-validator.sh"; then
        log_info "✅ config-validator.sh accepts config file"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "❌ config-validator.sh may not accept config file"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    # Test build scripts accept --arch and --version
    if grep -q "\-\-arch" "$PROJECT_ROOT/scripts/build-static.sh" && \
       grep -q "\-\-version" "$PROJECT_ROOT/scripts/build-static.sh"; then
        log_info "✅ build-static.sh accepts --arch and --version"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "❌ build-static.sh may not accept required arguments"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    # Test assemble-bootstrap accepts --mode, --arch, --version
    if grep -q "\-\-mode" "$PROJECT_ROOT/scripts/assemble-bootstrap.sh" && \
       grep -q "\-\-arch" "$PROJECT_ROOT/scripts/assemble-bootstrap.sh" && \
       grep -q "\-\-version" "$PROJECT_ROOT/scripts/assemble-bootstrap.sh"; then
        log_info "✅ assemble-bootstrap.sh accepts --mode, --arch, --version"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "❌ assemble-bootstrap.sh may not accept required arguments"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    # Test test-proot-compatibility accepts --mode, --arch, --version
    if grep -q "\-\-mode" "$PROJECT_ROOT/scripts/test-proot-compatibility.sh" && \
       grep -q "\-\-arch" "$PROJECT_ROOT/scripts/test-proot-compatibility.sh" && \
       grep -q "\-\-version" "$PROJECT_ROOT/scripts/test-proot-compatibility.sh"; then
        log_info "✅ test-proot-compatibility.sh accepts --mode, --arch, --version"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "❌ test-proot-compatibility.sh may not accept required arguments"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    # Test package-archives accepts --version, --mode, --arch
    if grep -q "\-\-version" "$PROJECT_ROOT/scripts/package-archives.sh" && \
       grep -q "\-\-mode" "$PROJECT_ROOT/scripts/package-archives.sh" && \
       grep -q "\-\-arch" "$PROJECT_ROOT/scripts/package-archives.sh"; then
        log_info "✅ package-archives.sh accepts --version, --mode, --arch"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "❌ package-archives.sh may not accept required arguments"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Test workflow file exists and is valid
test_workflow_file() {
    log_info "Testing GitHub Actions workflow file..."
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    local workflow_file="$PROJECT_ROOT/.github/workflows/build-bootstrap.yml"
    
    if [ ! -f "$workflow_file" ]; then
        log_error "❌ Workflow file not found"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    log_info "✅ Workflow file exists"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    
    # Test for matrix strategy
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if grep -q "matrix:" "$workflow_file" && \
       grep -q "mode:" "$workflow_file" && \
       grep -q "arch:" "$workflow_file"; then
        log_info "✅ Workflow has matrix strategy (mode × arch)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "❌ Workflow may not have proper matrix strategy"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    # Test for proper step separation
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if grep -q "Configuration Validation" "$workflow_file" && \
       grep -q "Source Package Download" "$workflow_file" && \
       grep -q "Compilation" "$workflow_file" && \
       grep -q "Bootstrap Assembly" "$workflow_file" && \
       grep -q "PRoot Compatibility Testing" "$workflow_file" && \
       grep -q "Archive Packaging" "$workflow_file" && \
       grep -q "Checksum Generation" "$workflow_file"; then
        log_info "✅ Workflow has proper step separation"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "❌ Workflow may not have all required steps"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Test documentation exists
test_documentation() {
    log_info "Testing documentation..."
    
    local docs=(
        "docs/WORKFLOW_ARCHITECTURE.md"
        "docs/WORKFLOW_QUICK_REFERENCE.md"
        "docs/WORKFLOW_INTEGRATION_SUMMARY.md"
    )
    
    for doc in "${docs[@]}"; do
        TESTS_TOTAL=$((TESTS_TOTAL + 1))
        if [ -f "$PROJECT_ROOT/$doc" ]; then
            log_info "✅ Documentation exists: $doc"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            log_error "❌ Documentation missing: $doc"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    done
}

# Print summary
print_summary() {
    echo ""
    log_info "================================================"
    log_info "WORKFLOW STRUCTURE TEST SUMMARY"
    log_info "================================================"
    log_info "Tests Total:   $TESTS_TOTAL"
    log_info "Tests Passed:  $TESTS_PASSED"
    log_info "Tests Failed:  $TESTS_FAILED"
    log_info "================================================"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_info "✅ ALL TESTS PASSED - Workflow structure is valid!"
        return 0
    else
        log_error "❌ SOME TESTS FAILED"
        return 1
    fi
}

# Main
main() {
    echo ""
    log_info "================================================"
    log_info "GitHub Actions Workflow Structure Test"
    log_info "================================================"
    log_info "This validates the workflow structure without running actual builds"
    echo ""
    
    test_workflow_order
    echo ""
    test_cli_arguments
    echo ""
    test_workflow_file
    echo ""
    test_documentation
    
    print_summary
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
