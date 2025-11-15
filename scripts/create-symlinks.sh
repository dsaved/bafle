#!/usr/bin/env bash
# create-symlinks.sh - Set up necessary symlinks in the bootstrap
# This script creates essential symlinks for shell, libraries, and utilities

set -e

BOOTSTRAP_DIR="${BOOTSTRAP_DIR:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create a symlink with validation
create_symlink() {
    local target=$1
    local link_name=$2
    local link_dir=$(dirname "$link_name")
    
    # Create directory if it doesn't exist
    mkdir -p "$link_dir"
    
    # Remove existing symlink or file if it exists
    if [ -e "$link_name" ] || [ -L "$link_name" ]; then
        rm -f "$link_name"
    fi
    
    # Create symlink
    ln -s "$target" "$link_name"
    
    log_info "  Created: $(basename "$link_name") -> $target"
}

# Create shell symlinks
create_shell_symlinks() {
    local bin_dir="$BOOTSTRAP_DIR/usr/bin"
    
    log_info "Creating shell symlinks..."
    
    # sh -> bash (if bash exists)
    if [ -f "$bin_dir/bash" ]; then
        create_symlink "bash" "$bin_dir/sh"
    elif [ -f "$bin_dir/dash" ]; then
        create_symlink "dash" "$bin_dir/sh"
    else
        log_warning "No bash or dash found, cannot create sh symlink"
    fi
    
    # rbash -> bash (restricted bash)
    if [ -f "$bin_dir/bash" ]; then
        create_symlink "bash" "$bin_dir/rbash"
    fi
}

# Create BusyBox symlinks
create_busybox_symlinks() {
    local bin_dir="$BOOTSTRAP_DIR/usr/bin"
    
    if [ ! -f "$bin_dir/busybox" ]; then
        log_info "BusyBox not found, skipping BusyBox symlinks"
        return 0
    fi
    
    log_info "Creating BusyBox symlinks..."
    
    # Get list of applets from busybox
    local applets=$("$bin_dir/busybox" --list 2>/dev/null || true)
    
    if [ -z "$applets" ]; then
        log_warning "Could not get BusyBox applet list"
        return 0
    fi
    
    local created_count=0
    
    # Create symlinks for each applet (only if binary doesn't already exist)
    while IFS= read -r applet; do
        if [ -n "$applet" ] && [ ! -f "$bin_dir/$applet" ]; then
            create_symlink "busybox" "$bin_dir/$applet"
            ((created_count++))
        fi
    done <<< "$applets"
    
    log_success "Created $created_count BusyBox applet symlinks"
}

# Create library directory symlinks
create_lib_symlinks() {
    local usr_dir="$BOOTSTRAP_DIR/usr"
    
    log_info "Creating library directory symlinks..."
    
    # lib64 -> lib (for 64-bit architectures)
    if [ -d "$usr_dir/lib" ]; then
        create_symlink "lib" "$usr_dir/lib64"
    fi
    
    # Create /lib -> usr/lib symlink at root level
    if [ -d "$usr_dir/lib" ]; then
        create_symlink "usr/lib" "$BOOTSTRAP_DIR/lib"
        create_symlink "usr/lib" "$BOOTSTRAP_DIR/lib64"
    fi
}

# Create bin directory symlinks
create_bin_symlinks() {
    local usr_dir="$BOOTSTRAP_DIR/usr"
    
    log_info "Creating bin directory symlinks..."
    
    # Create /bin -> usr/bin symlink at root level
    if [ -d "$usr_dir/bin" ]; then
        create_symlink "usr/bin" "$BOOTSTRAP_DIR/bin"
    fi
    
    # Create /sbin -> usr/bin symlink
    if [ -d "$usr_dir/bin" ]; then
        create_symlink "usr/bin" "$BOOTSTRAP_DIR/sbin"
    fi
}

# Create etc directory symlinks
create_etc_symlinks() {
    log_info "Creating etc directory symlinks..."
    
    # Create /etc -> usr/etc symlink at root level
    if [ -d "$BOOTSTRAP_DIR/usr/etc" ]; then
        create_symlink "usr/etc" "$BOOTSTRAP_DIR/etc"
    fi
}

