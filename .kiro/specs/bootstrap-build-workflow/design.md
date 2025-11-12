# Design Document: Bootstrap Build Workflow

## Overview

This design describes a GitHub Actions workflow that automates the complete bootstrap build and release pipeline. The workflow downloads pre-built Termux bootstrap packages, packages them into architecture-specific archives, generates checksums, creates GitHub releases, and updates the bootstrap manifest file.

The design leverages Termux's existing bootstrap packages to avoid complex cross-compilation, focusing instead on packaging, validation, and deployment automation.

## Architecture

### High-Level Flow

```
Manual Trigger (version input)
    ↓
Download Termux Bootstrap Packages (4 architectures)
    ↓
Package & Compress Archives
    ↓
Validate Archives
    ↓
Generate Checksums & Calculate Sizes
    ↓
Create GitHub Release
    ↓
Update bootstrap-manifest.json
    ↓
Commit & Push Manifest Changes
    ↓
Upload Manifest to Release
```

### Workflow Trigger

- **Event**: `workflow_dispatch` (manual trigger)
- **Input**: `version` (string, required) - Semantic version number (e.g., "1.0.0")
- **Validation**: Version must match pattern `^\d+\.\d+\.\d+$`

### Build Strategy

Instead of building from source (which requires complex cross-compilation setup), the workflow will:

1. Download pre-built Termux bootstrap packages from the official Termux releases
2. Extract and repackage them into the required directory structure
3. Set correct permissions
4. Create compressed tar.gz archives

This approach is faster, more reliable, and leverages Termux's well-tested build infrastructure.

## Components and Interfaces

### 1. Workflow Configuration File

**Location**: `.github/workflows/build-bootstrap.yml`

**Structure**:
```yaml
name: Build and Deploy Bootstrap
on:
  workflow_dispatch:
    inputs:
      version:
        description: 'Version number (e.g., 1.0.0)'
        required: true
        type: string

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - Checkout repository
      - Download Termux bootstraps
      - Package archives
      - Validate archives
      - Generate checksums
      - Create GitHub release
      - Update manifest
      - Commit and push manifest
```

### 2. Bootstrap Download Script

**Purpose**: Download pre-built Termux bootstrap packages for all architectures

**Script**: `scripts/download-bootstraps.sh`

**Inputs**:
- Version number (from workflow input)

**Outputs**:
- Downloaded bootstrap zip files for each architecture
- Extracted bootstrap directories

**Logic**:
```bash
for each architecture (aarch64, arm, x86_64, i686):
  - Map to Termux architecture name
  - Download from Termux releases (latest or specific version)
  - Extract zip file
  - Rename directory to match Android architecture naming
```

**Termux Bootstrap URL Pattern**:
```
https://github.com/termux/termux-packages/releases/download/bootstrap-{DATE}/bootstrap-{ARCH}.zip
```

### 3. Archive Packaging Script

**Purpose**: Create tar.gz archives from bootstrap directories

**Script**: `scripts/package-archives.sh`

**Inputs**:
- Bootstrap directories for each architecture
- Version number

**Outputs**:
- `bootstrap-arm64-v8a-{version}.tar.gz`
- `bootstrap-armeabi-v7a-{version}.tar.gz`
- `bootstrap-x86_64-{version}.tar.gz`
- `bootstrap-x86-{version}.tar.gz`

**Logic**:
```bash
for each architecture:
  - Set executable permissions on usr/bin/*
  - Set executable permissions on usr/libexec/* (if exists)
  - Create tar.gz with:
    - Owner/group set to 0 (root)
    - Numeric owner IDs
    - Compression level 9
    - Only include usr/ directory
```

### 4. Archive Validation Script

**Purpose**: Verify archives are valid and contain required files

**Script**: `scripts/validate-archives.sh`

**Inputs**:
- Archive files

**Outputs**:
- Exit code 0 (success) or 1 (failure)
- Validation report

**Validation Checks**:
1. Archive can be extracted without errors
2. `usr/bin` directory exists
3. Critical binaries present:
   - `bash`
   - `git`
   - `node` (or `nodejs`)
   - `python3` (or `python`)
4. Binaries are executable (have execute bit set)

### 5. Checksum Generation Script

**Purpose**: Calculate SHA-256 checksums and file sizes

