# GitHub Actions Workflow Architecture

## Overview

The bootstrap builder uses GitHub Actions as the **central build orchestrator**. The workflow coordinates all build components from configuration validation through to release publishing.

## Workflow Structure

```
GitHub Actions Workflow (.github/workflows/build-bootstrap.yml)
│
├── Build Job (Matrix: mode × architecture)
│   │
│   ├── Step 1: Setup Build Environment
│   │   └── Install dependencies (gcc, make, musl, qemu, etc.)
│   │
│   ├── Step 2: Configuration Validation
│   │   └── scripts/config-validator.sh
│   │
│   ├── Step 3: Source Package Download
│   │   └── scripts/download-sources.sh
│   │
│   ├── Step 4: Compilation (parallel by mode)
│   │   ├── scripts/build-static.sh (for static mode)
│   │   ├── scripts/build-linux-native.sh (for linux-native mode)
│   │   └── scripts/download-bootstraps.sh (for android-native mode)
│   │
│   ├── Step 5: Bootstrap Assembly
│   │   └── scripts/assemble-bootstrap.sh
│   │
│   ├── Step 6: PRoot Compatibility Testing
│   │   └── scripts/test-proot-compatibility.sh
│   │
│   ├── Step 7: Archive Packaging
│   │   └── scripts/package-archives.sh
│   │
│   ├── Step 8: Checksum Generation
│   │   └── scripts/generate-checksums.sh
│   │
│   └── Step 9: Upload Artifacts
│       └── Upload to GitHub Actions artifacts
│
└── Deploy Job (runs after all builds complete)
    │
    ├── Step 1: Download All Artifacts
    │   └── Collect all mode/arch combinations
    │
    ├── Step 2: Update Manifest
    │   └── scripts/update-manifest.sh
    │
    ├── Step 3: Commit Manifest
    │   └── Push updated manifest to repository
    │
    └── Step 4: Create GitHub Release
        └── Upload all archives, checksums, test reports, and manifest
```

## Matrix Strategy

The workflow uses a matrix strategy to build multiple configurations in parallel:

```yaml
strategy:
  matrix:
    mode: [static, linux-native, android-native]
    arch: [arm64-v8a, armeabi-v7a, x86_64, x86]
  fail-fast: false
```

This creates **12 parallel jobs** (3 modes × 4 architectures), dramatically reducing build time.

## Component Integration

### 1. Configuration Validator
**Script**: `scripts/config-validator.sh`
**Purpose**: Validates build configuration before starting
**Workflow Integration**: Step 2 of build job
**Inputs**: 
- Build mode
- Target architecture
- Version

### 2. Source Package Manager
**Script**: `scripts/download-sources.sh`
**Purpose**: Downloads and verifies source packages
**Workflow Integration**: Step 3 of build job
**Caching**: Uses `.cache/sources/` for downloaded sources
**Outputs**: Extracted source code in `build/` directory

### 3. Compilation Engine
**Scripts**: 
- `scripts/build-static.sh` (static mode)
- `scripts/build-linux-native.sh` (linux-native mode)
- `scripts/download-bootstraps.sh` (android-native mode)

**Purpose**: Compiles binaries for target architecture
**Workflow Integration**: Step 4 of build job (conditional based on mode)
**Inputs**:
- `--arch`: Target architecture
- `--version`: Build version
**Outputs**: Compiled binaries in `build/{mode}/`

### 4. Bootstrap Assembler
**Script**: `scripts/assemble-bootstrap.sh`
**Purpose**: Assembles final bootstrap directory structure
**Workflow Integration**: Step 5 of build job
**Inputs**:
- `--mode`: Build mode
- `--arch`: Target architecture
- `--version`: Build version
**Outputs**: Complete bootstrap in `build/{mode}/bootstrap-{mode}-{arch}-{version}/`

### 5. PRoot Compatibility Tester
**Script**: `scripts/test-proot-compatibility.sh`
**Purpose**: Tests binaries in PRoot environment
**Workflow Integration**: Step 6 of build job (skipped for android-native)
**Inputs**:
- `--mode`: Build mode
- `--arch`: Target architecture
- `--version`: Build version
**Outputs**: Test report JSON in `test-results/`

### 6. Archive Packager
**Script**: `scripts/package-archives.sh`
**Purpose**: Creates compressed archives
**Workflow Integration**: Step 7 of build job
**Inputs**:
- `--version`: Build version
- `--mode`: Build mode
- `--arch`: Target architecture
**Outputs**: `.tar.xz` archives in `bootstrap-archives/`

### 7. Checksum Generator
**Script**: `scripts/generate-checksums.sh`
**Purpose**: Generates SHA256 checksums
**Workflow Integration**: Step 8 of build job
**Inputs**:
- `--version`: Build version
- `--mode`: Build mode
- `--arch`: Target architecture
**Outputs**: 
- `checksums-{mode}-{arch}.txt`
- `checksums-{mode}-{arch}.json`

