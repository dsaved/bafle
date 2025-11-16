# GitHub Actions Limitations

## Build Mode Support

### ✅ Supported: android-native
The `android-native` build mode **works perfectly** in GitHub Actions:
- Downloads pre-built Termux bootstraps
- No compilation required
- Fast and reliable
- **This is the default and recommended mode**

### ❌ Not Supported: static and linux-native
The `static` and `linux-native` build modes **do not work** in GitHub Actions:

#### Why They Fail
1. **Cross-compilation required**
   - GitHub Actions runners are x86_64 (Intel/AMD)
   - ARM binaries require cross-compilation toolchains
   - Toolchains not available: `aarch64-linux-gnu-gcc`, `arm-linux-gnueabihf-gcc`

2. **Native compilation impossible**
   - Cannot compile ARM binaries on x86_64 without cross-compiler
   - Emulation (QEMU) too slow for full builds

3. **Missing dependencies**
   - musl-libc toolchain not installed
   - Cross-compilation sysroots not available

#### Error Messages You'll See
```
[WARNING] Cross-compiler not found: aarch64-linux-gnu-gcc
[WARNING] Attempting native build (may fail for incompatible architectures)
make: *** [applets/applets.o] Error 1
[ERROR] Failed to build busybox
```

## Solutions

### Option 1: Use android-native (Recommended)
```yaml
# In GitHub Actions workflow dispatch
build_modes: 'android-native'
```

**Advantages:**
- ✅ Works in GitHub Actions
- ✅ No compilation needed
- ✅ Fast (downloads only)
- ✅ Reliable
- ✅ All architectures supported

**Disadvantages:**
- ⚠️ Not PRoot compatible (uses Android linker)
- ⚠️ Deprecated for PRoot use cases

### Option 2: Build Locally with Docker
For static/linux-native builds, use Docker locally:

```bash
# Build static binaries in Docker
./test/test-static-build-docker.sh

# Or manually with Docker
docker run --rm -v $(pwd):/workspace -w /workspace \
  ubuntu:22.04 bash -c "
    apt-get update && apt-get install -y \
      gcc-aarch64-linux-gnu \
      gcc-arm-linux-gnueabihf \
      make wget curl
    ./scripts/build-static.sh --arch arm64-v8a --version 1.0.0
  "
```

**Advantages:**
- ✅ PRoot compatible
- ✅ Full control over build
- ✅ Can build all modes

**Disadvantages:**
- ❌ Requires Docker installed
- ❌ Slower (full compilation)
- ❌ Must run locally, not in GitHub Actions

### Option 3: Self-Hosted ARM Runners
Set up ARM-based GitHub Actions runners:

```yaml
jobs:
  build:
    runs-on: self-hosted-arm64  # Your ARM runner
```

**Advantages:**
- ✅ Native ARM compilation
- ✅ Works in GitHub Actions
- ✅ Can build all modes

**Disadvantages:**
- ❌ Requires infrastructure setup
- ❌ Maintenance overhead
- ❌ Cost of ARM hardware

## Workflow Configuration

### Current Default (Correct)
```yaml
build_modes:
  default: 'android-native'  # ✅ Works in GitHub Actions
```

### What NOT to Do
```yaml
build_modes: 'static'           # ❌ Will fail
build_modes: 'linux-native'     # ❌ Will fail
build_modes: 'static,android-native'  # ❌ Static will fail
```

## Recommended Workflow

For most users:
1. Use GitHub Actions with `android-native` mode
2. If you need PRoot compatibility, build locally with Docker
3. Upload Docker-built artifacts to GitHub Releases manually

## Testing

### Test android-native in GitHub Actions
```bash
# This works
gh workflow run build-bootstrap.yml \
  -f version=1.0.0 \
  -f build_modes=android-native \
  -f architectures=arm64-v8a,armeabi-v7a,x86_64,x86
```

### Test static builds locally
```bash
# This requires Docker
./test/test-static-build-docker.sh
```

## Summary

| Build Mode | GitHub Actions | Local Docker | ARM Runners | PRoot Compatible |
|------------|----------------|--------------|-------------|------------------|
| android-native | ✅ Yes | ✅ Yes | ✅ Yes | ❌ No |
| static | ❌ No | ✅ Yes | ✅ Yes | ✅ Yes |
| linux-native | ❌ No | ✅ Yes | ✅ Yes | ✅ Yes |

**Recommendation:** Use `android-native` in GitHub Actions. For PRoot-compatible builds, use Docker locally.
