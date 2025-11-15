#!/usr/bin/env bash
# build-cache.sh - Build artifact caching and incremental build support
# This script manages build caching to avoid recompiling unchanged components

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
CACHE_DIR="${CACHE_DIR:-$PROJECT_ROOT/.cache/build}"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[CACHE]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[CACHE]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[CACHE]${NC} $1"
}

log_error() {
    echo -e "${RED}[CACHE]${NC} $1"
}

# Initialize cache directory structure
init_cache() {
    mkdir -p "$CACHE_DIR"/{artifacts,metadata,checksums}
    log_info "Cache directory initialized: $CACHE_DIR"
}

# Calculate checksum of source files and build configuration
calculate_build_hash() {
    local package=$1
    local mode=$2
    local arch=$3
    local config_file=$4
    
    local hash_input=""
    
    # Include package version from config
    if [ -f "$config_file" ]; then
        local version=$(jq -r ".packages.${package}.version // \"unknown\"" "$config_file" 2>/dev/null || echo "unknown")
        hash_input="${hash_input}${version}"
    fi
    
    # Include build mode and architecture
    hash_input="${hash_input}${mode}${arch}"
    
    # Include relevant build script content if it exists
    local build_script="$PROJECT_ROOT/scripts/build-${package}-${mode}.sh"
    if [ -f "$build_script" ]; then
        # Use file modification time instead of content for faster hashing
        local script_mtime=$(stat -f%m "$build_script" 2>/dev/null || stat -c%Y "$build_script" 2>/dev/null || echo "0")
        hash_input="${hash_input}${script_mtime}"
    fi
    
    # Calculate SHA256 hash
    echo -n "$hash_input" | sha256sum 2>/dev/null | awk '{print $1}' || echo -n "$hash_input" | shasum -a 256 | awk '{print $1}'
}

# Check if cached artifact exists and is valid
check_cache() {
    local package=$1
    local mode=$2
    local arch=$3
    local config_file=$4
    
    local cache_key="${package}-${mode}-${arch}"
    local hash=$(calculate_build_hash "$package" "$mode" "$arch" "$config_file")
    local metadata_file="$CACHE_DIR/metadata/${cache_key}.json"
    
    if [ ! -f "$metadata_file" ]; then
        log_info "No cache entry found for $cache_key"
        return 1
    fi
    
    # Check if hash matches
    local cached_hash=$(jq -r '.hash' "$metadata_file" 2>/dev/null || echo "")
    
    if [ "$cached_hash" = "$hash" ]; then
        # Check if artifact files exist
        local artifact_dir="$CACHE_DIR/artifacts/${cache_key}"
        if [ -d "$artifact_dir" ] && [ "$(ls -A "$artifact_dir" 2>/dev/null)" ]; then
            local cached_time=$(jq -r '.timestamp' "$metadata_file" 2>/dev/null || echo "unknown")
            log_success "Cache hit for $cache_key (cached: $cached_time)"
            return 0
        else
            log_warning "Cache metadata exists but artifacts missing for $cache_key"
            return 1
        fi
    else
        log_info "Cache outdated for $cache_key (hash mismatch)"
        return 1
    fi
}

# Store build artifacts in cache
store_cache() {
    local package=$1
    local mode=$2
    local arch=$3
    local config_file=$4
    local output_dir=$5
    
    local cache_key="${package}-${mode}-${arch}"
    local hash=$(calculate_build_hash "$package" "$mode" "$arch" "$config_file")
    local artifact_dir="$CACHE_DIR/artifacts/${cache_key}"
    local metadata_file="$CACHE_DIR/metadata/${cache_key}.json"
    
    log_info "Storing artifacts in cache for $cache_key..."
    
    # Create artifact directory
    rm -rf "$artifact_dir"
    mkdir -p "$artifact_dir"
    
    # Copy built artifacts
    if [ -d "$output_dir/bin" ]; then
        cp -r "$output_dir/bin" "$artifact_dir/" 2>/dev/null || true
    fi
    
    if [ -d "$output_dir/lib" ]; then
        cp -r "$output_dir/lib" "$artifact_dir/" 2>/dev/null || true
    fi
    
    # Copy any text files (applet lists, etc.)
    find "$output_dir" -maxdepth 1 -type f -name "*.txt" -exec cp {} "$artifact_dir/" \; 2>/dev/null || true
    
    # Calculate artifact size
    local size=$(du -sh "$artifact_dir" 2>/dev/null | awk '{print $1}')
    
    # Store metadata
    cat > "$metadata_file" << EOF
{
  "package": "$package",
  "mode": "$mode",
  "arch": "$arch",
  "hash": "$hash",
  "timestamp": "$(date -u +"%Y-%m-%d %H:%M:%S UTC")",
  "size": "$size"
}
EOF
    
    log_success "Cached $package artifacts ($size)"
}

