#!/usr/bin/env bash
# build-metrics.sh - Build time metrics collection and reporting
# This script tracks and reports build performance metrics

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
METRICS_DIR="${METRICS_DIR:-$PROJECT_ROOT/.cache/metrics}"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[METRICS]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[METRICS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[METRICS]${NC} $1"
}

log_error() {
    echo -e "${RED}[METRICS]${NC} $1"
}

# Initialize metrics directory
init_metrics() {
    mkdir -p "$METRICS_DIR"
    log_info "Metrics directory initialized: $METRICS_DIR"
}

# Start timing a build
start_build_timer() {
    local build_id=$1
    local package=$2
    local mode=$3
    local arch=$4
    
    local start_time=$(date +%s)
    local start_timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
    
    # Store start time
    cat > "$METRICS_DIR/${build_id}.start" << EOF
{
  "build_id": "$build_id",
  "package": "$package",
  "mode": "$mode",
  "arch": "$arch",
  "start_time": $start_time,
  "start_timestamp": "$start_timestamp"
}
EOF
    
    log_info "Started timer for $package ($mode, $arch)"
    echo "$start_time"
}

# Stop timing a build and record metrics
stop_build_timer() {
    local build_id=$1
    local status=${2:-"success"}
    local cache_hit=${3:-"false"}
    
    local start_file="$METRICS_DIR/${build_id}.start"
    
    if [ ! -f "$start_file" ]; then
        log_error "No start time found for build ID: $build_id"
        return 1
    fi
    
    local end_time=$(date +%s)
    local end_timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
    
    # Read start time
    local start_time=$(jq -r '.start_time' "$start_file")
    local package=$(jq -r '.package' "$start_file")
    local mode=$(jq -r '.mode' "$start_file")
    local arch=$(jq -r '.arch' "$start_file")
    local start_timestamp=$(jq -r '.start_timestamp' "$start_file")
    
    # Calculate duration
    local duration=$((end_time - start_time))
    local duration_formatted=$(format_duration $duration)
    
    # Get output directory size if available
    local output_size="unknown"
    local output_dir="$BUILD_DIR/${mode}-${arch}"
    if [ -d "$output_dir" ]; then
        output_size=$(du -sh "$output_dir" 2>/dev/null | awk '{print $1}')
    fi
    
    # Store metrics
    local metrics_file="$METRICS_DIR/${build_id}.json"
    cat > "$metrics_file" << EOF
{
  "build_id": "$build_id",
  "package": "$package",
  "mode": "$mode",
  "arch": "$arch",
  "status": "$status",
  "cache_hit": $cache_hit,
  "start_time": $start_time,
  "end_time": $end_time,
  "duration_seconds": $duration,
  "duration_formatted": "$duration_formatted",
  "start_timestamp": "$start_timestamp",
  "end_timestamp": "$end_timestamp",
  "output_size": "$output_size",
  "hostname": "$(hostname)",
  "cpu_cores": $(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)
}
EOF
    
    # Remove start file
    rm -f "$start_file"
    
    if [ "$status" = "success" ]; then
        log_success "Build completed in $duration_formatted"
    else
        log_error "Build failed after $duration_formatted"
    fi
    
    echo "$duration"
}

# Format duration in human-readable format
format_duration() {
    local seconds=$1
    
    if [ $seconds -lt 60 ]; then
        echo "${seconds}s"
    elif [ $seconds -lt 3600 ]; then
        local minutes=$((seconds / 60))
        local secs=$((seconds % 60))
        echo "${minutes}m ${secs}s"
    else
        local hours=$((seconds / 3600))
        local minutes=$(((seconds % 3600) / 60))
        local secs=$((seconds % 60))
        echo "${hours}h ${minutes}m ${secs}s"
    fi
}

