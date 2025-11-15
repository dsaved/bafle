# GitHub Actions Workflow Quick Reference

## Triggering a Build

### Via GitHub UI
1. Go to **Actions** tab
2. Select **Build and Deploy Bootstrap** workflow
3. Click **Run workflow**
4. Fill in parameters:
   - **version**: `1.0.0` (required, semantic versioning)
   - **build_modes**: `static,linux-native` (optional, default: `static`)
   - **architectures**: `arm64-v8a,armeabi-v7a,x86_64,x86` (optional, default: all)
   - **run_tests**: `true` (optional, default: `true`)
5. Click **Run workflow**

### Via GitHub CLI
```bash
gh workflow run build-bootstrap.yml \
  -f version=1.0.0 \
  -f build_modes=static,linux-native \
  -f architectures=arm64-v8a,x86_64 \
  -f run_tests=true
```

## Workflow Steps

### Build Job (Matrix: mode × architecture)

| Step | Script | Purpose | Outputs |
|------|--------|---------|---------|
| 1 | Setup | Install build dependencies | Build environment ready |
| 2 | `config-validator.sh` | Validate configuration | Validated config |
| 3 | `download-sources.sh` | Download source packages | Sources in `.cache/` |
| 4 | `build-{mode}.sh` | Compile binaries | Binaries in `build/` |
| 5 | `assemble-bootstrap.sh` | Assemble bootstrap | Bootstrap directory |
| 6 | `test-proot-compatibility.sh` | Test PRoot compatibility | Test report JSON |
| 7 | `package-archives.sh` | Create archive | `.tar.xz` file |
| 8 | `generate-checksums.sh` | Generate checksums | Checksum files |
| 9 | Upload | Upload to artifacts | Artifacts stored |

### Deploy Job (After all builds complete)

| Step | Script | Purpose | Outputs |
|------|--------|---------|---------|
| 1 | Download | Download all artifacts | All files collected |
| 2 | `update-manifest.sh` | Update manifest | Updated manifest JSON |
| 3 | Commit | Push manifest changes | Committed to repo |
| 4 | Release | Create GitHub release | Published release |

## Script CLI Arguments

### config-validator.sh
```bash
./scripts/config-validator.sh <config-file>
```

### download-sources.sh
```bash
./scripts/download-sources.sh
# Uses build-config.json automatically
```

### build-static.sh
```bash
./scripts/build-static.sh --arch <arch> --version <version>
```

### build-linux-native.sh
```bash
./scripts/build-linux-native.sh --android-arch <arch> --version <version>
```

### assemble-bootstrap.sh
```bash
./scripts/assemble-bootstrap.sh \
  --mode <mode> \
  --arch <arch> \
  --version <version>
```

### test-proot-compatibility.sh
```bash
./scripts/test-proot-compatibility.sh \
  --mode <mode> \
  --arch <arch> \
  --version <version>
```

### package-archives.sh
```bash
./scripts/package-archives.sh \
  --version <version> \
  --mode <mode> \
  --arch <arch>
```

### generate-checksums.sh
```bash
./scripts/generate-checksums.sh \
  --version <version> \
  --mode <mode> \
  --arch <arch>
```

### update-manifest.sh
```bash
./scripts/update-manifest.sh \
  <version> \
  <repo-name> \
  <checksum-data-json> \
  <mode-arch> \
  <test-report-base-url>
```

## Environment Variables

The workflow sets these environment variables for all scripts:

```bash
VERSION="1.0.0"                    # Build version
BUILD_MODE="static"                # Build mode
TARGET_ARCH="arm64-v8a"           # Target architecture
RUN_TESTS="true"                  # Whether to run tests
GITHUB_TOKEN="${{ secrets.GITHUB_TOKEN }}"  # GitHub API token
REPO_NAME="${{ github.repository }}"        # Repository name
```

## Matrix Strategy

The workflow builds these combinations in parallel:

```
static × arm64-v8a
static × armeabi-v7a
static × x86_64
static × x86
linux-native × arm64-v8a
linux-native × armeabi-v7a
linux-native × x86_64
linux-native × x86
android-native × arm64-v8a
android-native × armeabi-v7a
android-native × x86_64
android-native × x86
```

Total: **12 parallel jobs** (3 modes × 4 architectures)

## Artifacts

Each build job produces:
```
bootstrap-{mode}-{arch}-{version}.tar.xz
checksums-{mode}-{arch}.txt
checksums-{mode}-{arch}.json
test-report-{mode}-{arch}.json
```

## Release Assets

The final release includes:
```
bootstrap-static-arm64-v8a-1.0.0.tar.xz
bootstrap-static-armeabi-v7a-1.0.0.tar.xz
bootstrap-static-x86_64-1.0.0.tar.xz
bootstrap-static-x86-1.0.0.tar.xz
bootstrap-linux-native-arm64-v8a-1.0.0.tar.xz
bootstrap-linux-native-armeabi-v7a-1.0.0.tar.xz
bootstrap-linux-native-x86_64-1.0.0.tar.xz
bootstrap-linux-native-x86-1.0.0.tar.xz
checksums-static-arm64-v8a.txt
checksums-static-armeabi-v7a.txt
... (all checksum files)
test-report-static-arm64-v8a.json
test-report-static-armeabi-v7a.json
... (all test reports)
bootstrap-manifest.json
```

## Download URLs

After release, assets are available at:

```
# Specific version
https://github.com/{owner}/{repo}/releases/download/v{version}/bootstrap-{mode}-{arch}-{version}.tar.xz

# Latest version
https://github.com/{owner}/{repo}/releases/latest/download/bootstrap-manifest.json
```

## Monitoring

### View Workflow Runs
```bash
gh run list --workflow=build-bootstrap.yml
```

### View Specific Run
```bash
gh run view <run-id>
```

### Download Artifacts
```bash
gh run download <run-id>
```

### View Releases
```bash
gh release list
```

## Troubleshooting

### Build Failed
1. Check workflow logs in GitHub Actions UI
2. Look for the specific step that failed
3. Check error messages and suggestions
4. Re-run failed jobs if transient issue

### Tests Failed
1. Download test report artifact
2. Review `test-report-{mode}-{arch}.json`
3. Check which specific tests failed
4. Verify PRoot compatibility

### Release Failed
1. Check if release tag already exists
2. Verify GITHUB_TOKEN permissions
3. Check if all artifacts were uploaded
4. Verify manifest JSON is valid

## Local Testing

Test the workflow locally before pushing:

```bash
# Test full workflow simulation
./test/test-full-workflow.sh

# Test specific build mode
./test/test-static-build-scripts.sh
./test/test-linux-native-scripts.sh

# Test PRoot compatibility
./test/test-proot-compatibility-system.sh
```

## Performance

Typical build times:
- **Single job**: 5-10 minutes
- **Full matrix (12 jobs)**: 10-15 minutes (parallel)
- **Deploy job**: 2-3 minutes

Total workflow time: **~15-20 minutes**

## Best Practices

1. **Version Numbers**: Use semantic versioning (X.Y.Z)
2. **Build Modes**: Start with `static` for maximum compatibility
3. **Testing**: Always run tests unless debugging
4. **Architectures**: Build all architectures for production releases
5. **Monitoring**: Check workflow logs for warnings
6. **Artifacts**: Download artifacts for local testing before release
