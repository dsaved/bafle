# Architecture Support

This document describes the multi-architecture support in the bootstrap builder system.

## Supported Architectures

The bootstrap builder supports the following Android architectures:

| Android Architecture | Linux Architecture | Target Triplet | Description |
|---------------------|-------------------|----------------|-------------|
| `arm64-v8a` | `aarch64` | `aarch64-linux-gnu` | 64-bit ARM (ARMv8-A) |
| `armeabi-v7a` | `arm` | `arm-linux-gnueabihf` | 32-bit ARM (ARMv7-A with NEON) |
| `x86_64` | `x86_64` | `x86_64-linux-gnu` | 64-bit x86 |
| `x86` | `i686` | `i686-linux-gnu` | 32-bit x86 |

## Architecture-Specific Compiler Flags

Each architecture uses specific compiler flags for optimization:

### arm64-v8a (ARMv8-A)
```bash
CFLAGS="-march=armv8-a"
```

### armeabi-v7a (ARMv7-A)
```bash
CFLAGS="-march=armv7-a -mfloat-abi=hard -mfpu=neon"
```

### x86_64
```bash
CFLAGS="-march=x86-64"
```

### x86 (i686)
```bash
CFLAGS="-march=i686 -m32"
```

## Cross-Compilation

### When is Cross-Compilation Needed?

Cross-compilation is required when the host architecture differs from the target architecture. For example:
- Building for `arm64-v8a` on an `x86_64` host
- Building for `x86` on an `x86_64` host

### Cross-Compilation Toolchains

The build system automatically detects when cross-compilation is needed and attempts to use the appropriate cross-compiler:

- **arm64-v8a**: `aarch64-linux-gnu-gcc`
- **armeabi-v7a**: `arm-linux-gnueabihf-gcc`
- **x86_64**: `x86_64-linux-gnu-gcc`
- **x86**: `i686-linux-gnu-gcc`

### Installing Cross-Compilation Toolchains

#### Debian/Ubuntu
```bash
# For ARM64
sudo apt-get install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu

# For ARM32
sudo apt-get install gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf

# For x86_64 (usually not needed on x86_64 hosts)
sudo apt-get install gcc-x86-64-linux-gnu g++-x86-64-linux-gnu

# For i686 (32-bit x86)
sudo apt-get install gcc-multilib g++-multilib
```

#### Fedora/RHEL
```bash
# For ARM64
sudo dnf install gcc-aarch64-linux-gnu gcc-c++-aarch64-linux-gnu

# For ARM32
sudo dnf install gcc-arm-linux-gnu gcc-c++-arm-linux-gnu
```

#### macOS
```bash
# Install via Homebrew
brew install arm-linux-gnueabihf-binutils
brew install aarch64-elf-gcc
```

## Build Mode Considerations

### Static Mode

In static mode, architecture-specific considerations include:
- Binary size varies by architecture (ARM typically smaller than x86)
- All dependencies are compiled into the binary
- No dynamic linker required
- Works in PRoot without additional libraries

### Linux-Native Mode

In linux-native mode, architecture-specific considerations include:
- Dynamic linker path varies by architecture:
  - `arm64-v8a`: `/lib/ld-linux-aarch64.so.1`
  - `armeabi-v7a`: `/lib/ld-linux-armhf.so.3`
  - `x86_64`: `/lib64/ld-linux-x86-64.so.2`
  - `x86`: `/lib/ld-linux.so.2`
- Shared libraries must match target architecture
- RPATH set to `/lib:/usr/lib` for library resolution

## PRoot Compatibility Testing

The PRoot compatibility test system automatically downloads architecture-appropriate PRoot binaries:

| Android Architecture | PRoot Architecture |
|---------------------|-------------------|
| `arm64-v8a` | `aarch64` |
| `armeabi-v7a` | `arm` |
| `x86_64` | `x86_64` |
| `x86` | `i686` |