**Script**: `scripts/generate-checksums.sh`

**Inputs**:
- Archive files

**Outputs**:
- `checksums.txt` file with format: `{checksum}  {filename}`
- JSON output with checksum and size for each architecture

**Logic**:
```bash
for each archive:
  - Calculate SHA-256: sha256sum {archive}
  - Get file size: stat -c%s {archive}
  - Store in checksums.txt
  - Output JSON: {"arch": "arm64-v8a", "checksum": "sha256:...", "size": 12345}
```

### 6. Manifest Update Script

**Purpose**: Update bootstrap-manifest.json with new release information

**Script**: `scripts/update-manifest.sh`

**Inputs**:
- Version number
- Repository name (from GitHub context)
- Checksum and size data (JSON from previous step)

**Outputs**:
- Updated `bootstrap-manifest.json` file

**Logic**:
```bash
- Read current manifest
- Update version field
- Update last_updated field (current date)
- For each architecture:
  - Update URL with new version tag
  - Update checksum
  - Update size
- Write updated manifest
- Validate JSON syntax
```

### 7. GitHub Release Creation

**Tool**: GitHub CLI (`gh`) or `actions/create-release` action

**Inputs**:
- Version number (tag: `v{version}`)
- Release title: "Bootstrap v{version}"
- Release notes (template)
- Archive files
- Manifest file
- Checksums file

**Outputs**:
- GitHub release with all assets
- Release URL

**Release Notes Template**:
```markdown
Bootstrap archives for mobile code editor v{version}

## Architectures
- arm64-v8a (64-bit ARM) - Modern Android devices
- armeabi-v7a (32-bit ARM) - Older Android devices
- x86_64 (64-bit x86) - Emulators and tablets
- x86 (32-bit x86) - Older emulators

## Included Tools
- Bash, Git, Node.js, npm, Python 3
- Core utilities (ls, cat, grep, sed, awk, etc.)
- Development tools (make, gcc, pkg-config)

## Checksums
See checksums.txt for SHA-256 verification.

## Installation
These archives are automatically downloaded by the mobile editor app based on device architecture.
```

## Data Models

### Workflow Input

```yaml
version: string  # Format: X.Y.Z (semantic versioning)
```

### Architecture Mapping

```json
{
  "aarch64": "arm64-v8a",
  "arm": "armeabi-v7a",
  "x86_64": "x86_64",
  "i686": "x86"
}
```

### Checksum Data Structure

```json
{
  "arm64-v8a": {
    "checksum": "sha256:a1b2c3...",
    "size": 89128960
  },
  "armeabi-v7a": {
    "checksum": "sha256:b2c3d4...",
    "size": 83886080
  },
  "x86_64": {
    "checksum": "sha256:c3d4e5...",
    "size": 94371840
  },
  "x86": {
    "checksum": "sha256:d4e5f6...",
    "size": 89128960
  }
}
```

### Bootstrap Manifest Structure

```json
{
  "version": "1.0.0",
  "last_updated": "2025-11-11",
  "architectures": {
    "arm64-v8a": {
      "url": "https://github.com/{owner}/{repo}/releases/download/v{version}/bootstrap-arm64-v8a-{version}.tar.gz",
      "size": 89128960,
      "checksum": "sha256:a1b2c3d4...",
      "min_android_version": 21
    }
    // ... other architectures
  }
}
```

## Error Handling

### Workflow-Level Error Handling

1. **Version Validation**
   - Check version format matches semantic versioning
   - Fail fast if invalid format

2. **Download Failures**
   - Retry download up to 3 times with exponential backoff
   - Fail workflow if download still fails
   - Log clear error message with URL that failed

3. **Archive Creation Failures**
   - Check if bootstrap directory exists before packaging
   - Verify tar command succeeds
   - Fail workflow if any architecture fails

4. **Validation Failures**
   - Run validation for all archives
   - Report which specific checks failed
   - Fail workflow if any validation fails

5. **Checksum Generation Failures**
   - Verify archive file exists before checksumming
   - Fail workflow if checksum calculation fails

6. **Release Creation Failures**
   - Check if release tag already exists
   - Fail workflow if release creation fails
   - Provide clear error message

7. **Manifest Update Failures**
   - Validate JSON syntax after update
   - Fail workflow if manifest is invalid
   - Rollback changes if commit fails

