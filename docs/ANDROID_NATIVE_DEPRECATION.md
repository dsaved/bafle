# Android-Native Mode Deprecation Notice

## Overview

The `android-native` build mode is **DEPRECATED** as of version 1.0.0 and is maintained only for backward compatibility. This mode will be removed in a future major release.

## Why is it Deprecated?

Android-native binaries have the following limitations:

1. **Not PRoot Compatible**: Android-native binaries use Android's system linker (`/system/bin/linker64`) which relies on the apex-based dynamic linker system. PRoot cannot properly handle this linker resolution, causing binaries to fail with "No such file or directory" errors.

2. **Requires Root or Termux**: Android-native binaries only work in:
   - Rooted Android environments with full system access
   - Termux app environment (which provides the necessary Android runtime)

3. **Limited Portability**: Cannot be used in standard Linux containers, PRoot environments, or non-rooted Android apps.

## Recommended Alternatives

### Option 1: Static Mode (Recommended)

**Best for**: Maximum compatibility and portability

```bash
./scripts/build-wrapper.sh --mode static --arch arm64-v8a --version 1.0.0
```

**Advantages**:
- ✅ Works in PRoot without any issues
- ✅ No dynamic linker required
- ✅ Maximum portability
- ✅ Single binary contains all dependencies

**Disadvantages**:
- Larger binary sizes (5-8 MB compressed)
- Slightly slower startup time

### Option 2: Linux-Native Mode

**Best for**: Smaller size while maintaining PRoot compatibility

```bash
./scripts/build-wrapper.sh --mode linux-native --arch arm64-v8a --version 1.0.0
```

**Advantages**:
- ✅ Works in PRoot environments
- ✅ Smaller size than static (8-12 MB compressed)
- ✅ Uses standard Linux dynamic linker
- ✅ Faster startup than static

**Disadvantages**:
- Requires bundled libraries
- Slightly more complex bootstrap structure

## Migration Guide

### For Existing Projects

If you're currently using android-native mode, follow these steps to migrate:

1. **Update your build configuration**:

   ```json
   {
     "buildMode": "static",  // Changed from "android-native"
     "architectures": ["arm64-v8a", "armeabi-v7a", "x86_64", "x86"],
     "compression": "xz",
     "stripSymbols": true,
     "runTests": true
   }
   ```

2. **Rebuild your bootstraps**:

   ```bash
   ./scripts/build-wrapper.sh --config build-config.json --version 1.0.0
   ```

3. **Test in PRoot environment**:

   ```bash
   ./scripts/test-proot-compatibility.sh bootstrap-static-arm64-v8a-1.0.0
   ```

4. **Update your application code**:
   - No changes needed if you're using the bootstrap as a filesystem root
   - Update any hardcoded paths to Android system linker if present

### For New Projects

Simply use `static` or `linux-native` mode from the start:

```bash
# Create config file
cat > build-config.json << EOF
{
  "version": "1.0.0",
  "buildMode": "static",
  "architectures": ["arm64-v8a"],
  "compression": "xz",
  "stripSymbols": true,
  "runTests": true
}
EOF

# Build
./scripts/build-wrapper.sh --config build-config.json
```

## Using Android-Native Mode (Legacy)

If you absolutely must use android-native mode for backward compatibility:

### Configuration

Use the provided android-native configuration:

```bash
./scripts/build-wrapper.sh \
  --config build-config-android-native.json \
  --version 1.0.0
```

Or create a custom config:

```json
{
  "version": "1.0.0",
  "buildMode": "android-native",
  "architectures": ["arm64-v8a", "armeabi-v7a", "x86_64", "x86"],
  "compression": "xz",
  "stripSymbols": true,
  "runTests": false
}
```

### Deprecation Warnings

When using android-native mode, you will see deprecation warnings:

```
[WARN] =========================================
[WARN] DEPRECATION WARNING
[WARN] =========================================
[WARN] The 'android-native' build mode is DEPRECATED
[WARN]
[WARN] Android-native binaries are NOT compatible with PRoot
[WARN] and will not work in non-rooted Android environments.
[WARN]
[WARN] Please consider migrating to:
[WARN]   - 'static' mode (recommended for PRoot)
[WARN]   - 'linux-native' mode (smaller size, PRoot compatible)
[WARN]
[WARN] This mode is maintained for backward compatibility only
[WARN] and may be removed in a future release.
[WARN] =========================================
```

### Manifest Metadata

Android-native bootstraps in the manifest will be marked as:

```json
{
  "android-native": {
    "arm64-v8a": {
      "url": "https://github.com/dsaved/bafle/releases/download/v1.0.0/bootstrap-android-native-arm64-v8a-1.0.0.tar.xz",
      "sha256": "...",
      "size": 10485760,
      "buildMode": "android-native",
      "linker": "/system/bin/linker64",
      "prootCompatible": false,
      "note": "Requires Termux environment or root access"
    }
  }
}
```

Note the `"prootCompatible": false` flag.

## Timeline

- **v1.0.0** (Current): Android-native mode marked as deprecated, warnings added
- **v1.x.x**: Continued support with deprecation warnings
- **v2.0.0** (Future): Android-native mode may be removed entirely

## Support

If you have questions or need help migrating:

1. Check the [Migration Guide](MIGRATION_GUIDE.md)
2. Review [Build Modes Documentation](BUILD_MODES.md)
3. Open an issue on GitHub: https://github.com/dsaved/bafle/issues

## Technical Details

### Why PRoot Doesn't Work with Android-Native

PRoot works by intercepting system calls and translating paths. However:

1. Android's linker is located at `/system/bin/linker64` (or `/apex/com.android.runtime/bin/linker64`)
2. PRoot cannot properly map these apex paths
3. When a binary tries to load, the kernel looks for the interpreter path
4. The interpreter path doesn't exist in the PRoot environment
5. Result: "No such file or directory" error

### How Static/Linux-Native Solves This

**Static Mode**:
- No dynamic linker needed at all
- All libraries compiled into the binary
- Works anywhere the CPU architecture matches

**Linux-Native Mode**:
- Uses standard Linux linker: `/lib/ld-linux-aarch64.so.1`
- Linker is bundled in the bootstrap at the expected path
- PRoot can properly map this path
- Works in any PRoot environment

## References

- [PRoot Documentation](https://proot-me.github.io/)
- [Android Linker Documentation](https://source.android.com/docs/core/architecture/vndk/linker-namespace)
- [ELF Dynamic Linking](https://refspecs.linuxfoundation.org/elf/elf.pdf)
