# Bootstrap Build Workflow

Automated GitHub Actions workflow for building and deploying Termux bootstrap packages for mobile code editor applications.

## Overview

This project provides a complete CI/CD pipeline that downloads pre-built Termux bootstrap packages, repackages them for Android architectures, validates their integrity, and publishes them as GitHub releases with automatic manifest updates.

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

## Scripts

### download-bootstraps.sh

Downloads pre-built Termux bootstrap packages for all supported architectures from the official Termux repository.

### package-archives.sh

Creates compressed tar.gz archives from bootstrap directories with proper permissions and ownership settings.

### validate-archives.sh

Validates archive integrity and verifies the presence of critical binaries (bash, git, node, python).

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