PRoot binaries are downloaded from the Termux PRoot releases:
```
https://github.com/termux/proot/releases/download/v{VERSION}/proot-{ARCH}
```

## Building for Specific Architectures

### Build All Architectures

```bash
./scripts/build-wrapper.sh \
  --mode static \
  --version 1.0.0 \
  --config build-config.json
```

This will build for all architectures specified in `build-config.json`.

### Build Single Architecture

```bash
./scripts/build-wrapper.sh \
  --mode static \
  --arch arm64-v8a \
  --version 1.0.0
```

### Build Multiple Specific Architectures

```bash
./scripts/build-wrapper.sh \
  --mode static \
  --arch arm64-v8a \
  --arch x86_64 \
  --version 1.0.0
```

## Archive Naming Convention

Archives are named with the following pattern:
```
bootstrap-{MODE}-{ARCH}-{VERSION}.tar.{COMPRESSION}
```

Examples:
- `bootstrap-static-arm64-v8a-1.0.0.tar.xz`
- `bootstrap-linux-native-armeabi-v7a-1.0.0.tar.xz`
- `bootstrap-static-x86_64-1.0.0.tar.xz`

## Verification

After building, binaries are verified for correct architecture:

### Static Binaries
```bash
# Check that binary is statically linked
ldd bootstrap/usr/bin/bash
# Should output: "not a dynamic executable" or "statically linked"

# Check architecture
file bootstrap/usr/bin/bash
# Should show correct architecture (e.g., "ARM aarch64" for arm64-v8a)
```

### Linux-Native Binaries
```bash
# Check dynamic linker
readelf -l bootstrap/usr/bin/bash | grep interpreter
# Should show correct linker path for architecture

# Check architecture
file bootstrap/usr/bin/bash
# Should show correct architecture
```

## Troubleshooting

### Cross-Compiler Not Found

If you see warnings about missing cross-compilers:
```
[WARNING] Cross-compiler not found: aarch64-linux-gnu-gcc
[WARNING] Attempting native build (may fail for incompatible architectures)
```

**Solution**: Install the appropriate cross-compilation toolchain (see above).

### Binary Architecture Mismatch

If binaries are built for the wrong architecture:
```
[ERROR] Binary architecture mismatch
```

**Solution**: 
1. Verify `TARGET_ARCH` environment variable is set correctly
2. Check that architecture-specific CFLAGS are being applied
3. Ensure cross-compiler is being used (check build logs)

### PRoot Download Fails

If PRoot binary download fails:
```
[ERROR] Failed to download PRoot from https://github.com/termux/proot/...
```

**Solution**:
1. Check network connectivity
2. Verify PRoot version exists for the target architecture
3. Try a different PRoot version with `--version` flag
4. Build PRoot from source as a fallback

## Performance Considerations

### Build Times

Build times vary by architecture and host:
- **Native builds**: Fastest (no cross-compilation overhead)
- **Cross-compilation**: Slower due to toolchain overhead
- **ARM on x86**: Typically 20-30% slower than native
- **x86 on ARM**: May be significantly slower

### Binary Sizes

Typical binary sizes by architecture (static mode with musl):
- **arm64-v8a**: ~1.2 MB (bash), ~1.0 MB (busybox)
- **armeabi-v7a**: ~1.1 MB (bash), ~950 KB (busybox)
- **x86_64**: ~1.4 MB (bash), ~1.2 MB (busybox)
- **x86**: ~1.3 MB (bash), ~1.1 MB (busybox)

ARM architectures typically produce smaller binaries due to more efficient instruction encoding.

## Future Enhancements

Potential future architecture support:
- **riscv64**: RISC-V 64-bit (emerging architecture)
- **mips**: MIPS architecture (legacy Android devices)
- **mips64**: MIPS 64-bit

These would require:
1. Adding architecture mappings
2. Defining compiler flags
3. Testing PRoot compatibility
4. Updating documentation