# Generate build report
generate_build_report() {
    local output_file=${1:-"$BUILD_DIR/build-metrics-report.txt"}
    
    log_info "Generating build metrics report..."
    
    if [ ! -d "$METRICS_DIR" ] || [ -z "$(ls -A "$METRICS_DIR"/*.json 2>/dev/null)" ]; then
        log_warning "No metrics data available"
        return 1
    fi
    
    {
        echo "Build Performance Metrics Report"
        echo "================================="
        echo ""
        echo "Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
        echo ""
        
        # Count total builds
        local total_builds=$(find "$METRICS_DIR" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
        local successful_builds=$(grep -l '"status": "success"' "$METRICS_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
        local failed_builds=$((total_builds - successful_builds))
        local cache_hits=$(grep -l '"cache_hit": true' "$METRICS_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
        
        echo "Summary:"
        echo "--------"
        echo "Total builds: $total_builds"
        echo "Successful: $successful_builds"
        echo "Failed: $failed_builds"
        echo "Cache hits: $cache_hits"
        echo ""
        
        # Calculate average build time
        local total_duration=0
        local build_count=0
        
        find "$METRICS_DIR" -name "*.json" 2>/dev/null | while read -r metrics_file; do
            local duration=$(jq -r '.duration_seconds' "$metrics_file" 2>/dev/null || echo 0)
            total_duration=$((total_duration + duration))
            build_count=$((build_count + 1))
        done
        
        echo "Build Times:"
        echo "------------"
        
        # Show individual build times
        find "$METRICS_DIR" -name "*.json" 2>/dev/null | sort -r | head -20 | while read -r metrics_file; do
            local package=$(jq -r '.package' "$metrics_file" 2>/dev/null || echo "unknown")
            local mode=$(jq -r '.mode' "$metrics_file" 2>/dev/null || echo "unknown")
            local arch=$(jq -r '.arch' "$metrics_file" 2>/dev/null || echo "unknown")
            local duration=$(jq -r '.duration_formatted' "$metrics_file" 2>/dev/null || echo "unknown")
            local status=$(jq -r '.status' "$metrics_file" 2>/dev/null || echo "unknown")
            local cache_hit=$(jq -r '.cache_hit' "$metrics_file" 2>/dev/null || echo "false")
            local timestamp=$(jq -r '.end_timestamp' "$metrics_file" 2>/dev/null || echo "unknown")
            
            local cache_indicator=""
            if [ "$cache_hit" = "true" ]; then
                cache_indicator=" [CACHED]"
            fi
            
            local status_indicator="✓"
            if [ "$status" != "success" ]; then
                status_indicator="✗"
            fi
            
            echo "  $status_indicator $package ($mode, $arch): $duration$cache_indicator - $timestamp"
        done
        
        echo ""
        echo "Performance by Package:"
        echo "-----------------------"
        
        # Group by package and show statistics
        for package in $(find "$METRICS_DIR" -name "*.json" -exec jq -r '.package' {} \; 2>/dev/null | sort -u); do
            local pkg_builds=$(grep -l "\"package\": \"$package\"" "$METRICS_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
            
            if [ $pkg_builds -gt 0 ]; then
                # Calculate average duration for this package
                local total_pkg_duration=0
                local pkg_count=0
                
                grep -l "\"package\": \"$package\"" "$METRICS_DIR"/*.json 2>/dev/null | while read -r metrics_file; do
                    local duration=$(jq -r '.duration_seconds' "$metrics_file" 2>/dev/null || echo 0)
                    total_pkg_duration=$((total_pkg_duration + duration))
                    pkg_count=$((pkg_count + 1))
                done
                
                echo "  $package: $pkg_builds builds"
            fi
        done
        
        echo ""
        echo "Performance by Mode:"
        echo "--------------------"
        
        # Group by mode
        for mode in static linux-native android-native; do
            local mode_builds=$(grep -l "\"mode\": \"$mode\"" "$METRICS_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
            
            if [ $mode_builds -gt 0 ]; then
                echo "  $mode: $mode_builds builds"
            fi
        done
        
        echo ""
        echo "Cache Efficiency:"
        echo "-----------------"
        
        if [ $total_builds -gt 0 ]; then
            local cache_rate=$((cache_hits * 100 / total_builds))
            echo "  Cache hit rate: ${cache_rate}% ($cache_hits/$total_builds)"
            
            # Calculate time saved by cache
            local cached_builds=$(grep -l '"cache_hit": true' "$METRICS_DIR"/*.json 2>/dev/null)
            if [ -n "$cached_builds" ]; then
                local total_cached_time=0
                echo "$cached_builds" | while read -r metrics_file; do
                    local duration=$(jq -r '.duration_seconds' "$metrics_file" 2>/dev/null || echo 0)
                    total_cached_time=$((total_cached_time + duration))
                done
                
                # Estimate time saved (assume cache is 10x faster than full build)
                local estimated_saved=$((total_cached_time * 9))
                local saved_formatted=$(format_duration $estimated_saved)
                echo "  Estimated time saved: ~$saved_formatted"
            fi
        else
            echo "  No builds recorded yet"
        fi
        
    } > "$output_file"
    
    log_success "Build metrics report saved to $output_file"
    cat "$output_file"
}

# Show recent builds
show_recent_builds() {
    local count=${1:-10}
    
    log_info "Recent builds (last $count):"
    echo ""
    
    if [ ! -d "$METRICS_DIR" ] || [ -z "$(ls -A "$METRICS_DIR"/*.json 2>/dev/null)" ]; then
        echo "No builds recorded yet"
        return
    fi
    
    find "$METRICS_DIR" -name "*.json" 2>/dev/null | sort -r | head -n "$count" | while read -r metrics_file; do
        local package=$(jq -r '.package' "$metrics_file" 2>/dev/null || echo "unknown")
        local mode=$(jq -r '.mode' "$metrics_file" 2>/dev/null || echo "unknown")
        local arch=$(jq -r '.arch' "$metrics_file" 2>/dev/null || echo "unknown")
        local duration=$(jq -r '.duration_formatted' "$metrics_file" 2>/dev/null || echo "unknown")
        local status=$(jq -r '.status' "$metrics_file" 2>/dev/null || echo "unknown")
        local cache_hit=$(jq -r '.cache_hit' "$metrics_file" 2>/dev/null || echo "false")
        local timestamp=$(jq -r '.end_timestamp' "$metrics_file" 2>/dev/null || echo "unknown")
        
        local cache_indicator=""
        if [ "$cache_hit" = "true" ]; then
            cache_indicator=" [CACHED]"
        fi
        
        local status_indicator="✓"
        if [ "$status" != "success" ]; then
            status_indicator="✗"
        fi
        
        echo "$status_indicator $package ($mode, $arch): $duration$cache_indicator - $timestamp"
    done
}

# Clean old metrics
clean_metrics() {
    local days=${1:-30}
    
    log_info "Cleaning metrics older than $days days..."
    
    if [ ! -d "$METRICS_DIR" ]; then
        log_info "No metrics directory found"
        return
    fi
    
    local count=0
    find "$METRICS_DIR" -name "*.json" -mtime +$days 2>/dev/null | while read -r file; do
        rm -f "$file"
        count=$((count + 1))
    done
    
    log_success "Cleaned $count old metric files"
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 COMMAND [OPTIONS]

Build time metrics collection and reporting.

Commands:
  init                              Initialize metrics directory
  start BUILD_ID PACKAGE MODE ARCH  Start build timer
  stop BUILD_ID [STATUS] [CACHED]   Stop build timer (status: success/failed, cached: true/false)
  report [OUTPUT_FILE]              Generate build metrics report
  recent [COUNT]                    Show recent builds (default: 10)
  clean [DAYS]                      Clean metrics older than DAYS (default: 30)

Environment Variables:
  METRICS_DIR                       Metrics directory (default: .cache/metrics)
  BUILD_DIR                         Build directory (default: build/)

Examples:
  $0 init
  $0 start build-123 busybox static arm64-v8a
  $0 stop build-123 success false
  $0 stop build-123 success true
  $0 report
  $0 recent 20
  $0 clean 7

EOF
}

# Main function
main() {
    local command=${1:-""}
    
    case "$command" in
        init)
            init_metrics
            ;;
        start)
            if [ $# -lt 5 ]; then
                log_error "Usage: $0 start BUILD_ID PACKAGE MODE ARCH"
                exit 1
            fi
            start_build_timer "$2" "$3" "$4" "$5"
            ;;
        stop)
            if [ $# -lt 2 ]; then
                log_error "Usage: $0 stop BUILD_ID [STATUS] [CACHED]"
                exit 1
            fi
            local status=${3:-"success"}
            local cached=${4:-"false"}
            stop_build_timer "$2" "$status" "$cached"
            ;;
        report)
            generate_build_report "$2"
            ;;
        recent)
            show_recent_builds "${2:-10}"
            ;;
        clean)
            clean_metrics "${2:-30}"
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
