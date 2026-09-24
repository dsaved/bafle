# PRoot Compatibility Testing

This document describes how to use the PRoot compatibility testing system to verify that bootstrap binaries work correctly in a PRoot environment.

## Overview

The PRoot compatibility testing system consists of two main scripts:

1. **`scripts/setup-test-proot.sh`** - Downloads and sets up PRoot binary for testing
2. **`scripts/test-proot-compatibility.sh`** - Runs compatibility tests on bootstrap directories

## Quick Start

### Test a Bootstrap Directory

```bash
# Test with automatic PRoot download
./scripts/test-proot-compatibility.sh --arch arm64-v8a bootstrap-static-arm64-v8a-1.0.0

# Test with custom PRoot binary
./scripts/test-proot-compatibility.sh --arch arm64-v8a --proot /path/to/proot bootstrap-static-arm64-v8a-1.0.0

# Test with verbose output and custom report location
./scripts/test-proot-compatibility.sh \
  --arch arm64-v8a \
  --verbose \
  --report test-results/my-report.json \
  bootstrap-static-arm64-v8a-1.0.0
```

## Setup PRoot Binary

If you want to download PRoot separately:

```bash
# Download PRoot for arm64-v8a
./scripts/setup-test-proot.sh --arch arm64-v8a --output .cache/proot/proot-arm64

# Download specific version
./scripts/setup-test-proot.sh --arch arm64-v8a --version 5.4.0 --output /tmp/proot
```

## Test Cases

The compatibility testing system runs the following tests:

### Basic Tests
- Shell execution (`echo 'Hello from PRoot'`)
- Shell version check
- File listing (`ls /usr/bin`)
- File reading (`cat /usr/etc/profile`)

### Text Processing
- Grep test
- Sed test (if available)
- Awk test (if available)

### File Operations
- Create file
- Copy file
- Remove file
- Directory operations

### System Tests
- Environment variables
- Path resolution
- Process listing (if ps available)
- Symlink handling

## Test Report

The test generates a JSON report with the following structure:

```json
{
  "bootstrapPath": "bootstrap-static-arm64-v8a-1.0.0",
  "buildMode": "static",
  "architecture": "arm64-v8a",
  "testDate": "2025-11-14T10:30:00Z",
  "prootVersion": "5.4.0",
  "prootCompatible": true,
  "testsRun": 15,
  "testsPassed": 15,
  "testsFailed": 0,
  "tests": [
    {
      "command": "echo 'Hello from PRoot'",
      "status": "passed",
      "exitCode": 0,
      "executionTime": "0.050s",
      "output": "Hello from PRoot"
    }
  ],
  "binaryAnalysis": [
    {
      "binary": "bash",
      "type": "static",
      "size": "1.2MB",
      "dependencies": []
    }
  ]
}
```

## Binary Analysis

The system analyzes key binaries in the bootstrap:

- **Type**: Static or dynamic
- **Size**: Human-readable size
- **Dependencies**: List of shared library dependencies (for dynamic binaries)
- **Interpreter**: Dynamic linker path (for dynamic binaries)

## Exit Codes

- **0**: All tests passed, bootstrap is PRoot-compatible
- **1**: One or more tests failed, bootstrap may have compatibility issues

## Architecture Support

Supported architectures:
- `arm64-v8a` (aarch64)
- `armeabi-v7a` (arm)
- `x86_64`
- `x86` (i686)

## Integration with Build Pipeline

The PRoot compatibility testing can be integrated into the build pipeline:

```bash
# After building a bootstrap
./scripts/assemble-bootstrap.sh --mode static --arch arm64-v8a --version 1.0.0

# Test the bootstrap
./scripts/test-proot-compatibility.sh \
  --arch arm64-v8a \
  --report test-results/proot-test-static-arm64-v8a.json \
  bootstrap-archives/bootstrap-static-arm64-v8a-1.0.0

# Check exit code
if [ $? -eq 0 ]; then
  echo "Bootstrap is PRoot-compatible!"
else
  echo "Bootstrap has compatibility issues"
  exit 1
fi
```

## Troubleshooting

### PRoot Download Fails

If PRoot download fails, you can:
1. Download PRoot manually from https://github.com/termux/proot/releases
2. Specify the path with `--proot /path/to/proot`

### Tests Fail with "No such file or directory"

This usually indicates:
- Dynamic binaries using Android linker instead of Linux linker
- Missing shared libraries
- Incorrect RPATH configuration

Check the binary analysis in the report to see the linker and dependencies.

### Architecture Detection Fails

If architecture cannot be detected automatically:
- Always specify `--arch` explicitly
- Ensure bootstrap directory name includes architecture tag

## Requirements Satisfied

This testing system satisfies the following requirements:

- **4.1**: Test suite verifies binary compatibility with PRoot
- **4.2**: Basic commands (ls, cat, echo) executed in PRoot environment
- **4.3**: Failures reported with diagnostic information
- **4.4**: Binaries verified without "No such file or directory" errors
- **4.5**: Compatibility report generated with test results and binary analysis

## Examples

### Test Static Build

```bash
./scripts/test-proot-compatibility.sh \
  --arch arm64-v8a \
  --verbose \
  bootstrap-archives/bootstrap-static-arm64-v8a-1.0.0
```

### Test Linux-Native Build

```bash
./scripts/test-proot-compatibility.sh \
  --arch arm64-v8a \
  --verbose \
  bootstrap-archives/bootstrap-linux-native-arm64-v8a-1.0.0
```

### Batch Testing Multiple Architectures

```bash
for arch in arm64-v8a armeabi-v7a x86_64 x86; do
  echo "Testing $arch..."
  ./scripts/test-proot-compatibility.sh \
    --arch $arch \
    --report test-results/proot-test-static-$arch.json \
    bootstrap-archives/bootstrap-static-$arch-1.0.0
done
```
