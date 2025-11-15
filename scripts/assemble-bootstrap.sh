#!/usr/bin/env bash
# assemble-bootstrap.sh - Create the final bootstrap directory structure
# This script assembles the final bootstrap with binaries, libraries, and configuration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build}"
CONFIG_FILE="${CONFIG_FILE:-$PROJECT_ROOT/build-config.json}"

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

# Create bootstrap directory structure
create_directory_structure() {
    local bootstrap_dir=$1
    
    log_info "Creating bootstrap directory structure..."
    
    # Create main directories
    mkdir -p "$bootstrap_dir/usr/bin"
    mkdir -p "$bootstrap_dir/usr/lib"
    mkdir -p "$bootstrap_dir/usr/etc"
    mkdir -p "$bootstrap_dir/usr/tmp"
    mkdir -p "$bootstrap_dir/usr/var"
    mkdir -p "$bootstrap_dir/usr/var/log"
    mkdir -p "$bootstrap_dir/usr/var/run"
    
    # Set proper permissions
    chmod 755 "$bootstrap_dir/usr"
    chmod 755 "$bootstrap_dir/usr/bin"
    chmod 755 "$bootstrap_dir/usr/lib"
    chmod 755 "$bootstrap_dir/usr/etc"
    chmod 1777 "$bootstrap_dir/usr/tmp"  # Sticky bit for tmp
    chmod 755 "$bootstrap_dir/usr/var"
    chmod 755 "$bootstrap_dir/usr/var/log"
    chmod 755 "$bootstrap_dir/usr/var/run"
    
    log_success "Directory structure created"
}

# Install binaries from build output
install_binaries() {
    local source_dir=$1
    local dest_dir=$2
    
    log_info "Installing binaries from $source_dir to $dest_dir..."
    
    if [ ! -d "$source_dir" ]; then
        log_error "Source directory not found: $source_dir"
        return 1
    fi
    
    local installed_count=0
    
    # Find and copy all files (we'll check if they're executable)
    while IFS= read -r binary; do
        # Skip if not a regular file
        [ -f "$binary" ] || continue
        
        local binary_name=$(basename "$binary")
        
        # Copy binary
        cp "$binary" "$dest_dir/$binary_name"
        
        # Set executable permissions
        chmod 755 "$dest_dir/$binary_name"
        
        ((installed_count++))
        log_info "  Installed: $binary_name"
    done < <(find "$source_dir" -maxdepth 1 -type f 2>/dev/null || true)
    
    if [ $installed_count -eq 0 ]; then
        log_warning "No binaries found in $source_dir"
        return 1
    fi
    
    log_success "Installed $installed_count binaries"
    return 0
}

# Install libraries for linux-native mode
install_libraries() {
    local source_dir=$1
    local dest_dir=$2
    
    log_info "Installing libraries from $source_dir to $dest_dir..."
    
    if [ ! -d "$source_dir" ]; then
        log_warning "Source directory not found: $source_dir (skipping library installation)"
        return 0
    fi
    
    local installed_count=0
    
    # Copy all shared libraries and dynamic linker
    while IFS= read -r lib; do
        local lib_name=$(basename "$lib")
        
        # Copy library
        cp -P "$lib" "$dest_dir/"
        
        # Set proper permissions (644 for libraries, 755 for linker)
        if [[ "$lib_name" == ld-* ]] || [[ "$lib_name" == ld.so* ]]; then
            chmod 755 "$dest_dir/$lib_name"
        else
            chmod 644 "$dest_dir/$lib_name"
        fi
        
        ((installed_count++))
    done < <(find "$source_dir" -type f \( -name "*.so*" -o -name "ld-*" \) 2>/dev/null || true)
    
    # Also copy symlinks
    while IFS= read -r link; do
        local link_name=$(basename "$link")
        cp -P "$link" "$dest_dir/"
        ((installed_count++))
    done < <(find "$source_dir" -type l \( -name "*.so*" -o -name "ld-*" \) 2>/dev/null || true)
    
    if [ $installed_count -eq 0 ]; then
        log_warning "No libraries found in $source_dir"
    else
        log_success "Installed $installed_count libraries and symlinks"
    fi
    
    return 0
}

# Create symlinks
create_symlinks() {
    local bootstrap_dir=$1
    
    log_info "Creating symlinks..."
    
    # Export bootstrap directory for symlink script
    export BOOTSTRAP_DIR="$bootstrap_dir"
    
    # Run symlink creation script
    if bash "$SCRIPT_DIR/create-symlinks.sh"; then
        log_success "Symlinks created"
        return 0
    else
        log_error "Failed to create symlinks"
        return 1
    fi
}

