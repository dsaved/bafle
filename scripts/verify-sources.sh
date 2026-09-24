#!/usr/bin/env bash
# verify-sources.sh - Verify source package checksums using SHA256
# This script verifies the integrity of downloaded source packages

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Calculate SHA256 checksum of a file
calculate_checksum() {
    local file=$1
    
    if [ ! -f "$file" ]; then
        log_error "File not found: $file"
        return 1
    fi
    
    # Use sha256sum (Linux) or shasum (macOS)
    if command -v sha256sum &> /dev/null; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum &> /dev/null; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        log_error "Neither sha256sum nor shasum found"
        return 1
    fi
}

# Verify a file against expected checksum
verify_checksum() {
    local file=$1
    local expected_checksum=$2
    
    if [ -z "$expected_checksum" ]; then
        log_error "No checksum provided for verification"
        return 1
    fi
    
    log_info "Calculating checksum for $(basename "$file")..."
    local actual_checksum=$(calculate_checksum "$file")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to calculate checksum"
        return 1
    fi
    
    log_info "Expected: $expected_checksum"
    log_info "Actual:   $actual_checksum"
    
    if [ "$actual_checksum" = "$expected_checksum" ]; then
        log_success "Checksum verification passed"
        return 0
    else
        log_error "Checksum verification failed"
        log_error "File may be corrupted or tampered with"
        return 1
    fi
}

# Verify multiple files from a checksum file
verify_from_checksum_file() {
    local checksum_file=$1
    local base_dir=${2:-.}
    
    if [ ! -f "$checksum_file" ]; then
        log_error "Checksum file not found: $checksum_file"
        return 1
    fi
    
    log_info "Verifying files from checksum file: $checksum_file"
    
    local failed_files=()
    local verified_count=0
    
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        
        # Parse checksum and filename
        local checksum=$(echo "$line" | awk '{print $1}')
        local filename=$(echo "$line" | awk '{print $2}')
        
        if [ -z "$checksum" ] || [ -z "$filename" ]; then
            log_error "Invalid line in checksum file: $line"
            continue
        fi
        
        local filepath="$base_dir/$filename"
        
        if [ ! -f "$filepath" ]; then
            log_error "File not found: $filepath"
            failed_files+=("$filename")
            continue
        fi
        
        if verify_checksum "$filepath" "$checksum"; then
            ((verified_count++))
        else
            failed_files+=("$filename")
        fi
        
        echo "" >&2
    done < "$checksum_file"
    
    # Report results
    if [ ${#failed_files[@]} -eq 0 ]; then
        log_success "All $verified_count files verified successfully"
        return 0
    else
        log_error "Failed to verify ${#failed_files[@]} files: ${failed_files[*]}"
        return 1
    fi
}

# Generate checksum file for directory
generate_checksum_file() {
    local directory=$1
    local output_file=${2:-checksums.txt}
    
    if [ ! -d "$directory" ]; then
        log_error "Directory not found: $directory"
        return 1
    fi
    
    log_info "Generating checksums for files in $directory..."
    
    # Find all regular files and calculate checksums
    find "$directory" -type f | sort | while read -r file; do
        local checksum=$(calculate_checksum "$file")
        local relative_path=$(realpath --relative-to="$directory" "$file" 2>/dev/null || \
                             python -c "import os.path; print(os.path.relpath('$file', '$directory'))" 2>/dev/null || \
                             echo "$file")
        echo "$checksum  $relative_path"
    done > "$output_file"
    
    log_success "Checksums written to $output_file"
    return 0
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] FILE [CHECKSUM]

Verify source package checksums using SHA256.

Options:
  -f, --checksum-file FILE    Verify multiple files from a checksum file
  -d, --base-dir DIR          Base directory for files in checksum file (default: .)
  -g, --generate DIR          Generate checksum file for directory
  -o, --output FILE           Output file for generated checksums (default: checksums.txt)
  -h, --help                  Show this help message

Examples:
  # Verify a single file
  $0 busybox-1.36.1.tar.bz2 b8cc24c9574d809e7279c3be349795c5d5ceb6fdf19ca709f80cde50e47de314

  # Verify files from checksum file
  $0 --checksum-file checksums.txt --base-dir .cache/sources

  # Generate checksum file
  $0 --generate .cache/sources --output checksums.txt

  # Calculate checksum only (no verification)
  $0 busybox-1.36.1.tar.bz2

EOF
}

# Main function
main() {
    local file=""
    local expected_checksum=""
    local checksum_file=""
    local base_dir="."
    local generate_dir=""
    local output_file="checksums.txt"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--checksum-file)
                checksum_file="$2"
                shift 2
                ;;
            -d|--base-dir)
                base_dir="$2"
                shift 2
                ;;
            -g|--generate)
                generate_dir="$2"
                shift 2
                ;;
            -o|--output)
                output_file="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                if [ -z "$file" ]; then
                    file="$1"
                elif [ -z "$expected_checksum" ]; then
                    expected_checksum="$1"
                else
                    log_error "Unknown argument: $1"
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Generate checksum file mode
    if [ -n "$generate_dir" ]; then
        generate_checksum_file "$generate_dir" "$output_file"
        exit $?
    fi
    
    # Verify from checksum file mode
    if [ -n "$checksum_file" ]; then
        verify_from_checksum_file "$checksum_file" "$base_dir"
        exit $?
    fi
    
    # Single file verification mode
    if [ -z "$file" ]; then
        log_error "No file specified"
        show_usage
        exit 1
    fi
    
    if [ ! -f "$file" ]; then
        log_error "File not found: $file"
        exit 1
    fi
    
    # If no checksum provided, just calculate and display
    if [ -z "$expected_checksum" ]; then
        local checksum=$(calculate_checksum "$file")
        echo "$checksum"
        exit 0
    fi
    
    # Verify checksum
    if verify_checksum "$file" "$expected_checksum"; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"