# Restore artifacts from cache
restore_cache() {
    local package=$1
    local mode=$2
    local arch=$3
    local output_dir=$4
    
    local cache_key="${package}-${mode}-${arch}"
    local artifact_dir="$CACHE_DIR/artifacts/${cache_key}"
    
    if [ ! -d "$artifact_dir" ]; then
        log_error "Cache artifact directory not found: $artifact_dir"
        return 1
    fi
    
    log_info "Restoring artifacts from cache for $cache_key..."
    
    # Create output directory
    mkdir -p "$output_dir"
    
    # Restore artifacts
    if [ -d "$artifact_dir/bin" ]; then
        cp -r "$artifact_dir/bin" "$output_dir/" 2>/dev/null || true
    fi
    
    if [ -d "$artifact_dir/lib" ]; then
        cp -r "$artifact_dir/lib" "$output_dir/" 2>/dev/null || true
    fi
    
    # Restore text files
    find "$artifact_dir" -maxdepth 1 -type f -name "*.txt" -exec cp {} "$output_dir/" \; 2>/dev/null || true
    
    log_success "Restored $package artifacts from cache"
}

# Clean cache for specific package or all
clean_cache() {
    local package=${1:-"all"}
    local mode=${2:-"all"}
    local arch=${3:-"all"}
    
    if [ "$package" = "all" ]; then
        log_info "Cleaning entire build cache..."
        rm -rf "$CACHE_DIR/artifacts"/*
        rm -rf "$CACHE_DIR/metadata"/*
        log_success "Build cache cleared"
    else
        local cache_key="${package}-${mode}-${arch}"
        log_info "Cleaning cache for $cache_key..."
        rm -rf "$CACHE_DIR/artifacts/${cache_key}"
        rm -f "$CACHE_DIR/metadata/${cache_key}.json"
        log_success "Cache cleared for $cache_key"
    fi
}

# Show cache statistics
show_cache_stats() {
    log_info "Build Cache Statistics"
    echo "======================"
    
    if [ ! -d "$CACHE_DIR/artifacts" ]; then
        echo "Cache is empty"
        return
    fi
    
    local total_size=$(du -sh "$CACHE_DIR/artifacts" 2>/dev/null | awk '{print $1}')
    local entry_count=$(find "$CACHE_DIR/metadata" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
    
    echo "Total cached entries: $entry_count"
    echo "Total cache size: $total_size"
    echo ""
    echo "Cached packages:"
    echo "----------------"
    
    find "$CACHE_DIR/metadata" -name "*.json" 2>/dev/null | while read -r metadata_file; do
        local package=$(jq -r '.package' "$metadata_file" 2>/dev/null || echo "unknown")
        local mode=$(jq -r '.mode' "$metadata_file" 2>/dev/null || echo "unknown")
        local arch=$(jq -r '.arch' "$metadata_file" 2>/dev/null || echo "unknown")
        local timestamp=$(jq -r '.timestamp' "$metadata_file" 2>/dev/null || echo "unknown")
        local size=$(jq -r '.size' "$metadata_file" 2>/dev/null || echo "unknown")
        
        echo "  $package ($mode, $arch) - $size - cached: $timestamp"
    done
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 COMMAND [OPTIONS]

Build artifact caching and incremental build support.

Commands:
  init                          Initialize cache directory
  check PACKAGE MODE ARCH       Check if cached artifact exists
  store PACKAGE MODE ARCH DIR   Store build artifacts in cache
  restore PACKAGE MODE ARCH DIR Restore artifacts from cache
  clean [PACKAGE] [MODE] [ARCH] Clean cache (all if no args)
  stats                         Show cache statistics

Environment Variables:
  CACHE_DIR                     Cache directory (default: .cache/build)
  BUILD_DIR                     Build directory (default: build/)

Examples:
  $0 init
  $0 check busybox static arm64-v8a
  $0 store busybox static arm64-v8a build/static-arm64-v8a
  $0 restore busybox static arm64-v8a build/static-arm64-v8a
  $0 clean busybox static arm64-v8a
  $0 clean
  $0 stats

EOF
}

# Main function
main() {
    local command=${1:-""}
    
    case "$command" in
        init)
            init_cache
            ;;
        check)
            if [ $# -lt 4 ]; then
                log_error "Usage: $0 check PACKAGE MODE ARCH [CONFIG_FILE]"
                exit 1
            fi
            local config_file=${5:-"$PROJECT_ROOT/build-config.json"}
            check_cache "$2" "$3" "$4" "$config_file"
            ;;
        store)
            if [ $# -lt 5 ]; then
                log_error "Usage: $0 store PACKAGE MODE ARCH OUTPUT_DIR [CONFIG_FILE]"
                exit 1
            fi
            local config_file=${6:-"$PROJECT_ROOT/build-config.json"}
            store_cache "$2" "$3" "$4" "$config_file" "$5"
            ;;
        restore)
            if [ $# -lt 5 ]; then
                log_error "Usage: $0 restore PACKAGE MODE ARCH OUTPUT_DIR"
                exit 1
            fi
            restore_cache "$2" "$3" "$4" "$5"
            ;;
        clean)
            clean_cache "${2:-all}" "${3:-all}" "${4:-all}"
            ;;
        stats)
            show_cache_stats
            ;;
        --help|-h|help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
