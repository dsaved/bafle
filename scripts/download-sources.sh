#!/usr/bin/env bash
# download-sources.sh - Download source packages for bootstrap builder
# This script downloads source packages (BusyBox, Bash, Coreutils) from configured URLs
# and caches them in .cache/sources/ directory

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="$PROJECT_ROOT/.cache/sources"
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

# Check if required tools are available
check_dependencies() {
    local missing_deps=()
    
    for cmd in curl jq sha256sum tar; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Please install them before running this script"
        exit 1
    fi
}

# Create cache directory structure
setup_cache_directory() {
    log_info "Setting up cache directory: $CACHE_DIR"
    mkdir -p "$CACHE_DIR"
    
    # Create subdirectories for each package type
    mkdir -p "$CACHE_DIR/busybox"
    mkdir -p "$CACHE_DIR/bash"
    mkdir -p "$CACHE_DIR/coreutils"
    
    log_success "Cache directory structure created"
}

# Get package information from config
get_package_info() {
    local package_name=$1
    local field=$2
    
    jq -r ".packages.${package_name}.${field}" "$CONFIG_FILE"
}

# Check if cached source is valid
is_cached_source_valid() {
    local package_name=$1
    local version=$2
    local checksum=$3
    local cache_file="$CACHE_DIR/$package_name/$(basename "$(get_package_info "$package_name" "source")")"
    
    # Check if file exists
    if [ ! -f "$cache_file" ]; then
        return 1
    fi
    
    # Verify checksum
    log_info "Verifying cached $package_name..."
    if "$SCRIPT_DIR/verify-sources.sh" "$cache_file" "$checksum"; then
        log_success "Valid cached source found for $package_name v$version"
        return 0
    else
        log_warning "Cached source for $package_name has invalid checksum, will re-download"
        rm -f "$cache_file"
        return 1
    fi
}

# Download a package
download_package() {
    local package_name=$1
    local version=$2
    local source_url=$3
    local checksum=$4
    
    local filename=$(basename "$source_url")
    local cache_file="$CACHE_DIR/$package_name/$filename"
    
    log_info "Downloading $package_name v$version..."
    log_info "URL: $source_url"
    
    # Download with progress bar
    if curl -L -f -# -o "$cache_file.tmp" "$source_url"; then
        mv "$cache_file.tmp" "$cache_file"
        log_success "Downloaded $package_name successfully"
        
        # Verify checksum
        if "$SCRIPT_DIR/verify-sources.sh" "$cache_file" "$checksum"; then
            log_success "Checksum verification passed for $package_name"
            return 0
        else
            log_error "Checksum verification failed for $package_name"
            rm -f "$cache_file"
            return 1
        fi
    else
        log_error "Failed to download $package_name from $source_url"
        rm -f "$cache_file.tmp"
        return 1
    fi
}

# Process a single package
process_package() {
    local package_name=$1
    
    log_info "Processing package: $package_name"
    
    # Get package information from config
    local version=$(get_package_info "$package_name" "version")
    local source_url=$(get_package_info "$package_name" "source")
    local checksum=$(get_package_info "$package_name" "checksum")
    
    # Validate package info
    if [ "$version" = "null" ] || [ "$source_url" = "null" ]; then
        log_error "Package $package_name not found in configuration"
        return 1
    fi
    
    if [ "$checksum" = "null" ] || [ -z "$checksum" ]; then
        log_warning "No checksum specified for $package_name, skipping verification"
        checksum=""
    fi
    
    # Check if valid cached source exists
    if [ -n "$checksum" ] && is_cached_source_valid "$package_name" "$version" "$checksum"; then
        log_info "Using cached source for $package_name"
        return 0
    fi
    
    # Download the package
    if download_package "$package_name" "$version" "$source_url" "$checksum"; then
        return 0
    else
        return 1
    fi
}

# Extract source archive
extract_source() {
    local package_name=$1
    local extract_dir=${2:-$PROJECT_ROOT/build}
    
    local source_url=$(get_package_info "$package_name" "source")
    local filename=$(basename "$source_url")
    local cache_file="$CACHE_DIR/$package_name/$filename"
    
    if [ ! -f "$cache_file" ]; then
        log_error "Source file not found: $cache_file"
        return 1
    fi
    
    log_info "Extracting $package_name to $extract_dir..."
    mkdir -p "$extract_dir"
    
    # Detect archive type and extract
    case "$filename" in
        *.tar.bz2)
            tar -xjf "$cache_file" -C "$extract_dir"
            ;;
        *.tar.gz)
            tar -xzf "$cache_file" -C "$extract_dir"
            ;;
        *.tar.xz)
            tar -xJf "$cache_file" -C "$extract_dir"
            ;;
        *)
            log_error "Unsupported archive format: $filename"
            return 1
            ;;
    esac
    
    log_success "Extracted $package_name successfully"
    return 0
}

# Main function
main() {
    local packages_to_download=()
    local extract_dir=""
    local extract_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --package)
                packages_to_download+=("$2")
                shift 2
                ;;
            --extract-dir)
                extract_dir="$2"
                shift 2
                ;;
            --extract)
                extract_only=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --config FILE         Path to build configuration file (default: build-config.json)"
                echo "  --package NAME        Download specific package (can be specified multiple times)"
                echo "  --extract-dir DIR     Extract sources to specified directory"
                echo "  --extract             Extract sources after downloading"
                echo "  --help                Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0                                    # Download all packages"
                echo "  $0 --package busybox                  # Download only BusyBox"
                echo "  $0 --extract --extract-dir ./build    # Download and extract all packages"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Check if config file exists
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    
    log_info "Using configuration file: $CONFIG_FILE"
    
    # Check dependencies
    check_dependencies
    
    # Setup cache directory
    setup_cache_directory
    
    # If no specific packages specified, download all
    if [ ${#packages_to_download[@]} -eq 0 ]; then
        packages_to_download=($(jq -r '.packages | keys[]' "$CONFIG_FILE"))
    fi
    
    log_info "Packages to process: ${packages_to_download[*]}"
    
    # Download packages
    local failed_packages=()
    for package in "${packages_to_download[@]}"; do
        if ! process_package "$package"; then
            failed_packages+=("$package")
        fi
        echo ""
    done
    
    # Extract if requested
    if [ "$extract_only" = true ] || [ -n "$extract_dir" ]; then
        log_info "Extracting sources..."
        for package in "${packages_to_download[@]}"; do
            if [[ ! " ${failed_packages[@]} " =~ " ${package} " ]]; then
                extract_source "$package" "$extract_dir"
            fi
        done
    fi
    
    # Report results
    echo ""
    echo "=========================================="
    if [ ${#failed_packages[@]} -eq 0 ]; then
        log_success "All packages downloaded successfully!"
        log_info "Cache location: $CACHE_DIR"
        exit 0
    else
        log_error "Failed to download packages: ${failed_packages[*]}"
        exit 1
    fi
}

# Run main function
main "$@"