# Setup environment files
setup_environment() {
    local bootstrap_dir=$1
    
    log_info "Setting up environment files..."
    
    # Export bootstrap directory for environment setup script
    export BOOTSTRAP_DIR="$bootstrap_dir"
    
    # Run environment setup script
    if bash "$SCRIPT_DIR/setup-environment.sh"; then
        log_success "Environment files created"
        return 0
    else
        log_error "Failed to setup environment"
        return 1
    fi
}

# Generate SYMLINKS.txt documentation
generate_symlinks_doc() {
    local bootstrap_dir=$1
    local output_file="$bootstrap_dir/SYMLINKS.txt"
    
    log_info "Generating SYMLINKS.txt documentation..."
    
    {
        echo "Bootstrap Symlinks Documentation"
        echo "================================="
        echo ""
        echo "This file documents all symbolic links in the bootstrap."
        echo "Generated on: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
        echo ""
        echo "Symlinks:"
        echo "---------"
        echo ""
        
        # Find all symlinks in bootstrap
        find "$bootstrap_dir" -type l | sort | while read -r link; do
            local link_path="${link#$bootstrap_dir}"
            local target=$(readlink "$link")
            echo "$link_path -> $target"
        done
        
    } > "$output_file"
    
    log_success "SYMLINKS.txt generated"
}

