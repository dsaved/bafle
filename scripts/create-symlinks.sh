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
    
    # Create parent directory if it doesn't exist
    mkdir -p "$link_dir"
    
    # If link_name exists as a directory, remove it
    if [ -d "$link_name" ] && [ ! -L "$link_name" ]; then
        log_warning "  Removing existing directory: $link_name"
        rm -rf "$link_name"
    fi
    
    # Remove existing symlink or file if it exists
    if [ -e "$link_name" ] || [ -L "$link_name" ]; then
        rm -f "$link_name"
    fi
    
    # Create symlink
    if ! ln -s "$target" "$link_name" 2>/dev/null; then
        log_error "  Failed to create symlink: $link_name -> $target"
        return 1
    fi
    
    log_info "  Created: $(basename "$link_name") -> $target"
    return 0
}

# Create shell symlinks
create_shell_symlinks() {
    local bin_dir="$BOOTSTRAP_DIR/usr/bin"
    
    log_info "Creating shell symlinks..."
    
    # sh -> bash (if bash exists)
    if [ -f "$bin_dir/bash" ]; then
        create_symlink "bash" "$bin_dir/sh" || return 1
    elif [ -f "$bin_dir/dash" ]; then
        create_symlink "dash" "$bin_dir/sh" || return 1
    else
        log_warning "No bash or dash found, cannot create sh symlink"
    fi
    
    # rbash -> bash (restricted bash)
    if [ -f "$bin_dir/bash" ]; then
        create_symlink "bash" "$bin_dir/rbash" || return 1
    fi
    
    return 0
}

# Create BusyBox symlinks
create_busybox_symlinks() {
    local bin_dir="$BOOTSTRAP_DIR/usr/bin"
    
    if [ ! -f "$bin_dir/busybox" ]; then
        log_info "BusyBox not found, skipping BusyBox symlinks"
        return 0
    fi
    
    log_info "Creating BusyBox symlinks..."
    
    # Try to get list of applets from busybox-applets.txt file first
    local applets_file=""
    if [ -f "$BOOTSTRAP_DIR/busybox-applets.txt" ]; then
        applets_file="$BOOTSTRAP_DIR/busybox-applets.txt"
        log_info "Found applets file: $applets_file"
    elif [ -f "$bin_dir/../busybox-applets.txt" ]; then
        applets_file="$bin_dir/../busybox-applets.txt"
        log_info "Found applets file: $applets_file"
    else
        log_info "No applets file found, will try to execute busybox"
    fi
    
    local applets=""
    if [ -n "$applets_file" ]; then
        applets=$(cat "$applets_file" 2>/dev/null || true)
        log_info "Using applet list from: $applets_file"
        log_info "Applet count: $(echo "$applets" | wc -l | tr -d ' ')"
    else
        # Fallback: try to execute busybox (may fail for cross-compiled binaries)
        applets=$("$bin_dir/busybox" --list 2>/dev/null || true)
    fi
    
    if [ -z "$applets" ]; then
        log_warning "Could not get BusyBox applet list"
        log_warning "Symlinks will need to be created manually or during first boot"
        return 0
    fi
    
    # Create symlinks using a more reliable method
    # Filter out busybox itself and empty lines, then create symlinks
    local temp_applets="/tmp/busybox-applets-$$.txt"
    
    # Write applets to temp file, filtering out busybox and empty lines
    if [ -n "$applets_file" ]; then
        # Read from file
        grep -v "^busybox$" "$applets_file" | grep -v "^$" > "$temp_applets" || true
    else
        # Use applets variable
        echo "$applets" | grep -v "^busybox$" | grep -v "^$" > "$temp_applets" || true
    fi
    
    # Check if temp file has content
    if [ ! -s "$temp_applets" ]; then
        log_warning "No applets found to create symlinks"
        rm -f "$temp_applets"
        return 0
    fi
    
    local created_count=0
    local failed_count=0
    
    # Read applets and create symlinks
    while IFS= read -r applet || [ -n "$applet" ]; do
        # Skip empty lines
        [ -z "$applet" ] && continue
        
        # Skip if file already exists
        if [ -f "$bin_dir/$applet" ]; then
            continue
        fi
        
        # Try to create symlink
        if ln -sf busybox "$bin_dir/$applet" 2>/dev/null; then
            ((created_count++))
            
            # Log progress every 50 applets to avoid too much output
            if [ $((created_count % 50)) -eq 0 ]; then
                log_info "  Progress: $created_count symlinks created..."
            fi
        else
            ((failed_count++))
            log_warning "  Failed to create symlink for: $applet"
        fi
    done < "$temp_applets"
    
    rm -f "$temp_applets"
    
    if [ $created_count -eq 0 ] && [ $failed_count -gt 0 ]; then
        log_error "Failed to create any symlinks ($failed_count failures)"
        return 1
    fi
    
    log_success "Created $created_count BusyBox applet symlinks"
    if [ $failed_count -gt 0 ]; then
        log_warning "Failed to create $failed_count symlinks"
    fi
}