### Script-Level Error Handling

All scripts will:
- Use `set -e` to exit on first error
- Use `set -u` to fail on undefined variables
- Use `set -o pipefail` to catch errors in pipes
- Provide descriptive error messages
- Return appropriate exit codes

### Retry Logic

For network operations (downloads, GitHub API calls):
```bash
retry_count=0
max_retries=3
until [ $retry_count -ge $max_retries ]; do
  command && break
  retry_count=$((retry_count+1))
  sleep $((retry_count * 2))  # Exponential backoff
done
```

## Testing Strategy

### Local Testing

Before committing workflow changes:

1. **Script Testing**
   - Test each script independently with sample data
   - Verify error handling with invalid inputs
   - Check output format matches expectations

2. **Dry Run**
   - Run scripts locally with actual Termux bootstraps
   - Verify archives are created correctly
   - Validate checksums match

3. **Manifest Validation**
   - Verify JSON syntax with `jq`
   - Check all required fields are present
   - Validate URL format

### Workflow Testing

1. **Test Workflow Execution**
   - Trigger workflow with test version (e.g., "0.0.1-test")
   - Monitor workflow logs for errors
   - Verify all steps complete successfully

2. **Release Verification**
   - Check release is created with correct tag
   - Verify all assets are uploaded
   - Download and extract archives to verify integrity

3. **Manifest Verification**
   - Download manifest from release
   - Verify all URLs are accessible
   - Verify checksums match downloaded files

### Validation Checklist

After workflow completes:
- [ ] GitHub release created with correct version tag
- [ ] All 4 architecture archives uploaded
- [ ] bootstrap-manifest.json uploaded to release
- [ ] checksums.txt uploaded to release
- [ ] Manifest committed and pushed to repository
- [ ] All URLs in manifest are accessible
- [ ] Checksums in manifest match actual files
- [ ] File sizes in manifest match actual files
- [ ] Release marked as "Latest"

## Implementation Notes

### GitHub Actions Permissions

The workflow requires:
```yaml
permissions:
  contents: write  # For creating releases and committing manifest
```

### Environment Variables

```yaml
env:
  GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}  # Automatically provided
  VERSION: ${{ inputs.version }}
  REPO_NAME: ${{ github.repository }}
```

### Termux Bootstrap Version

The workflow will use the latest Termux bootstrap release. To find the latest:
```bash
curl -s https://api.github.com/repos/termux/termux-packages/releases | \
  jq -r '[.[] | select(.tag_name | startswith("bootstrap-"))][0].tag_name'
```

### Directory Structure

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
├── BOOTSTRAP_ARCHIVE_CREATION.md
└── BOOTSTRAP_MANIFEST_README.md
```

### Workflow Artifacts

The workflow will produce:
- 4 bootstrap archives (tar.gz)
- 1 manifest file (JSON)
- 1 checksums file (txt)
- Workflow logs

### Repository Information

- **GitHub Repository**: https://github.com/dsaved/bafle.git
- **Release URL Pattern**: https://github.com/dsaved/bafle/releases/download/v{version}/{filename}

### Performance Considerations

- **Parallel Downloads**: Download all architectures in parallel to reduce time
- **Compression Level**: Use gzip level 9 for best compression (acceptable speed)
- **Caching**: Consider caching downloaded Termux bootstraps if version doesn't change
- **Estimated Runtime**: 5-10 minutes for complete workflow

## Security Considerations

1. **Checksum Verification**: Always verify checksums before publishing
2. **HTTPS Only**: All download URLs use HTTPS
3. **Token Permissions**: Limit GitHub token to minimum required permissions
4. **Input Validation**: Validate version input to prevent injection attacks
5. **Signed Commits**: Consider signing commits for manifest updates

## Future Enhancements

1. **Automated Triggers**: Trigger workflow when Termux releases new bootstrap
2. **Custom Package Selection**: Allow specifying which packages to include
3. **Multi-Version Support**: Maintain multiple bootstrap versions simultaneously
4. **Notification System**: Send notifications on successful/failed builds
5. **Build from Source**: Option to build packages from source instead of using pre-built
6. **Architecture Selection**: Allow building only specific architectures
7. **Rollback Mechanism**: Ability to rollback to previous version if issues found