### 8. Manifest Updater
**Script**: `scripts/update-manifest.sh`
**Purpose**: Updates bootstrap manifest with new release info
**Workflow Integration**: Step 2 of deploy job
**Inputs**:
- Version
- Repository name
- Checksum data (JSON)
- Mode/arch combination
- Test report base URL
**Outputs**: Updated `bootstrap-manifest.json`

### 9. Release Publisher
**Tool**: GitHub CLI (`gh`)
**Purpose**: Creates GitHub release and uploads assets
**Workflow Integration**: Step 4 of deploy job
**Uploads**:
- All bootstrap archives (`.tar.xz`)
- All checksum files (`.txt`, `.json`)
- All test reports (`.json`)
- Bootstrap manifest (`bootstrap-manifest.json`)

## Artifact Management

### Build Artifacts
Each build job uploads artifacts:
```
bootstrap-{mode}-{arch}-{version}/
├── bootstrap-{mode}-{arch}-{version}.tar.xz
├── checksums-{mode}-{arch}.txt
├── checksums-{mode}-{arch}.json
└── test-report-{mode}-{arch}.json
```

### Artifact Flow
1. **Build Job**: Creates and uploads artifacts
2. **Deploy Job**: Downloads all artifacts
3. **Deploy Job**: Organizes artifacts into proper directories
4. **Deploy Job**: Uploads to GitHub Release

## Environment Variables

The workflow uses these environment variables:

```yaml
VERSION: ${{ inputs.version }}           # Build version (e.g., 1.0.0)
BUILD_MODE: ${{ matrix.mode }}           # Build mode (static, linux-native, android-native)
TARGET_ARCH: ${{ matrix.arch }}          # Target architecture
RUN_TESTS: ${{ inputs.run_tests }}       # Whether to run PRoot tests
GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }} # For GitHub API access
REPO_NAME: ${{ github.repository }}      # Repository name
```

## Workflow Inputs

Users can customize the build via workflow dispatch inputs:

```yaml
version:        # Required - semantic version (X.Y.Z)
build_modes:    # Optional - comma-separated modes (default: static)
architectures:  # Optional - comma-separated archs (default: all)
run_tests:      # Optional - boolean (default: true)
```

## Error Handling

Each step includes error handling:
- Clear error messages
- Suggestions for common issues
- Non-zero exit codes on failure
- `fail-fast: false` allows other matrix jobs to continue

## Parallel Execution

The matrix strategy enables parallel execution:
- **12 build jobs** run simultaneously
- Each job is independent
- Failures in one job don't affect others
- Total build time ≈ time of slowest job (not sum of all jobs)

## Caching Strategy

The workflow uses caching to speed up builds:
- **Source cache**: `.cache/sources/` (downloaded packages)
- **Build cache**: `.cache/build/` (compiled objects)
- **PRoot cache**: `.cache/proot-{arch}` (PRoot binaries)

## Release Process

1. **Trigger**: Manual workflow dispatch with version input
2. **Build**: Matrix jobs build all mode/arch combinations
3. **Test**: PRoot compatibility tests run (except android-native)
4. **Package**: Archives created and checksums generated
5. **Collect**: Deploy job downloads all artifacts
6. **Manifest**: Update manifest with new release info
7. **Commit**: Push manifest changes to repository
8. **Release**: Create GitHub release with all assets
9. **Publish**: Assets available at predictable URLs

## URLs

After release, assets are available at:

```
# Versioned URLs
https://github.com/{owner}/{repo}/releases/download/v{version}/bootstrap-{mode}-{arch}-{version}.tar.xz
https://github.com/{owner}/{repo}/releases/download/v{version}/checksums-{mode}-{arch}.txt
https://github.com/{owner}/{repo}/releases/download/v{version}/test-report-{mode}-{arch}.json
https://github.com/{owner}/{repo}/releases/download/v{version}/bootstrap-manifest.json

# Latest URLs
https://github.com/{owner}/{repo}/releases/latest/download/bootstrap-manifest.json
```

## Advantages of This Architecture

1. **Centralized Orchestration**: GitHub Actions controls the entire pipeline
2. **Parallel Builds**: Matrix strategy enables concurrent builds
3. **Reproducible**: Same inputs always produce same outputs
4. **Traceable**: Every build has a workflow run with full logs
5. **Automated**: No manual steps required
6. **Scalable**: Easy to add new architectures or build modes
7. **Testable**: Each component can be tested independently
8. **Maintainable**: Clear separation of concerns

## Local Testing

To test the workflow locally, use the test scripts:

```bash
# Test full workflow simulation
./test/test-full-workflow.sh

# Test individual components
./test/test-static-build-scripts.sh
./test/test-linux-native-scripts.sh
./test/test-proot-compatibility-system.sh
```

## Monitoring

Monitor builds via:
- GitHub Actions UI: `https://github.com/{owner}/{repo}/actions`
- Workflow runs: Each run shows all matrix jobs
- Artifacts: Download artifacts from completed runs
- Releases: View published releases

## Future Enhancements

Potential improvements:
- **Build caching**: Cache compiled objects between runs
- **Incremental builds**: Only rebuild changed components
- **Performance metrics**: Track build times and sizes
- **Automated testing**: Run integration tests on releases
- **Multi-platform**: Support building on different OS runners