# Validate bootstrap structure
validate_bootstrap() {
    local bootstrap_dir=$1
    
    log_info "Validating bootstrap structure..."
    
    local errors=()
    
    # Check required directories
    local required_dirs=("usr/bin" "usr/lib" "usr/etc" "usr/tmp" "usr/var")
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$bootstrap_dir/$dir" ]; then
            errors+=("Missing required directory: $dir")
        fi
    done
    
    # Check for at least one binary
    local bin_count=$(find "$bootstrap_dir/usr/bin" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$bin_count" -eq 0 ]; then
        errors+=("No binaries found in usr/bin")
    fi
    
    # Check for shell
    if [ ! -f "$bootstrap_dir/usr/bin/sh" ] && [ ! -L "$bootstrap_dir/usr/bin/sh" ]; then
        errors+=("No shell (sh) found in usr/bin")
    fi
    
    # Report validation results
    if [ ${#errors[@]} -gt 0 ]; then
        log_error "Bootstrap validation failed:"
        for error in "${errors[@]}"; do
            echo "  - $error"
        done
        return 1
    fi
    
    log_success "Bootstrap validation passed"
    return 0
}

# Generate assembly report
generate_assembly_report() {
    local bootstrap_dir=$1
    local report_file="$bootstrap_dir/ASSEMBLY_REPORT.txt"
    
    log_info "Generating assembly report..."
    
    {
        echo "Bootstrap Assembly Report"
        echo "========================="
        echo ""
        echo "Assembly Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
        echo "Bootstrap Directory: $bootstrap_dir"
        echo ""
        echo "Directory Structure:"
        echo "-------------------"
        tree -L 2 "$bootstrap_dir" 2>/dev/null || find "$bootstrap_dir" -maxdepth 2 -type d | sort
        echo ""
        echo "Binaries (usr/bin):"
        echo "-------------------"
        
        if [ -d "$bootstrap_dir/usr/bin" ]; then
            find "$bootstrap_dir/usr/bin" -type f -executable | while read -r binary; do
                local size=$(stat -f%z "$binary" 2>/dev/null || stat -c%s "$binary" 2>/dev/null || echo "unknown")
                local size_kb=$(echo "scale=2; $size / 1024" | bc 2>/dev/null || echo "?")
                echo "  $(basename "$binary"): ${size_kb} KB"
            done
        fi
        
        echo ""
        echo "Libraries (usr/lib):"
        echo "--------------------"
        
        if [ -d "$bootstrap_dir/usr/lib" ]; then
            local lib_count=$(find "$bootstrap_dir/usr/lib" -type f -name "*.so*" 2>/dev/null | wc -l | tr -d ' ')
            echo "  Total libraries: $lib_count"
            
            # List dynamic linker if present
            find "$bootstrap_dir/usr/lib" -type f -name "ld-*" 2>/dev/null | while read -r linker; do
                echo "  Dynamic linker: $(basename "$linker")"
            done
        fi
        
        echo ""
        echo "Symlinks:"
        echo "---------"
        
        local symlink_count=$(find "$bootstrap_dir" -type l 2>/dev/null | wc -l | tr -d ' ')
        echo "  Total symlinks: $symlink_count"
        
        echo ""
        echo "Total Size:"
        echo "-----------"
        local total_size=$(du -sh "$bootstrap_dir" 2>/dev/null | awk '{print $1}')
        echo "  $total_size"
        
    } > "$report_file"
    
    log_success "Assembly report saved to $report_file"
    cat "$report_file"
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Assemble the final bootstrap directory structure with binaries and libraries.

Options:
  --mode MODE           Build mode (static, linux-native, android-native)
  --arch ARCH           Target architecture (arm64-v8a, armeabi-v7a, x86_64, x86)
  --version VERSION     Bootstrap version (default: 1.0.0)
  --build-dir DIR       Build directory (default: build/)
  --output-dir DIR      Output directory for bootstrap (default: bootstrap-archives/)
  --config FILE         Path to build configuration file (default: build-config.json)
  --help                Show this help message

Environment Variables:
  BUILD_DIR             Override build directory
  CONFIG_FILE           Override configuration file

Examples:
  $0 --mode static --arch arm64-v8a --version 1.0.0
  $0 --mode linux-native --arch armeabi-v7a

EOF
}

# Main function
main() {
    local build_mode=""
    local arch=""
    local version="1.0.0"
    local output_base_dir="$PROJECT_ROOT/build"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mode)
                build_mode="$2"
                shift 2
                ;;
            --arch)
                arch="$2"
                shift 2
                ;;
            --version)
                version="$2"
                shift 2
                ;;
            --build-dir)
                BUILD_DIR="$2"
                shift 2
                ;;
            --output-dir)
                output_base_dir="$2"
                shift 2
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate required arguments
    if [ -z "$build_mode" ]; then
        log_error "Build mode is required (--mode)"
        show_usage
        exit 1
    fi
    
    if [ -z "$arch" ]; then
        log_error "Architecture is required (--arch)"
        show_usage
        exit 1
    fi
    
    # Validate build mode
    case "$build_mode" in
        static|linux-native|android-native)
            ;;
        *)
            log_error "Invalid build mode: $build_mode"
            log_error "Valid modes: static, linux-native, android-native"
            exit 1
            ;;
    esac
    
    # Determine source directories based on build mode and architecture
    local source_bin_dir="$BUILD_DIR/${build_mode}-${arch}/bin"
    local source_lib_dir="$BUILD_DIR/${build_mode}-${arch}/lib"
    
    # Fallback to non-architecture-specific directory if it doesn't exist
    if [ ! -d "$source_bin_dir" ]; then
        source_bin_dir="$BUILD_DIR/$build_mode/bin"
        source_lib_dir="$BUILD_DIR/$build_mode/lib"
    fi
    
    # Create bootstrap directory name
    local bootstrap_name="bootstrap-${build_mode}-${arch}-${version}"
    local bootstrap_dir="$output_base_dir/$bootstrap_name"
    
    log_info "Starting bootstrap assembly..."
    log_info "Build mode: $build_mode"
    log_info "Architecture: $arch"
    log_info "Version: $version"
    log_info "Source binaries: $source_bin_dir"
    log_info "Source libraries: $source_lib_dir"
    log_info "Bootstrap directory: $bootstrap_dir"
    echo ""
    
    # Create output directory
    mkdir -p "$output_base_dir"
    
    # Remove existing bootstrap directory if it exists
    if [ -d "$bootstrap_dir" ]; then
        log_warning "Removing existing bootstrap directory: $bootstrap_dir"
        rm -rf "$bootstrap_dir"
    fi
    
    # Create directory structure
    create_directory_structure "$bootstrap_dir"
    echo ""
    
    # Install binaries
    if ! install_binaries "$source_bin_dir" "$bootstrap_dir/usr/bin"; then
        log_error "Failed to install binaries"
        exit 1
    fi
    echo ""
    
    # Install libraries (for linux-native mode)
    if [ "$build_mode" = "linux-native" ]; then
        install_libraries "$source_lib_dir" "$bootstrap_dir/usr/lib"
        echo ""
    fi
    
    # Create symlinks
    if ! create_symlinks "$bootstrap_dir"; then
        log_error "Failed to create symlinks"
        exit 1
    fi
    echo ""
    
    # Setup environment
    if ! setup_environment "$bootstrap_dir"; then
        log_error "Failed to setup environment"
        exit 1
    fi
    echo ""
    
    # Generate SYMLINKS.txt
    generate_symlinks_doc "$bootstrap_dir"
    echo ""
    
    # Validate bootstrap
    if ! validate_bootstrap "$bootstrap_dir"; then
        log_error "Bootstrap validation failed"
        exit 1
    fi
    echo ""
    
    # Generate assembly report
    generate_assembly_report "$bootstrap_dir"
    echo ""
    
    # Final success message
    echo "=========================================="
    log_success "Bootstrap assembly completed successfully!"
    log_info "Bootstrap location: $bootstrap_dir"
    log_info "Ready for packaging and testing"
}

# Run main function
main "$@"
