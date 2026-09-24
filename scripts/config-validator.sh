#!/usr/bin/env bash

# config-validator.sh - Validates build configuration files
# Part of the bootstrap builder PRoot compatibility system

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Validation functions
validate_file_exists() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    return 0
}

validate_json_syntax() {
    local config_file="$1"
    
    if ! jq empty "$config_file" 2>/dev/null; then
        log_error "Invalid JSON syntax in configuration file"
        return 1
    fi
    
    return 0
}

validate_build_mode() {
    local config_file="$1"
    local build_mode
    
    build_mode=$(jq -r '.buildMode // empty' "$config_file")
    
    if [[ -z "$build_mode" ]]; then
        log_error "Missing required field: buildMode"
        return 1
    fi
    
    case "$build_mode" in
        static|linux-native|android-native)
            log_info "Build mode: $build_mode"
            
            # Check if mode is deprecated
            local is_deprecated
            local deprecation_msg
            is_deprecated=$(jq -r ".buildModeInfo.\"$build_mode\".deprecated // false" "$config_file")
            deprecation_msg=$(jq -r ".buildModeInfo.\"$build_mode\".deprecationMessage // empty" "$config_file")
            
            if [[ "$is_deprecated" == "true" ]]; then
                log_warn "Build mode '$build_mode' is DEPRECATED"
                if [[ -n "$deprecation_msg" ]]; then
                    log_warn "$deprecation_msg"
                fi
            fi
            
            # Check PRoot compatibility
            local proot_compatible
            if jq -e ".buildModeInfo.\"$build_mode\" | has(\"prootCompatible\")" "$config_file" > /dev/null 2>&1; then
                proot_compatible=$(jq -r ".buildModeInfo.\"$build_mode\".prootCompatible" "$config_file")
                
                if [[ "$proot_compatible" == "false" ]]; then
                    log_warn "Build mode '$build_mode' is NOT PRoot compatible"
                    log_warn "Binaries will not work in PRoot environments"
                fi
            fi
            
            return 0
            ;;
        *)
            log_error "Invalid build mode: $build_mode"
            log_error "Valid options: static, linux-native, android-native"
            return 1
            ;;
    esac
}

validate_architectures() {
    local config_file="$1"
    local architectures
    local valid_archs=("arm64-v8a" "armeabi-v7a" "x86_64" "x86")
    
    architectures=$(jq -r '.architectures[]? // empty' "$config_file")
    
    if [[ -z "$architectures" ]]; then
        log_error "Missing or empty field: architectures"
        return 1
    fi
    
    local invalid_arch=0
    while IFS= read -r arch; do
        local valid=0
        for valid_arch in "${valid_archs[@]}"; do
            if [[ "$arch" == "$valid_arch" ]]; then
                valid=1
                break
            fi
        done
        
        if [[ $valid -eq 0 ]]; then
            log_error "Invalid architecture: $arch"
            log_error "Valid options: ${valid_archs[*]}"
            invalid_arch=1
        fi
    done <<< "$architectures"
    
    if [[ $invalid_arch -eq 1 ]]; then
        return 1
    fi
    
    log_info "Architectures: $(echo "$architectures" | tr '\n' ' ')"
    return 0
}

validate_compression() {
    local config_file="$1"
    local compression
    
    compression=$(jq -r '.compression // "xz"' "$config_file")
    
    case "$compression" in
        xz|zstd|gzip)
            log_info "Compression: $compression"
            return 0
            ;;
        *)
            log_error "Invalid compression format: $compression"
            log_error "Valid options: xz, zstd, gzip"
            return 1
            ;;
    esac
}

validate_static_options() {
    local config_file="$1"
    local build_mode
    
    build_mode=$(jq -r '.buildMode // empty' "$config_file")
    
    if [[ "$build_mode" != "static" ]]; then
        return 0
    fi
    
    local libc
    libc=$(jq -r '.staticOptions.libc // "musl"' "$config_file")
    
    case "$libc" in
        musl|glibc)
            log_info "Static libc: $libc"
            ;;
        *)
            log_error "Invalid libc option: $libc"
            log_error "Valid options: musl, glibc"
            return 1
            ;;
    esac
    
    local opt_level
    opt_level=$(jq -r '.staticOptions.optimizationLevel // "Os"' "$config_file")
    
    case "$opt_level" in
        Os|O2|O3)
            log_info "Optimization level: $opt_level"
            ;;
        *)
            log_error "Invalid optimization level: $opt_level"
            log_error "Valid options: Os, O2, O3"
            return 1
            ;;
    esac
    
    return 0
}