# Create tmp directory symlinks
create_tmp_symlinks() {
    log_info "Creating tmp directory symlinks..."
    
    # Create /tmp -> usr/tmp symlink at root level
    if [ -d "$BOOTSTRAP_DIR/usr/tmp" ]; then
        create_symlink "usr/tmp" "$BOOTSTRAP_DIR/tmp"
    fi
}

# Create var directory symlinks
create_var_symlinks() {
    log_info "Creating var directory symlinks..."
    
    # Create /var -> usr/var symlink at root level
    if [ -d "$BOOTSTRAP_DIR/usr/var" ]; then
        create_symlink "usr/var" "$BOOTSTRAP_DIR/var"
    fi
}

# Create common utility symlinks
create_utility_symlinks() {
    local bin_dir="$BOOTSTRAP_DIR/usr/bin"
    
    log_info "Creating utility symlinks..."
    
    # awk -> gawk (if gawk exists)
    if [ -f "$bin_dir/gawk" ] && [ ! -f "$bin_dir/awk" ]; then
        create_symlink "gawk" "$bin_dir/awk"
    fi
    
    # vi -> vim (if vim exists)
    if [ -f "$bin_dir/vim" ] && [ ! -f "$bin_dir/vi" ]; then
        create_symlink "vim" "$bin_dir/vi"
    fi
    
    # python -> python3 (if python3 exists)
    if [ -f "$bin_dir/python3" ] && [ ! -f "$bin_dir/python" ]; then
        create_symlink "python3" "$bin_dir/python"
    fi
}

# Create library symlinks for common library names
create_library_version_symlinks() {
    local lib_dir="$BOOTSTRAP_DIR/usr/lib"
    
    if [ ! -d "$lib_dir" ]; then
        return 0
    fi
    
    log_info "Creating library version symlinks..."
    
    # Find all versioned libraries and create unversioned symlinks
    find "$lib_dir" -type f -name "*.so.*" 2>/dev/null | while read -r lib; do
        local lib_name=$(basename "$lib")
        local base_name=$(echo "$lib_name" | sed 's/\.so\..*/\.so/')
        
        # Create .so symlink if it doesn't exist
        if [ ! -e "$lib_dir/$base_name" ]; then
            create_symlink "$lib_name" "$lib_dir/$base_name"
        fi
    done || true
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [BOOTSTRAP_DIR]

Create necessary symlinks in the bootstrap directory.

Arguments:
  BOOTSTRAP_DIR         Path to bootstrap directory (can also use BOOTSTRAP_DIR env var)

Environment Variables:
  BOOTSTRAP_DIR         Bootstrap directory path

Examples:
  $0 /path/to/bootstrap
  BOOTSTRAP_DIR=/path/to/bootstrap $0

EOF
}

# Main function
main() {
    # Get bootstrap directory from argument or environment
    if [ $# -gt 0 ]; then
        BOOTSTRAP_DIR="$1"
    fi
    
    # Validate bootstrap directory
    if [ -z "$BOOTSTRAP_DIR" ]; then
        log_error "Bootstrap directory not specified"
        show_usage
        exit 1
    fi
    
    if [ ! -d "$BOOTSTRAP_DIR" ]; then
        log_error "Bootstrap directory not found: $BOOTSTRAP_DIR"
        exit 1
    fi
    
    log_info "Creating symlinks in: $BOOTSTRAP_DIR"
    echo ""
    
    # Create all symlinks
    create_shell_symlinks
    echo ""
    
    create_busybox_symlinks
    echo ""
    
    create_utility_symlinks
    echo ""
    
    create_lib_symlinks
    echo ""
    
    create_bin_symlinks
    echo ""
    
    create_etc_symlinks
    echo ""
    
    create_tmp_symlinks
    echo ""
    
    create_var_symlinks
    echo ""
    
    create_library_version_symlinks
    echo ""
    
    # Count total symlinks created
    local total_symlinks=$(find "$BOOTSTRAP_DIR" -type l 2>/dev/null | wc -l | tr -d ' ')
    
    log_success "Symlink creation completed"
    log_info "Total symlinks: $total_symlinks"
}

# Run main function
main "$@"
