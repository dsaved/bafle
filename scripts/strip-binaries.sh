#!/bin/bash

# Binary Stripping Script
# Strips debug symbols from all binaries in a bootstrap directory
# Usage: ./strip-binaries.sh <bootstrap_dir>

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if bootstrap directory is provided
if [ $# -eq 0 ]; then
    log_error "Bootstrap directory is required"
    echo "Usage: $0 <bootstrap_dir>"
    echo "Example: $0 build/bootstrap-static-arm64-v8a-1.0.0"
    exit 1
fi

BOOTSTRAP_DIR="$1"

# Validate bootstrap directory exists
if [ ! -d "$BOOTSTRAP_DIR" ]; then
    log_error "Bootstrap directory not found: $BOOTSTRAP_DIR"
    exit 1
fi

log_info "Stripping debug symbols from binaries in: $BOOTSTRAP_DIR"

# Check if strip command is available
if ! command -v strip &> /dev/null; then
    log_error "strip command not found"
    log_error "Please install binutils package"
    exit 1
fi

# Counter for stripped files
stripped_count=0
failed_count=0
skipped_count=0

# Function to strip a single file
strip_file() {
    local file="$1"
    local filename=$(basename "$file")
    
    # Check if file is executable or a library
    if [ ! -x "$file" ] && [[ ! "$file" =~ \.(so|a)(\.[0-9]+)*$ ]]; then
        return 0
    fi
    
    # Check if file is actually a binary (not a script)
    if file "$file" | grep -q "script\|text"; then
        return 0
    fi
    
    # Try to strip the file
    if strip --strip-all "$file" 2>/dev/null; then
        stripped_count=$((stripped_count + 1))
        return 0
    else
        # Some files might not be strippable (already stripped, or special format)
        # Try with less aggressive stripping
        if strip --strip-unneeded "$file" 2>/dev/null; then
            stripped_count=$((stripped_count + 1))
            return 0
        else
            failed_count=$((failed_count + 1))
            return 1
        fi
    fi
}

# Strip binaries in usr/bin
if [ -d "${BOOTSTRAP_DIR}/usr/bin" ]; then
    log_info "Stripping binaries in usr/bin..."
    
    while IFS= read -r -d '' file; do
        if strip_file "$file"; then
            : # Success, counter already incremented
        else
            log_warn "  Failed to strip: $(basename "$file")"
        fi
    done < <(find "${BOOTSTRAP_DIR}/usr/bin" -type f -print0 2>/dev/null)
fi

# Strip binaries in bin (root level)
if [ -d "${BOOTSTRAP_DIR}/bin" ]; then
    log_info "Stripping binaries in bin..."
    
    while IFS= read -r -d '' file; do
        if strip_file "$file"; then
            : # Success, counter already incremented
        else
            log_warn "  Failed to strip: $(basename "$file")"
        fi
    done < <(find "${BOOTSTRAP_DIR}/bin" -type f -print0 2>/dev/null)
fi

# Strip libraries in usr/lib
if [ -d "${BOOTSTRAP_DIR}/usr/lib" ]; then
    log_info "Stripping libraries in usr/lib..."
    
    while IFS= read -r -d '' file; do
        # Only strip .so and .a files
        if [[ "$file" =~ \.(so|a)(\.[0-9]+)*$ ]]; then
            if strip_file "$file"; then
                : # Success, counter already incremented
            else
                log_warn "  Failed to strip: $(basename "$file")"
            fi
        fi
    done < <(find "${BOOTSTRAP_DIR}/usr/lib" -type f -print0 2>/dev/null)
fi

# Strip libraries in lib (root level)
if [ -d "${BOOTSTRAP_DIR}/lib" ]; then
    log_info "Stripping libraries in lib..."
    
    while IFS= read -r -d '' file; do
        # Only strip .so and .a files
        if [[ "$file" =~ \.(so|a)(\.[0-9]+)*$ ]]; then
            if strip_file "$file"; then
                : # Success, counter already incremented
            else
                log_warn "  Failed to strip: $(basename "$file")"
            fi
        fi
    done < <(find "${BOOTSTRAP_DIR}/lib" -type f -print0 2>/dev/null)
fi

# Strip executables in usr/libexec
if [ -d "${BOOTSTRAP_DIR}/usr/libexec" ]; then
    log_info "Stripping executables in usr/libexec..."
    
    while IFS= read -r -d '' file; do
        if strip_file "$file"; then
            : # Success, counter already incremented
        else
            log_warn "  Failed to strip: $(basename "$file")"
        fi
    done < <(find "${BOOTSTRAP_DIR}/usr/libexec" -type f -print0 2>/dev/null)
fi

# Strip executables in libexec (root level)
if [ -d "${BOOTSTRAP_DIR}/libexec" ]; then
    log_info "Stripping executables in libexec..."
    
    while IFS= read -r -d '' file; do
        if strip_file "$file"; then
            : # Success, counter already incremented
        else
            log_warn "  Failed to strip: $(basename "$file")"
        fi
    done < <(find "${BOOTSTRAP_DIR}/libexec" -type f -print0 2>/dev/null)
fi

# Report results
echo ""
log_info "Stripping complete!"
log_info "  Successfully stripped: $stripped_count files"

if [ $failed_count -gt 0 ]; then
    log_warn "  Failed to strip: $failed_count files"
fi

# Exit with success even if some files failed to strip
# (they might already be stripped or in a format that doesn't support stripping)
exit 0