validate_linux_native_options() {
    local config_file="$1"
    local build_mode
    
    build_mode=$(jq -r '.buildMode // empty' "$config_file")
    
    if [[ "$build_mode" != "linux-native" ]]; then
        return 0
    fi
    
    local linker_path
    linker_path=$(jq -r '.linuxNativeOptions.linkerPath // empty' "$config_file")
    
    if [[ -z "$linker_path" ]]; then
        log_error "Missing linkerPath for linux-native mode"
        return 1
    fi
    
    log_info "Linux linker path: $linker_path"
    
    local lib_paths
    lib_paths=$(jq -r '.linuxNativeOptions.libPaths[]? // empty' "$config_file")
    
    if [[ -z "$lib_paths" ]]; then
        log_warn "No library paths specified for linux-native mode"
    else
        log_info "Library paths: $(echo "$lib_paths" | tr '\n' ' ')"
    fi
    
    return 0
}

validate_packages() {
    local config_file="$1"
    local build_mode
    local packages
    
    build_mode=$(jq -r '.buildMode // empty' "$config_file")
    
    # Check if packages field exists
    if ! jq -e '.packages' "$config_file" > /dev/null 2>&1; then
        # Android-native mode doesn't require packages (uses pre-built binaries)
        if [[ "$build_mode" == "android-native" ]]; then
            log_info "No packages specified (android-native uses pre-built binaries)"
            return 0
        else
            log_error "Missing required field: packages"
            return 1
        fi
    fi
    
    packages=$(jq -r '.packages | keys[]? // empty' "$config_file")
    
    # Android-native mode doesn't require packages (uses pre-built binaries)
    if [[ "$build_mode" == "android-native" ]]; then
        if [[ -z "$packages" ]]; then
            log_info "No packages specified (android-native uses pre-built binaries)"
            return 0
        fi
    fi
    
    if [[ -z "$packages" ]]; then
        log_error "Missing or empty field: packages"
        return 1
    fi
    
    local invalid_package=0
    while IFS= read -r package; do
        local version
        local source
        
        version=$(jq -r ".packages.\"$package\".version // empty" "$config_file")
        source=$(jq -r ".packages.\"$package\".source // empty" "$config_file")
        
        if [[ -z "$version" ]]; then
            log_error "Package '$package' missing version"
            invalid_package=1
        fi
        
        if [[ -z "$source" ]]; then
            log_error "Package '$package' missing source URL"
            invalid_package=1
        fi
        
        if [[ $invalid_package -eq 0 ]]; then
            log_info "Package: $package v$version"
        fi
    done <<< "$packages"
    
    if [[ $invalid_package -eq 1 ]]; then
        return 1
    fi
    
    return 0
}

validate_version() {
    local config_file="$1"
    local version
    
    version=$(jq -r '.version // empty' "$config_file")
    
    if [[ -z "$version" ]]; then
        log_error "Missing required field: version"
        return 1
    fi
    
    # Validate semantic versioning format
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Invalid version format: $version"
        log_error "Expected format: X.Y.Z (e.g., 1.0.0)"
        return 1
    fi
    
    log_info "Version: $version"
    return 0
}

# Main validation function
validate_config() {
    local config_file="$1"
    
    log_info "Validating configuration file: $config_file"
    echo ""
    
    local validation_failed=0
    
    # Run all validations
    validate_file_exists "$config_file" || validation_failed=1
    
    if [[ $validation_failed -eq 0 ]]; then
        validate_json_syntax "$config_file" || validation_failed=1
    fi
    
    if [[ $validation_failed -eq 0 ]]; then
        validate_version "$config_file" || validation_failed=1
        validate_build_mode "$config_file" || validation_failed=1
        validate_architectures "$config_file" || validation_failed=1
        validate_compression "$config_file" || validation_failed=1
        validate_static_options "$config_file" || validation_failed=1
        validate_linux_native_options "$config_file" || validation_failed=1
        validate_packages "$config_file" || validation_failed=1
    fi
    
    echo ""
    if [[ $validation_failed -eq 1 ]]; then
        log_error "Configuration validation FAILED"
        return 1
    fi
    
    log_info "Configuration validation PASSED"
    return 0
}

# Script entry point
main() {
    if [[ $# -lt 1 ]]; then
        log_error "Usage: $0 <config-file>"
        log_error "Example: $0 build-config.json"
        exit 1
    fi
    
    local config_file="$1"
    
    # Check for required tools
    if ! command -v jq &> /dev/null; then
        log_error "Required tool 'jq' is not installed"
        log_error "Install with: apt-get install jq (Debian/Ubuntu) or brew install jq (macOS)"
        exit 1
    fi
    
    validate_config "$config_file"
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
