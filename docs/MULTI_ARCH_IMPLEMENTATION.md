# Multi-Architecture Support Implementation

## Overview

This document describes the implementation of multi-architecture support for the bootstrap builder system, enabling builds for arm64-v8a, armeabi-v7a, x86_64, and x86 architectures.

## Changes Made

### 1. Build Wrapper (scripts/build-wrapper.sh)

**Added:**
- Architecture parameter export to build scripts (`TARGET_ARCH`, `BUILD_VERSION`)
- Updated `delegate_build()` to pass architecture and version to build pipelines
- Architecture-specific command-line arguments for each build mode

**Key Changes:**
```bash
# Export architecture for build scripts
export TARGET_ARCH="$arch"
export BUILD_VERSION="$version"

# Pass architecture to build scripts
"$SCRIPT_DIR/build-static.sh" --arch "$arch" --version "$version" --config "$CONFIG_FILE"
"$SCRIPT_DIR/build-linux-native.sh" --android-arch "$arch" --version "$version" --config "$CONFIG_FILE"
```

### 2. Static Build Pipeline (scripts/build-static.sh)

**Added Functions:**
- `map_android_to_target()`: Maps Android arch to cross-compilation target triplet
- `get_arch_cflags()`: Returns architecture-specific compiler flags
- `detect_host_arch()`: Detects host system architecture
- `needs_cross_compilation()`: Determines if cross-compilation is needed

**Architecture Mappings:**
| Android Arch | Target Triplet | CFLAGS |
|-------------|----------------|--------|
| arm64-v8a | aarch64-linux-gnu | -march=armv8-a |
| armeabi-v7a | arm-linux-gnueabihf | -march=armv7-a -mfloat-abi=hard -mfpu=neon |
| x86_64 | x86_64-linux-gnu | -march=x86-64 |
| x86 | i686-linux-gnu | -march=i686 -m32 |

**Key Changes:**
- Added `--arch` and `--version` command-line options
- Architecture validation
- Output directory now includes architecture: `build/static-{ARCH}`
- Cross-compilation detection and toolchain selection
- Export of `CROSS_COMPILE` and `ARCH_CFLAGS` environment variables

### 3. BusyBox Static Build (scripts/build-busybox-static.sh)

**Key Changes:**
- Cross-compiler detection and usage
- Architecture-specific CFLAGS integration
- Support for `CROSS_COMPILE` environment variable

**Example:**
```bash
if [ -n "$CROSS_COMPILE" ]; then
    cc="${CROSS_COMPILE}gcc"
    log_info "Using cross-compiler: $cc"
fi

if [ -n "$ARCH_CFLAGS" ]; then
    cflags="$cflags $ARCH_CFLAGS"
fi
```

### 4. Bash Static Build (scripts/build-bash-static.sh)

**Key Changes:**
- Cross-compiler detection in both configure and build phases
- Host triplet configuration for cross-compilation
- Architecture-specific CFLAGS integration

**Configure Example:**
```bash
case "$TARGET_ARCH" in
    arm64-v8a)
        host_flag="--host=aarch64-linux-gnu"
        ;;
    armeabi-v7a)
        host_flag="--host=arm-linux-gnueabihf"
        ;;
    # ... etc
esac

./configure CC="$cc" CFLAGS="$cflags" LDFLAGS="$ldflags" $host_flag ...
```

### 5. Linux-Native Build Pipeline (scripts/build-linux-native.sh)

**Key Changes:**
- Added `--version` parameter support
- Architecture-specific output directory: `build/linux-native-{ARCH}`
- Export of `LINUX_ARCH` and `CROSS_COMPILE_TARGET` environment variables
- Cross-compilation toolchain detection and validation

**Key Exports:**
```bash
export LINUX_ARCH="$target_arch"
export CROSS_COMPILE_TARGET=$(get_toolchain_prefix "$target_arch")
export CROSS_COMPILE="${CROSS_COMPILE_TARGET}-"
```

### 6. Bootstrap Assembly (scripts/assemble-bootstrap.sh)

**Key Changes:**
- Architecture-aware source directory detection
- Fallback to non-architecture-specific directories for backward compatibility

**Directory Resolution:**
```bash
# Try architecture-specific directory first
local source_bin_dir="$BUILD_DIR/${build_mode}-${arch}/bin"

# Fallback to non-architecture-specific
if [ ! -d "$source_bin_dir" ]; then
    source_bin_dir="$BUILD_DIR/$build_mode/bin"
fi
```

### 7. PRoot Test Setup (scripts/setup-test-proot.sh)

**Key Changes:**
- Enhanced error handling for PRoot download failures
- Better logging for architecture-specific PRoot binaries
- Graceful fallback suggestions when binaries are unavailable

### 8. Documentation

**New Files:**
- `docs/ARCHITECTURE_SUPPORT.md`: Comprehensive architecture support documentation
- `docs/MULTI_ARCH_IMPLEMENTATION.md`: This implementation guide

