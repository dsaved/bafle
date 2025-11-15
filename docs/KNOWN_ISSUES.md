# Known Issues

## Build System

### Source Compilation Not Yet Functional

**Status**: Work in Progress

**Issue**: The source compilation pipeline (static and linux-native modes) is not yet fully functional. Builds fail due to:

1. **Missing build dependencies**: musl-gcc, cross-compilation toolchains
2. **Platform-specific issues**: macOS vs Linux differences
3. **Package-specific configuration**: Each package (bash, busybox, coreutils) needs specific build flags

**Current State**:
- ✅ Workflow structure is correct
- ✅ All scripts exist and are executable
- ✅ Configuration validation works
- ✅ Source download works
- ❌ Compilation fails
- ❌ Assembly not tested
- ❌ PRoot testing not tested

**Workaround**: Use android-native mode which downloads pre-built binaries:
```bash
# In workflow, use:
build_modes: 'android-native'
```

**Next Steps**:
1. Set up proper build environment in GitHub Actions
2. Install cross-compilation toolchains
3. Fix package-specific build scripts
4. Test on actual Linux environment (not macOS)
5. Add Docker-based builds for reproducibility

## Recommended Approach

For now, the project should use **android-native mode** which is proven to work:

```yaml
# .github/workflows/build-bootstrap.yml
inputs:
  build_modes:
    default: 'android-native'  # Use this instead of 'static'
```

This downloads pre-built Termux bootstraps which are tested and working.

## Future Work

To make static/linux-native builds work:

### 1. Docker-Based Builds
Use Docker containers with pre-configured build environments:
```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: alpine:latest  # or custom build image
```

### 2. Install Build Dependencies
```yaml
- name: Install build tools
  run: |
    apt-get update
    apt-get install -y \
      gcc-aarch64-linux-gnu \
      gcc-arm-linux-gnueabihf \
      musl-tools \
      musl-dev
```

### 3. Simplify Build Scripts
- Remove complex configuration
- Use pre-configured build options
- Focus on one architecture at a time

### 4. Test Incrementally
- Test bash build alone
- Test busybox build alone
- Test coreutils build alone
- Then combine

## Timeline

- **Phase 1** (Current): Use android-native mode
- **Phase 2** (1-2 weeks): Fix static builds for x86_64 only
- **Phase 3** (2-4 weeks): Add cross-compilation for ARM
- **Phase 4** (4-6 weeks): Full multi-architecture support

## Contact

If you need PRoot-compatible builds urgently, consider:
1. Using Termux's proot package directly
2. Building manually on a Linux system
3. Using pre-built static binaries from other sources
