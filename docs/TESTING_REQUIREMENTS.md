# Testing Requirements

## Overview

This project has different testing requirements depending on what you're testing.

## Quick Tests (Works Anywhere)

### Workflow Structure Test
Tests that all scripts exist and workflow is properly configured.

**Requirements**: None (just bash and basic tools)

**Run**:
```bash
./test/test-workflow-structure.sh
```

**Time**: ~1 second

## Full Build Tests (Requires Linux)

### Why Linux is Required

Static and linux-native builds compile C code for Linux. This requires:
- Linux kernel headers
- Linux-specific build tools (musl-gcc, glibc)
- Linux system libraries
- ELF binary format support

**macOS/Windows cannot build Linux binaries natively.**

### Option 1: Docker (Recommended for Local Testing)

Use Docker to create a Linux environment:

```bash
./test/test-static-build-docker.sh
```

**Requirements**:
- Docker installed
- ~2GB disk space
- ~10-15 minutes for first run

### Option 2: GitHub Actions (Easiest)

Just push to GitHub and let Actions run the tests:

```bash
git push origin your-branch
```

GitHub Actions provides Ubuntu runners with all tools pre-installed.

### Option 3: Native Linux

If you're on Linux:

```bash
# Install dependencies
sudo apt-get install build-essential musl-tools musl-dev

# Run test
./test/test-github-workflow-simulation.sh
```

## Android-Native Mode (Works Anywhere)

Android-native mode just downloads pre-built binaries, so it works on any OS:

```bash
VERSION=0.0.1 ./scripts/download-bootstraps.sh
```

## Summary Table

| Test | macOS | Linux | Windows | Docker | GitHub Actions |
|------|-------|-------|---------|--------|----------------|
| Workflow Structure | ✅ | ✅ | ✅ | ✅ | ✅ |
| Android-Native | ✅ | ✅ | ✅ | ✅ | ✅ |
| Static Build | ❌ | ✅ | ❌ | ✅ | ✅ |
| Linux-Native Build | ❌ | ✅ | ❌ | ✅ | ✅ |

## Recommended Testing Workflow

1. **During Development** (macOS/Windows):
   - Run `./test/test-workflow-structure.sh` to validate structure
   - Test android-native downloads if needed
   - Use Docker for static/linux-native builds

2. **Before Pushing**:
   - Run Docker tests if available
   - Or just push and let GitHub Actions test

3. **In CI/CD**:
   - GitHub Actions runs full test suite on Linux
   - All build modes tested in parallel

## Why This Design?

The project builds **Linux binaries for Android devices**. Android uses the Linux kernel, so we need Linux build tools. Cross-compiling from macOS/Windows is possible but complex and error-prone.

Using GitHub Actions (free Linux runners) is the simplest and most reliable approach.
