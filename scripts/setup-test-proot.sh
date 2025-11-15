#!/usr/bin/env bash
# setup-test-proot.sh - Download and set up PRoot binary for testing
# This script downloads the appropriate PRoot binary for the target architecture

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
PROOT_VERSION="5.4.0"
CACHE_DIR="$PROJECT_ROOT/.cache/proot"
ARCH=""
OUTPUT_PATH=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Download and set up PRoot binary for testing.

OPTIONS:
    --arch ARCH          Target architecture (arm64-v8a, armeabi-v7a, x86_64, x86)
    --output PATH        Output path for PRoot binary
    --version VERSION    PRoot version to download (default: $PROOT_VERSION)
    --cache-dir DIR      Cache directory (default: $CACHE_DIR)
    --help               Show this help message

EXAMPLES:
    $0 --arch arm64-v8a --output .cache/proot/proot-arm64
    $0 --arch x86_64 --output /tmp/proot

EOF
}

# Map Android architecture to PRoot architecture
map_arch_to_proot() {
    local android_arch="$1"
    
    case "$android_arch" in
        arm64-v8a)
            echo "aarch64"
            ;;
        armeabi-v7a)
            echo "arm"
            ;;
        x86_64)
            echo "x86_64"
            ;;
        x86)
            echo "i686"
            ;;
        *)
            log_error "Unsupported architecture: $android_arch"
            return 1
            ;;
    esac
}

# Download PRoot binary
download_proot() {
    local proot_arch="$1"
    local output_path="$2"
    
    log_info "Downloading PRoot for architecture: $proot_arch"
    
    # Create cache directory
    mkdir -p "$(dirname "$output_path")"
    
    # PRoot download URL (using Termux PRoot builds)
    # Note: Termux PRoot releases use specific naming conventions
    local base_url="https://github.com/termux/proot/releases/download/v${PROOT_VERSION}"
    local filename="proot-${proot_arch}"
    local download_url="${base_url}/${filename}"
    
    log_info "Download URL: $download_url"
    
    # Try to download with curl or wget
    local download_success=false
    
    if command -v curl &> /dev/null; then
        if curl -L -f -o "$output_path" "$download_url" 2>&1; then
            download_success=true
        fi
    elif command -v wget &> /dev/null; then
        if wget -O "$output_path" "$download_url" 2>&1; then
            download_success=true
        fi
    else
        log_error "Neither curl nor wget is available"
        return 1
    fi
    
    if [ "$download_success" = false ]; then
        log_error "Failed to download PRoot from $download_url"
        log_warning "PRoot binary may not be available for this architecture/version"
        log_warning "You may need to build PRoot from source or use a different version"
        return 1
    fi
    
    # Make executable
    chmod +x "$output_path"
    
    log_success "Downloaded PRoot to: $output_path"
    return 0
}

# Verify PRoot binary
verify_proot() {
    local proot_path="$1"
    
    log_info "Verifying PRoot binary..."
    
    if [ ! -f "$proot_path" ]; then
        log_error "PRoot binary not found: $proot_path"
        return 1
    fi
    
    if [ ! -x "$proot_path" ]; then
        log_error "PRoot binary is not executable: $proot_path"
        return 1
    fi
    
    # Try to get version
    if "$proot_path" --version &> /dev/null; then
        local version=$("$proot_path" --version 2>&1 | head -n1)
        log_success "PRoot binary verified: $version"
    else
        log_warning "PRoot binary exists but version check failed (may still work)"
    fi
    
    return 0
}

# Main function
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --arch)
                ARCH="$2"
                shift 2
                ;;
            --output)
                OUTPUT_PATH="$2"
                shift 2
                ;;
            --version)
                PROOT_VERSION="$2"
                shift 2
                ;;
            --cache-dir)
                CACHE_DIR="$2"
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
    if [ -z "$ARCH" ]; then
        log_error "Architecture is required (--arch)"
        show_usage
        exit 1
    fi
    
    # Map architecture
    local proot_arch
    if ! proot_arch=$(map_arch_to_proot "$ARCH"); then
        exit 1
    fi
    
    # Set default output path if not specified
    if [ -z "$OUTPUT_PATH" ]; then
        OUTPUT_PATH="$CACHE_DIR/proot-${proot_arch}"
    fi
    
    log_info "Setting up PRoot for architecture: $ARCH ($proot_arch)"
    log_info "Output path: $OUTPUT_PATH"
    
    # Check if PRoot already exists and is valid
    if [ -f "$OUTPUT_PATH" ] && [ -x "$OUTPUT_PATH" ]; then
        log_info "PRoot binary already exists at: $OUTPUT_PATH"
        
        if verify_proot "$OUTPUT_PATH"; then
            log_success "Using existing PRoot binary"
            echo "$OUTPUT_PATH"
            exit 0
        else
            log_warning "Existing PRoot binary is invalid, re-downloading..."
            rm -f "$OUTPUT_PATH"
        fi
    fi
    
    # Download PRoot
    if ! download_proot "$proot_arch" "$OUTPUT_PATH"; then
        log_error "Failed to download PRoot"
        exit 1
    fi
    
    # Verify downloaded binary
    if ! verify_proot "$OUTPUT_PATH"; then
        log_error "Downloaded PRoot binary verification failed"
        exit 1
    fi
    
    # Output the path for use by other scripts
    echo "$OUTPUT_PATH"
    
    log_success "PRoot setup complete!"
    exit 0
}

# Run main function
main "$@"
