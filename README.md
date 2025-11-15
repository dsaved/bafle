# Bootstrap Build Workflow

Automated GitHub Actions workflow for building and deploying bootstrap packages for mobile code editor applications with PRoot compatibility.

## Overview

This project provides a complete CI/CD pipeline orchestrated by GitHub Actions that builds, tests, and publishes bootstrap packages. The workflow coordinates all build components from source download through compilation, testing, packaging, and release publishing.

**Key Architecture**: GitHub Actions serves as the central build orchestrator, coordinating all scripts and managing parallel builds across multiple modes and architectures. See [Workflow Architecture](docs/WORKFLOW_ARCHITECTURE.md) for details.

## Features

- Automated bootstrap package downloads from Termux official releases
- Multi-architecture support (arm64-v8a, armeabi-v7a, x86_64, x86)
- Archive validation with critical binary checks
- SHA-256 checksum generation
- Automated GitHub release creation
- Bootstrap manifest management
- Comprehensive error handling and logging

## Supported Architectures

- **arm64-v8a** - 64-bit ARM (modern Android devices)
- **armeabi-v7a** - 32-bit ARM (older Android devices)
- **x86_64** - 64-bit x86 (emulators and tablets)
- **x86** - 32-bit x86 (older emulators)

## Build Modes

The bootstrap builder supports three build modes:

### Static Mode (Recommended)

Produces statically-linked binaries that work in PRoot environments without requiring a dynamic linker.

```bash
./scripts/build-wrapper.sh --mode static --arch arm64-v8a --version 1.0.0
```

**Advantages:**
- ✅ Full PRoot compatibility
- ✅ No dynamic linker required
- ✅ Maximum portability

**Use when:** You need PRoot compatibility (recommended for most use cases)

### Linux-Native Mode

Produces dynamically-linked binaries using standard Linux dynamic linker.

```bash
./scripts/build-wrapper.sh --mode linux-native --arch arm64-v8a --version 1.0.0
```

**Advantages:**
- ✅ PRoot compatible
- ✅ Smaller size than static
- ✅ Standard Linux linker

**Use when:** You need PRoot compatibility with smaller bootstrap size

### Android-Native Mode (DEPRECATED)

⚠️ **DEPRECATED**: This mode is maintained for backward compatibility only and will be removed in a future release.

Downloads pre-built Termux bootstrap packages with Android-native binaries.

```bash
./scripts/build-wrapper.sh --mode android-native --arch arm64-v8a --version 1.0.0
```

**Limitations:**
- ❌ NOT PRoot compatible
- ❌ Requires Termux environment or root access
- ❌ Limited portability

**Migration:** See [Android-Native Deprecation Notice](docs/ANDROID_NATIVE_DEPRECATION.md) for migration guide.

**Use when:** You absolutely need backward compatibility with existing android-native deployments (not recommended for new projects)

## Workflow Usage

### Triggering a Build

1. Navigate to the Actions tab in your GitHub repository
2. Select "Build and Deploy Bootstrap" workflow
3. Click "Run workflow"
4. Enter a semantic version number (e.g., 1.0.0)
5. Click "Run workflow" to start the build

### Version Format

Version numbers must follow semantic versioning: `X.Y.Z`

Valid examples: `1.0.0`, `2.3.1`, `10.15.3`

Invalid examples: `v1.0.0`, `1.0`, `1.0.0-beta`

## Bootstrap Structure

The Termux bootstrap packages follow the Filesystem Hierarchy Standard (FHS) with a `usr/` directory at the root level:

```
bootstrap-{arch}-{version}.tar.gz
└── usr/
    ├── bin/          # Executables (bash, apt, dpkg, etc.)
    ├── lib/          # Shared libraries
    ├── etc/          # Configuration files
    ├── include/      # Header files
    ├── libexec/      # Helper executables
    ├── share/        # Shared data
    ├── tmp/          # Temporary directory
    ├── var/          # Variable data
    └── SYMLINKS.txt  # Symlink definitions
```

### PRoot Compatibility

The bootstrap packages are designed to work with PRoot, a user-space implementation of chroot that allows running Linux environments on Android without root access.

**Critical Requirements:**

1. **Directory Structure**: The bootstrap must maintain the correct `usr/` directory structure. Nested `usr/usr/` directories will cause binaries to fail with "Function not implemented" errors.

2. **ELF Interpreter**: Termux binaries are compiled for Android and reference the Android system linker:
   - 64-bit ARM: `/system/bin/linker64`
   - 32-bit ARM: `/system/bin/linker`
   - x86_64: `/system/bin/linker64`
   - x86: `/system/bin/linker`

3. **Symlinks**: The bootstrap includes symlinks that must be preserved during packaging and extraction.

## Scripts

### download-bootstraps.sh

Downloads pre-built Termux bootstrap packages for all supported architectures from the official Termux repository. Preserves the original bootstrap structure without restructuring.

### package-archives.sh

Creates compressed tar.gz archives from bootstrap directories with proper permissions and ownership settings. Archives the entire directory structure to maintain compatibility with PRoot.

### validate-archives.sh

Validates archive integrity, verifies the presence of critical binaries (bash, apt, dpkg), checks directory structure, and validates ELF interpreter paths for Android compatibility.

### generate-checksums.sh

Calculates SHA-256 checksums and file sizes for all bootstrap archives.

### update-manifest.sh

Updates the bootstrap-manifest.json file with new version information, URLs, checksums, and file sizes.