# Create library directory symlinks
create_lib_symlinks() {
    local usr_dir="$BOOTSTRAP_DIR/usr"
    
    log_info "Creating library directory symlinks..."
    
    # lib64 -> lib (for 64-bit architectures)
    if [ -d "$usr_dir/lib" ]; then
        create_symlink "lib" "$usr_dir/lib64" || return 1
    fi
    
    # Create /lib -> usr/lib symlink at root level
    if [ -d "$usr_dir/lib" ]; then
        create_symlink "usr/lib" "$BOOTSTRAP_DIR/lib" || return 1
        create_symlink "usr/lib" "$BOOTSTRAP_DIR/lib64" || return 1
    fi
    
    return 0
}

# Create bin directory symlinks
create_bin_symlinks() {
    local usr_dir="$BOOTSTRAP_DIR/usr"
    
    log_info "Creating bin directory symlinks..."
    
    # Create /bin -> usr/bin symlink at root level
    if [ -d "$usr_dir/bin" ]; then
        create_symlink "usr/bin" "$BOOTSTRAP_DIR/bin" || return 1
    fi
    
    # Create /sbin -> usr/bin symlink
    if [ -d "$usr_dir/bin" ]; then
        create_symlink "usr/bin" "$BOOTSTRAP_DIR/sbin" || return 1
    fi
    
    return 0
}

# Create etc directory symlinks
create_etc_symlinks() {
    log_info "Creating etc directory symlinks..."
    
    # Create /etc -> usr/etc symlink at root level
    if [ -d "$BOOTSTRAP_DIR/usr/etc" ]; then
        create_symlink "usr/etc" "$BOOTSTRAP_DIR/etc" || return 1
    fi
    
    return 0
}

# Create tmp directory symlinks
create_tmp_symlinks() {
    log_info "Creating tmp directory symlinks..."
    
    # Create /tmp -> usr/tmp symlink at root level
    if [ -d "$BOOTSTRAP_DIR/usr/tmp" ]; then
        create_symlink "usr/tmp" "$BOOTSTRAP_DIR/tmp" || return 1
    fi
    
    return 0
}

# Create var directory symlinks
create_var_symlinks() {
    log_info "Creating var directory symlinks..."
    
    # Create /var -> usr/var symlink at root level
    if [ -d "$BOOTSTRAP_DIR/usr/var" ]; then
        create_symlink "usr/var" "$BOOTSTRAP_DIR/var" || return 1
    fi
    
    return 0
}

# Create common utility symlinks
create_utility_symlinks() {
    local bin_dir="$BOOTSTRAP_DIR/usr/bin"
    
    log_info "Creating utility symlinks..."
    
    # awk -> gawk (if gawk exists)
    if [ -f "$bin_dir/gawk" ] && [ ! -f "$bin_dir/awk" ]; then
        create_symlink "gawk" "$bin_dir/awk" || return 1
    fi
    
    # vi -> vim (if vim exists)
    if [ -f "$bin_dir/vim" ] && [ ! -f "$bin_dir/vi" ]; then
        create_symlink "vim" "$bin_dir/vi" || return 1
    fi
    
    # python -> python3 (if python3 exists)
    if [ -f "$bin_dir/python3" ] && [ ! -f "$bin_dir/python" ]; then
        create_symlink "python3" "$bin_dir/python" || return 1
    fi
    
    return 0
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
            create_symlink "$lib_name" "$lib_dir/$base_name" || true
        fi
    done || true
    
    return 0
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
    
    # Create all symlinks with error handling
    if ! create_shell_symlinks; then
        log_error "Failed to create shell symlinks"
        exit 1
    fi
    echo ""
    
    if ! create_busybox_symlinks; then
        log_error "Failed to create BusyBox symlinks"
        exit 1
    fi
    echo ""
    
    if ! create_utility_symlinks; then
        log_error "Failed to create utility symlinks"
        exit 1
    fi
    echo ""
    
    if ! create_lib_symlinks; then
        log_error "Failed to create library symlinks"
        exit 1
    fi
    echo ""
    
    if ! create_bin_symlinks; then
        log_error "Failed to create bin symlinks"
        exit 1
    fi
    echo ""
    
    if ! create_etc_symlinks; then
        log_error "Failed to create etc symlinks"
        exit 1
    fi
    echo ""
    
    if ! create_tmp_symlinks; then
        log_error "Failed to create tmp symlinks"
        exit 1
    fi
    echo ""
    
    if ! create_var_symlinks; then
        log_error "Failed to create var symlinks"
        exit 1
    fi
    echo ""
    
    if ! create_library_version_symlinks; then
        log_error "Failed to create library version symlinks"
        exit 1
    fi
    echo ""
    
    # Count total symlinks created
    local total_symlinks=$(find "$BOOTSTRAP_DIR" -type l 2>/dev/null | wc -l | tr -d ' ')
    
    log_success "Symlink creation completed"
    log_info "Total symlinks: $total_symlinks"
}

# Run main function
main "$@"
