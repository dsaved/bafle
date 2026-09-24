# Workflow Fix Summary

## Problem
The GitHub Actions workflow was failing at the "Package archive" step for android-native builds with the error:
```
[ERROR] Input directory not found: build
[ERROR] Please ensure the build has completed successfully
```

## Root Cause
The workflow had a mismatch between where bootstraps were downloaded and where the packaging script expected them:

1. `download-bootstraps.sh` downloaded to `bootstrap-downloads/{arch}/`
2. `package-archives.sh` expected bootstraps in `build/bootstrap-{mode}-{arch}-{version}/`
3. The workflow skipped the assembly step for android-native mode, leaving no step to move/organize the downloaded bootstraps

## Solution

### 1. Added Organization Step
Added a new workflow step to move downloaded android-native bootstraps to the expected location:

```yaml
- name: Organize android-native bootstrap
  if: ${{ matrix.mode == 'android-native' }}
  run: |
    BOOTSTRAP_NAME="bootstrap-${BUILD_MODE}-${TARGET_ARCH}-${VERSION}"
    SOURCE_DIR="bootstrap-downloads/${TARGET_ARCH}"
    DEST_DIR="build/${BOOTSTRAP_NAME}"
    
    mkdir -p build
    mv "$SOURCE_DIR" "$DEST_DIR"
```

### 2. Updated Package Script
Enhanced `scripts/package-archives.sh` to handle both directory structures:
- **Standard structure**: `usr/bin/`, `usr/lib/`, etc. (from static/linux-native builds)
- **Flat structure**: `bin/`, `lib/`, etc. (from android-native downloads)

Key changes:
- Updated `validate_structure()` to accept both structures
- Updated `set_permissions()` to handle both structures
- Added detection logic to identify which structure is present

### 3. Fixed Assembly Script
Changed `scripts/assemble-bootstrap.sh` default output directory from `bootstrap-archives/` to `build/` for consistency.

### 4. Added Structure Validation
Added validation in the workflow to ensure no nested `usr/usr/` structure:

```yaml
# Check for incorrect nested usr/usr/ structure
if tar -tJf "$ARCHIVE_PATH" | grep -q "usr/usr/"; then
  echo "❌ CRITICAL ERROR: Archive contains nested usr/usr/ structure!"
  exit 1
fi
```

## Testing

### Created Test Scripts
1. **test/test-package-workflow.sh** - Fast test with mock bootstrap
   - Creates mock flat structure
   - Tests organize step
   - Tests package step
   - Validates archive structure (no usr/usr/)

2. **test/test-workflow-end-to-end.sh** - Full integration test
   - Downloads real Termux bootstraps
   - Tests complete workflow
   - Validates final archive

### Test Results
```bash
$ ./test/test-package-workflow.sh
[SUCCESS] All tests passed!
[INFO] The workflow is working correctly
```

Archive structure verified:
```
bootstrap-android-native-arm64-v8a-2.0.0/
├── bin/
│   ├── bash
│   ├── sh
│   ├── cat
│   └── ls
├── lib/
├── etc/
├── var/
├── tmp/
└── SYMLINKS.txt
```

✅ No nested `usr/usr/` structure
✅ Flat structure preserved correctly

## Workflow Steps (Updated)

For **android-native** mode:
1. Download bootstraps → `bootstrap-downloads/{arch}/`
2. Organize → Move to `build/bootstrap-{mode}-{arch}-{version}/`
3. Package → Create archive from `build/` directory
4. Validate → Check for correct structure (no usr/usr/)

For **static/linux-native** modes:
1. Download sources
2. Compile binaries
3. Assemble → Create `build/bootstrap-{mode}-{arch}-{version}/` with usr/ structure
4. Test PRoot compatibility
5. Package → Create archive from `build/` directory
6. Validate → Check for correct structure

## Files Modified
- `.github/workflows/build-bootstrap.yml` - Added organize step and validation
- `scripts/package-archives.sh` - Support for both directory structures
- `scripts/assemble-bootstrap.sh` - Fixed output directory
- `test/test-package-workflow.sh` - New fast test
- `test/test-workflow-end-to-end.sh` - Updated for flat structure

## Verification
The workflow now correctly:
1. ✅ Downloads android-native bootstraps
2. ✅ Organizes them to the expected location
3. ✅ Packages them without errors
4. ✅ Validates structure (no nested usr/usr/)
5. ✅ Creates valid archives ready for deployment