## Output Files

Each workflow run produces:

- 4 bootstrap archives (one per architecture)
- checksums.txt file with SHA-256 hashes
- Updated bootstrap-manifest.json
- GitHub release with all assets

## Bootstrap Manifest

The manifest file provides metadata for each architecture:

```json
{
  "version": "1.0.0",
  "last_updated": "2025-11-12",
  "architectures": {
    "arm64-v8a": {
      "url": "https://github.com/dsaved/bafle/releases/download/v1.0.0/bootstrap-arm64-v8a-1.0.0.tar.gz",
      "size": 89128960,
      "checksum": "sha256:...",
      "min_android_version": 21
    }
  }
}
```

## Requirements

The workflow runs on Ubuntu and requires:

- curl (for downloads)
- tar (for archive creation)
- jq (for JSON manipulation)
- sha256sum or shasum (for checksums)
- unzip (for extracting Termux packages)
- GitHub CLI (for release management)

All dependencies are pre-installed on GitHub Actions ubuntu-latest runners.

## Error Handling

All scripts implement comprehensive error handling:

- Exit on first error (`set -e`)
- Fail on undefined variables (`set -u`)
- Catch errors in pipes (`set -o pipefail`)
- Descriptive error messages with troubleshooting hints
- Color-coded logging (INFO, WARN, ERROR)
- Retry logic for network operations

## Workflow Steps

1. Validate version format
2. Download Termux bootstrap packages
3. Package archives with correct permissions
4. Validate archive integrity
5. Generate checksums and calculate sizes
6. Update bootstrap manifest
7. Commit and push manifest changes
8. Create GitHub release with all assets
9. Upload manifest to release

## Testing

Run the test suite locally:

```bash
chmod +x test-workflow.sh
./test-workflow.sh
```

The test suite verifies:

- Version validation logic
- Script executability
- Error handling in all scripts
- Required tools availability
- Manifest file validity
- Logging functions
- Bootstrap directory structure
- Detection of nested usr/usr/ directories

## Troubleshooting

### "Function not implemented" Error in PRoot

**Symptom**: When trying to execute bash or other binaries in PRoot, you get:
```
bash: Function not implemented
```

**Cause**: This error occurs when the bootstrap has an incorrect directory structure, typically a nested `usr/usr/` directory instead of the correct `usr/` structure.

**Solution**:
1. Extract the bootstrap archive and verify the structure:
   ```bash
   tar -tzf bootstrap-arm64-v8a-1.0.0.tar.gz | head -20
   ```
   
2. You should see paths like `usr/bin/bash`, NOT `usr/usr/bin/bash`

3. If the structure is incorrect, regenerate the bootstrap using the fixed scripts

### Binaries Not Found in PRoot

**Symptom**: PRoot reports that binaries don't exist even though they're in the archive.

**Cause**: The bootstrap was extracted or packaged incorrectly, placing files in the wrong directory hierarchy.

**Solution**:
1. Verify the archive contains the correct structure:
   ```bash
   tar -tzf bootstrap-arm64-v8a-1.0.0.tar.gz | grep "^usr/bin/bash$"
   ```

2. Check for incorrect nested structure:
   ```bash
   tar -tzf bootstrap-arm64-v8a-1.0.0.tar.gz | grep "^usr/usr/"
   ```
   This should return no results.

### ELF Interpreter Issues

**Symptom**: Binaries fail to execute with linker errors.

**Cause**: The binaries reference the Android system linker which may not be accessible in your PRoot environment.

**Diagnosis**:
1. Check the ELF interpreter for a binary:
   ```bash
   readelf -l usr/bin/bash | grep interpreter
   ```
   
2. You should see: `[Requesting program interpreter: /system/bin/linker64]`

**Solution**: Ensure your PRoot environment has access to the Android system directories, or use a bootstrap compiled with a different linker.

### Validation Failures

**Symptom**: The validation script reports missing binaries or incorrect structure.

**Cause**: The bootstrap was not downloaded or packaged correctly.

**Solution**:
1. Clean the download and archive directories:
   ```bash
   rm -rf bootstrap-downloads bootstrap-archives
   ```

2. Re-run the download and package scripts:
   ```bash
   ./scripts/download-bootstraps.sh
   VERSION=1.0.0 ./scripts/package-archives.sh
   ```

3. Run validation again:
   ```bash
   VERSION=1.0.0 ./scripts/validate-archives.sh
   ```

### Checksum Mismatches

**Symptom**: Downloaded archives have different checksums than expected.

**Cause**: The archive was modified or corrupted during download/packaging.

**Solution**:
1. Verify the archive integrity:
   ```bash
   tar -tzf bootstrap-arm64-v8a-1.0.0.tar.gz > /dev/null
   ```

2. If the archive is corrupted, regenerate it from the bootstrap-downloads directory

3. Recalculate checksums:
   ```bash
   VERSION=1.0.0 ./scripts/generate-checksums.sh
   ```

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       └── build-bootstrap.yml
├── scripts/
│   ├── download-bootstraps.sh
│   ├── package-archives.sh
│   ├── validate-archives.sh
│   ├── generate-checksums.sh
│   └── update-manifest.sh
├── bootstrap-manifest.json
├── .gitignore
└── README.md
```

## License

This project is provided as-is for building and distributing Termux bootstrap packages.

## Credits

Bootstrap packages are sourced from the official Termux project:
https://github.com/termux/termux-packages