## Usage Examples

### Build for Single Architecture

```bash
./scripts/build-wrapper.sh \
  --mode static \
  --arch arm64-v8a \
  --version 1.0.0
```

### Build for Multiple Architectures

```bash
./scripts/build-wrapper.sh \
  --mode static \
  --arch arm64-v8a \
  --arch x86_64 \
  --version 1.0.0
```

### Build All Architectures from Config

```bash
./scripts/build-wrapper.sh \
  --mode static \
  --version 1.0.0 \
  --config build-config.json
```

### Test PRoot Compatibility for Specific Architecture

```bash
./test/test-proot-compatibility.sh \
  --arch arm64-v8a \
  bootstrap-static-arm64-v8a-1.0.0
```

## Cross-Compilation Requirements

### Installing Toolchains

**Debian/Ubuntu:**
```bash
sudo apt-get install \
  gcc-aarch64-linux-gnu \
  gcc-arm-linux-gnueabihf \
  gcc-multilib
```

**Fedora/RHEL:**
```bash
sudo dnf install \
  gcc-aarch64-linux-gnu \
  gcc-arm-linux-gnu
```

### Verification

Check if cross-compilers are available:
```bash
which aarch64-linux-gnu-gcc
which arm-linux-gnueabihf-gcc
which i686-linux-gnu-gcc
```

## Output Structure

### Build Artifacts

```
build/
├── static-arm64-v8a/
│   ├── bin/
│   │   ├── bash
│   │   ├── busybox
│   │   └── ...
│   └── build-report.txt
├── static-armeabi-v7a/
│   └── ...
├── static-x86_64/
│   └── ...
└── static-x86/
    └── ...
```

### Archives

```
bootstrap-archives/
├── bootstrap-static-arm64-v8a-1.0.0.tar.xz
├── bootstrap-static-arm64-v8a-1.0.0.tar.xz.sha256
├── bootstrap-static-armeabi-v7a-1.0.0.tar.xz
├── bootstrap-static-x86_64-1.0.0.tar.xz
└── bootstrap-static-x86-1.0.0.tar.xz
```

## Testing

### Syntax Validation

All modified scripts pass bash syntax validation:
```bash
bash -n scripts/build-wrapper.sh          # ✓ OK
bash -n scripts/build-static.sh           # ✓ OK
bash -n scripts/build-linux-native.sh     # ✓ OK
bash -n scripts/build-busybox-static.sh   # ✓ OK
bash -n scripts/build-bash-static.sh      # ✓ OK
bash -n scripts/setup-test-proot.sh       # ✓ OK
bash -n scripts/assemble-bootstrap.sh     # ✓ OK
```

### Architecture Validation

The build wrapper correctly validates architectures:
```bash
# Valid architecture - accepted
./scripts/build-wrapper.sh --mode static --arch arm64-v8a --version 1.0.0

# Invalid architecture - rejected with error
./scripts/build-wrapper.sh --mode static --arch invalid-arch --version 1.0.0
# [ERROR] Invalid architecture: invalid-arch
# [ERROR] Valid options: arm64-v8a armeabi-v7a x86_64 x86
```

### Function Testing

Architecture mapping functions work correctly:
- `map_android_to_target("arm64-v8a")` → `"aarch64-linux-gnu"`
- `map_android_to_target("armeabi-v7a")` → `"arm-linux-gnueabihf"`
- `get_arch_cflags("arm64-v8a")` → `"-march=armv8-a"`
- `get_arch_cflags("armeabi-v7a")` → `"-march=armv7-a -mfloat-abi=hard -mfpu=neon"`

## Backward Compatibility

The implementation maintains backward compatibility:

1. **Non-architecture builds**: Scripts still work without architecture specification (uses defaults)
2. **Directory fallback**: Assembly script falls back to non-architecture-specific directories
3. **Environment variables**: Existing `BUILD_DIR`, `OUTPUT_DIR` variables still work
4. **Config file**: Existing config files work without modification

## Requirements Satisfied

This implementation satisfies all requirements from task 9:

✅ **7.1**: Support for arm64-v8a, armeabi-v7a, x86_64, and x86 architectures  
✅ **7.2**: Architecture detection and cross-compilation toolchain selection  
✅ **7.3**: Architecture-specific compiler flags and target triplets  
✅ **7.4**: Archive naming includes architecture tag  
✅ **7.5**: PRoot compatibility tests use architecture-appropriate binaries  

## Future Enhancements

Potential improvements:
1. **Automatic toolchain installation**: Script to install required cross-compilers
2. **Docker-based builds**: Containerized builds with all toolchains pre-installed
3. **Parallel architecture builds**: Build multiple architectures simultaneously
4. **Architecture-specific optimizations**: Fine-tune compiler flags per architecture
5. **Additional architectures**: Support for RISC-V, MIPS, etc.
