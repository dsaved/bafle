#!/usr/bin/env bash

# cleanup-project.sh - Clean up unused files and test artifacts
# Keeps only essential files needed for GitHub Actions workflow

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Dry run mode
DRY_RUN=false

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up unused files and test artifacts.

OPTIONS:
    --dry-run    Show what would be deleted without actually deleting
    --help       Show this help

WHAT GETS DELETED:
    - Old test scripts (keeping only workflow simulation tests)
    - Build artifacts (build/, bootstrap-downloads/)
    - Test caches (.test-cache/)
    - Temporary config files (build-config-test.json)
    - Old checksums (checksums.txt, checksums.json)

WHAT GETS KEPT:
    - All scripts in scripts/
    - GitHub Actions workflow
    - Documentation
    - Main config files
    - Source cache (.cache/sources/)
    - test-workflow-structure.sh (quick validation)
    - test-github-workflow-simulation.sh (full e2e test)

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --help) usage ;;
        *) log_error "Unknown option: $1"; usage ;;
    esac
done

# Remove function
remove_item() {
    local item="$1"
    local full_path="$PROJECT_ROOT/$item"
    
    if [ ! -e "$full_path" ]; then
        return 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_warn "[DRY RUN] Would delete: $item"
        return 0
    fi
    
    if [ -d "$full_path" ]; then
        rm -rf "$full_path"
        log_info "Deleted directory: $item"
    else
        rm -f "$full_path"
        log_info "Deleted file: $item"
    fi
}

main() {
    echo ""
    log_info "================================================"
    log_info "Project Cleanup"
    log_info "================================================"
    
    if [ "$DRY_RUN" = true ]; then
        log_warn "DRY RUN MODE - No files will be deleted"
    fi
    
    echo ""
    log_info "Removing old test scripts..."
    
    # Remove old test scripts (keep only the two main ones)
    remove_item "test/test-android-native-deprecation.sh"
    remove_item "test/test-assemble-bootstrap.sh"
    remove_item "test/test-build-performance.sh"
    remove_item "test/test-full-workflow.sh"
    remove_item "test/test-linux-native-scripts.sh"
    remove_item "test/test-proot-compatibility-system.sh"
    remove_item "test/test-proot-compatibility.sh"
    remove_item "test/test-static-build-scripts.sh"
    remove_item "test/test-workflow.sh"
    
    echo ""
    log_info "Removing build artifacts..."
    
    # Remove build artifacts
    remove_item "build"
    remove_item "bootstrap-downloads"
    remove_item ".test-cache"
    
    echo ""
    log_info "Removing temporary files..."
    
    # Remove temporary config files
    remove_item "build-config-test.json"
    
    # Remove old checksums (workflow generates new ones)
    remove_item "checksums.txt"
    remove_item "checksums.json"
    
    # Clean bootstrap-archives but keep the directory
    if [ -d "$PROJECT_ROOT/bootstrap-archives" ]; then
        if [ "$DRY_RUN" = true ]; then
            log_warn "[DRY RUN] Would clean: bootstrap-archives/"
        else
            find "$PROJECT_ROOT/bootstrap-archives" -type f -name "*.tar.xz" -delete 2>/dev/null || true
            find "$PROJECT_ROOT/bootstrap-archives" -type f -name "checksums-*.txt" -delete 2>/dev/null || true
            find "$PROJECT_ROOT/bootstrap-archives" -type f -name "checksums-*.json" -delete 2>/dev/null || true
            log_info "Cleaned: bootstrap-archives/"
        fi
    fi
    
    echo ""
    log_info "================================================"
    log_info "Cleanup Summary"
    log_info "================================================"
    
    if [ "$DRY_RUN" = true ]; then
        log_warn "DRY RUN completed - no files were deleted"
        log_info "Run without --dry-run to actually delete files"
    else
        log_info "Cleanup completed successfully"
        
        # Show disk space saved
        echo ""
        log_info "Remaining directories:"
        du -sh "$PROJECT_ROOT"/{.cache,scripts,docs,test,.github} 2>/dev/null || true
    fi
    
    echo ""
    log_info "Kept essential files:"
    log_info "  ✓ scripts/ (all build scripts)"
    log_info "  ✓ .github/workflows/ (GitHub Actions)"
    log_info "  ✓ docs/ (documentation)"
    log_info "  ✓ test/test-workflow-structure.sh (quick test)"
    log_info "  ✓ test/test-github-workflow-simulation.sh (full test)"
    log_info "  ✓ .cache/sources/ (source packages cache)"
    log_info "  ✓ build-config*.json (configuration files)"
    
    echo ""
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
