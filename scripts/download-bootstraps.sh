#!/usr/bin/env bash

# Bootstrap Download Script
# Downloads Termux bootstrap packages for all supported architectures
# Usage: ./download-bootstraps.sh [version]

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# Configuration
TERMUX_REPO="termux/termux-packages"
DOWNLOAD_DIR="bootstrap-downloads"
MAX_RETRIES=3
INITIAL_BACKOFF=2

# Architecture mapping: Termux arch -> Android arch
# Format: "termux_arch:android_arch"
ARCHITECTURES=(
    "aarch64:arm64-v8a"
    "arm:armeabi-v7a"
    "x86_64:x86_64"
    "i686:x86"
)

# Helper function to get Android arch from Termux arch
get_android_arch() {
    local termux_arch="$1"
    for mapping in "${ARCHITECTURES[@]}"; do
        local t_arch="${mapping%%:*}"
        local a_arch="${mapping##*:}"
        if [ "$t_arch" = "$termux_arch" ]; then
            echo "$a_arch"
            return 0
        fi
    done
    return 1
}

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

# Get the latest Termux bootstrap release tag
get_latest_bootstrap_tag() {
    log_info "Fetching latest Termux bootstrap release..." >&2
    
    local tag
    tag=$(curl -s "https://api.github.com/repos/${TERMUX_REPO}/releases" | \
        grep -o '"tag_name": "bootstrap-[^"]*"' | \
        head -1 | \
        cut -d'"' -f4)
    
    if [ -z "$tag" ]; then
        log_error "Failed to fetch latest bootstrap tag" >&2
        return 1
    fi
    
    log_info "Latest bootstrap tag: $tag" >&2
    echo "$tag"
}

# Download file with retry logic and exponential backoff
download_with_retry() {
    local url="$1"
    local output="$2"
    local retry_count=0
    local backoff=$INITIAL_BACKOFF
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        log_info "Downloading: $url (attempt $((retry_count + 1))/$MAX_RETRIES)"
        
        if curl -L -f -o "$output" "$url" 2>/dev/null; then
            log_info "Successfully downloaded: $(basename "$output")"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        
        if [ $retry_count -lt $MAX_RETRIES ]; then
            log_warn "Download failed, retrying in ${backoff}s..."
            sleep $backoff
            backoff=$((backoff * 2))  # Exponential backoff
        fi
    done
    
    log_error "Failed to download after $MAX_RETRIES attempts: $url"
    return 1
}

# Download and extract bootstrap for a specific architecture
download_bootstrap() {
    local termux_arch="$1"
    local bootstrap_tag="$2"
    local android_arch
    
    android_arch=$(get_android_arch "$termux_arch")
    if [ $? -ne 0 ]; then
        log_error "Unknown architecture: $termux_arch"
        return 1
    fi
    
    log_info "Processing architecture: $termux_arch -> $android_arch"
    
    # Construct download URL
    local filename="bootstrap-${termux_arch}.zip"
    local url="https://github.com/${TERMUX_REPO}/releases/download/${bootstrap_tag}/${filename}"
    local download_path="${DOWNLOAD_DIR}/${filename}"
    
    # Download the bootstrap zip
    if ! download_with_retry "$url" "$download_path"; then
        log_error "Failed to download bootstrap for $termux_arch"
        return 1
    fi
    
    # Extract the bootstrap
    log_info "Extracting bootstrap for $android_arch..."
    local extract_dir="${DOWNLOAD_DIR}/bootstrap-${termux_arch}"
    
    if ! unzip -q -o "$download_path" -d "$extract_dir"; then
        log_error "Failed to extract bootstrap for $termux_arch"
        return 1
    fi
    
    # Rename to Android architecture naming
    local android_dir="${DOWNLOAD_DIR}/${android_arch}"
    if [ -d "$android_dir" ]; then
        rm -rf "$android_dir"
    fi
    mv "$extract_dir" "$android_dir"
    
    log_info "Successfully processed $android_arch"
    
    # Clean up zip file
    rm -f "$download_path"
    
    return 0
}

# Main execution
main() {
    log_info "Starting Termux bootstrap download process..."
    
    # Create download directory
    mkdir -p "$DOWNLOAD_DIR"
    
    # Get the latest bootstrap release tag
    local bootstrap_tag
    if ! bootstrap_tag=$(get_latest_bootstrap_tag); then
        log_error "Failed to determine bootstrap version"
        exit 1
    fi
    
    # Download bootstraps for all architectures
    local failed_archs=()
    
    for mapping in "${ARCHITECTURES[@]}"; do
        local termux_arch="${mapping%%:*}"
        if ! download_bootstrap "$termux_arch" "$bootstrap_tag"; then
            failed_archs+=("$termux_arch")
        fi
    done
    
    # Report results
    echo ""
    log_info "Download process complete!"
    log_info "Bootstrap tag: $bootstrap_tag"
    log_info "Download directory: $DOWNLOAD_DIR"
    
    if [ ${#failed_archs[@]} -eq 0 ]; then
        log_info "All architectures downloaded successfully:"
        for mapping in "${ARCHITECTURES[@]}"; do
            local android_arch="${mapping##*:}"
            echo "  ✓ $android_arch"
        done
        exit 0
    else
        log_error "Failed to download the following architectures:"
        for arch in "${failed_archs[@]}"; do
            local android_arch
            android_arch=$(get_android_arch "$arch")
            echo "  ✗ $android_arch"
        done
        exit 1
    fi
}

# Run main function
main "$@"
