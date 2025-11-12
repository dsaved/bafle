# Testing Documentation

## Full Workflow Test Results

The complete bootstrap build and deploy workflow has been tested locally and all issues have been resolved.

### Test Script

Run the full workflow test:

```bash
./test-full-workflow.sh
```

This script simulates the complete GitHub Actions workflow locally, including all 7 steps.

### Test Results

All workflow steps complete successfully:

1. **Download Termux Bootstrap Packages** - PASS
   - Downloads latest Termux bootstrap for all 4 architectures
   - Restructures to include usr directory
   - All architectures downloaded successfully

2. **Package Bootstrap Archives** - PASS
   - Creates tar.gz archives for all architectures
   - Sets correct permissions on binaries
   - Compression level 9 applied
   - Archive sizes: 24-27 MB per architecture

3. **Validate Bootstrap Archives** - PASS
   - Extracts and validates all archives
   - Verifies usr/bin directory exists
   - Checks for critical binaries (bash, apt, dpkg, tar, gzip)
   - Validates executable permissions
   - All archives pass validation

4. **Generate Checksums and Calculate Sizes** - PASS
   - Calculates SHA-256 checksums for all archives
   - Determines file sizes in bytes
   - Generates checksums.txt and checksums.json
   - All checksums generated successfully

5. **Update Bootstrap Manifest** - PASS
   - Updates version and last_updated fields
   - Updates URLs for all architectures
   - Updates checksums and sizes
   - Validates JSON syntax
   - Manifest updated successfully

6. **Validate Manifest JSON Syntax** - PASS
   - Verifies manifest is valid JSON
   - All fields properly formatted
   - URLs correctly constructed

7. **Workflow Summary** - PASS
   - All assets created
   - All checksums verified
   - Manifest properly updated

### Issues Found and Fixed

#### Issue 1: Bash 3.2 Compatibility
**Problem**: macOS uses bash 3.2 which doesn't support associative arrays.

**Solution**: 
- Replaced associative arrays with simple array mappings
- Added helper functions for architecture lookups
- Scripts now work on both bash 3.2 (macOS) and bash 4+ (Linux)

**Files Modified**:
- `scripts/download-bootstraps.sh`
- `scripts/validate-archives.sh`

#### Issue 2: Bootstrap Directory Structure
**Problem**: Termux bootstrap extracts without a usr directory, but packaging script expects usr directory.

**Solution**:
- Modified download script to restructure bootstrap after extraction
- Creates usr directory and moves all contents into it
- Matches expected structure for packaging

**Files Modified**:
- `scripts/download-bootstraps.sh`

#### Issue 3: Validation Checking Wrong Binaries
**Problem**: Validation script checked for git, node, python which aren't in base Termux bootstrap.

**Solution**:
- Updated critical binaries list to match base bootstrap (bash, apt, dpkg)
- Changed alternative binaries to tar and gzip
- Removed checks for packages that are installed via apt later

**Files Modified**:
- `scripts/validate-archives.sh`

#### Issue 4: Checksum Script Path Issue
**Problem**: Checksum script hardcoded ARCHIVE_DIR path, causing issues when run from inside that directory.

**Solution**:
- Made ARCHIVE_DIR configurable with default fallback
- Script now works when run from any directory
- Workflow can run it from bootstrap-archives directory

**Files Modified**:
- `scripts/generate-checksums.sh`

### Archive Structure Verification

Extracted archive structure (verified):

```
usr/
├── bin/          (256 executables including bash, apt, dpkg, tar, gzip)
├── etc/          (configuration files)
├── include/      (header files)
├── lib/          (shared libraries)
├── libexec/      (helper executables)
├── share/        (shared data)
├── tmp/          (temporary directory)
├── var/          (variable data)
└── SYMLINKS.txt  (symlink definitions)
```

### Generated Assets

Each workflow run produces:

- `bootstrap-arm64-v8a-{version}.tar.gz` (~27 MB)
- `bootstrap-armeabi-v7a-{version}.tar.gz` (~24 MB)
- `bootstrap-x86_64-{version}.tar.gz` (~27 MB)
- `bootstrap-x86-{version}.tar.gz` (~27 MB)
- `checksums.txt` (SHA-256 checksums)
- `checksums.json` (JSON format checksums with sizes)
- `bootstrap-manifest.json` (updated with new version)

### Checksums Example

```
98c616d4095507b86f647498f7e0a724d16e565b133b262b8617a42d4317cd07  bootstrap-arm64-v8a-1.0.0.tar.gz
c4cc049737bd46fd1ce1d924951e25f8cb37b337bb1a2f2de83e5054b27d0598  bootstrap-armeabi-v7a-1.0.0.tar.gz
33f0267a7867527ba529e55b8d1be95a0db7c2fea6fd6f45447dee3244f7a9b5  bootstrap-x86_64-1.0.0.tar.gz
f0c1344e4324e957da05f5a3a18f53b4f61f110208e05334cfb2a49dd0a20a01  bootstrap-x86-1.0.0.tar.gz
```

### Manifest Example

```json
{
  "version": "1.0.0",
  "last_updated": "2025-11-12",
  "architectures": {
    "arm64-v8a": {
      "url": "https://github.com/dsaved/bafle/releases/download/v1.0.0/bootstrap-arm64-v8a-1.0.0.tar.gz",
      "size": 28710588,
      "checksum": "sha256:98c616d4095507b86f647498f7e0a724d16e565b133b262b8617a42d4317cd07",
      "min_android_version": 21
    }
  }
}
```

### Performance

Approximate execution times (local test on macOS):

- Download: ~2-3 minutes (depends on network)
- Package: ~1-2 minutes (compression)
- Validate: ~30 seconds
- Checksums: ~10 seconds
- Manifest: <1 second

**Total**: ~4-7 minutes for complete workflow

### GitHub Actions Compatibility

All scripts are now compatible with:

- Ubuntu (GitHub Actions runner)
- macOS (local development)
- Bash 3.2+ (macOS default)
- Bash 4+ (Linux default)

### Next Steps

The workflow is ready for production use:

1. Trigger workflow from GitHub Actions
2. Provide semantic version number (e.g., 1.0.0)
3. Workflow will automatically:
   - Download and package bootstraps
   - Validate archives
   - Generate checksums
   - Update manifest
   - Create GitHub release
   - Upload all assets
   - Commit manifest changes

### Accessing Bootstrap Files

After the workflow completes, bootstrap files are available via:

**Latest Manifest** (recommended for apps):
```
https://github.com/dsaved/bafle/releases/latest/download/bootstrap-manifest.json
```

**Latest Bootstrap Archives**:
```
https://github.com/dsaved/bafle/releases/latest/download/bootstrap-arm64-v8a-{version}.tar.gz
https://github.com/dsaved/bafle/releases/latest/download/bootstrap-armeabi-v7a-{version}.tar.gz
https://github.com/dsaved/bafle/releases/latest/download/bootstrap-x86_64-{version}.tar.gz
https://github.com/dsaved/bafle/releases/latest/download/bootstrap-x86-{version}.tar.gz
```

**Benefits**:
- Apps always get the latest bootstrap version
- No app updates needed when releasing new bootstrap versions
- Users automatically receive updates
- Specific versions remain accessible for rollback if needed

### Cleanup

To clean up test artifacts:

```bash
rm -rf bootstrap-downloads bootstrap-archives checksums.txt checksums.json temp-validation bootstrap-manifest.json.backup
```
