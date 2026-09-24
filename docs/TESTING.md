# Testing Guide

## Overview

This project includes comprehensive testing to ensure the GitHub Actions workflow and all build scripts function correctly.

## Test Scripts

### 1. Workflow Structure Test (Fast)

**Script**: `test/test-workflow-structure.sh`

**Purpose**: Validates the workflow structure without running actual builds

**What it tests**:
- All required scripts exist and are executable
- Scripts accept correct CLI arguments
- Workflow file has proper matrix strategy
- Workflow has all required steps
- Documentation exists

**Usage**:
```bash
./test/test-workflow-structure.sh
```

**Runtime**: ~1 second

**When to use**: Quick validation after making changes to scripts or workflow

### 2. Full Workflow Simulation (Slow)

**Script**: `test/test-github-workflow-simulation.sh`

**Purpose**: Simulates the complete GitHub Actions workflow end-to-end

**What it tests**:
- Environment setup
- Configuration validation
- Source package download
- Binary compilation
- Bootstrap assembly
- PRoot compatibility testing
- Archive packaging
- Checksum generation
- Archive integrity verification

**Usage**:
```bash
# Default (static mode, arm64-v8a)
./test/test-github-workflow-simulation.sh

# Custom configuration
./test/test-github-workflow-simulation.sh \
  --version 1.0.0 \
  --mode static \
  --arch arm64-v8a

# Skip tests
./test/test-github-workflow-simulation.sh --no-tests
```

**Runtime**: ~10-20 minutes (depends on network and compilation)

**When to use**: Before pushing changes that affect the build pipeline

**Requirements**:
- Linux environment (or macOS with cross-compilation tools)
- Build dependencies: gcc, make, curl, jq, tar, xz
- Internet connection (for downloading sources)

## Test Matrix

The workflow supports building these combinations:

| Mode | Architecture | PRoot Compatible |
|------|--------------|------------------|
| static | arm64-v8a | ✅ Yes |
| static | armeabi-v7a | ✅ Yes |
| static | x86_64 | ✅ Yes |
| static | x86 | ✅ Yes |
| linux-native | arm64-v8a | ✅ Yes |
| linux-native | armeabi-v7a | ✅ Yes |
| linux-native | x86_64 | ✅ Yes |
| linux-native | x86 | ✅ Yes |
| android-native | arm64-v8a | ❌ No |
| android-native | armeabi-v7a | ❌ No |
| android-native | x86_64 | ❌ No |
| android-native | x86 | ❌ No |

## Testing Workflow

### Before Committing

1. Run structure test:
```bash
./test/test-workflow-structure.sh
```

2. If structure test passes, optionally run full simulation:
```bash
./test/test-github-workflow-simulation.sh --no-tests
```

### Before Releasing

1. Run full workflow simulation with tests:
```bash
./test/test-github-workflow-simulation.sh
```

2. Verify all steps pass
3. Check generated artifacts in `bootstrap-archives/`

### In CI/CD

The GitHub Actions workflow automatically:
1. Validates configuration
2. Downloads sources
3. Compiles binaries
4. Assembles bootstraps
5. Tests PRoot compatibility
6. Packages archives
7. Generates checksums
8. Creates release

## Test Artifacts

After running the full simulation, check these artifacts:

```
build/
├── static/
│   └── bootstrap-static-arm64-v8a-0.0.1/
│       └── usr/
│           ├── bin/
│           ├── lib/
│           └── etc/
bootstrap-archives/
├── bootstrap-static-arm64-v8a-0.0.1.tar.xz
├── checksums-static-arm64-v8a.txt
└── checksums-static-arm64-v8a.json
test-results/
└── test-report-static-arm64-v8a.json
```

## Troubleshooting

### Structure Test Fails

**Issue**: Script not found or not executable

**Solution**:
```bash
chmod +x scripts/*.sh
```

**Issue**: Missing CLI arguments

**Solution**: Check script accepts required arguments:
```bash
./scripts/script-name.sh --help
```

### Full Simulation Fails

**Issue**: Missing build dependencies

**Solution**:
```bash
# macOS
brew install gcc make curl jq xz

# Ubuntu/Debian
sudo apt-get install build-essential curl jq xz-utils
```

**Issue**: Source download fails

**Solution**: Check internet connection and retry

**Issue**: Compilation fails

**Solution**: 
- Ensure you're on Linux or have cross-compilation tools
- Check build logs in `build/` directory
- Try with `--no-tests` flag first

**Issue**: PRoot tests fail

**Solution**:
- Check test report in `test-results/`
- Verify binaries are statically linked: `ldd build/static/*/usr/bin/bash`
- Ensure PRoot binary downloaded correctly

## Continuous Integration

The workflow runs automatically on:
- Manual workflow dispatch
- Push to main branch (optional)
- Pull requests (optional)

Monitor builds at:
```
https://github.com/{owner}/{repo}/actions
```

## Performance Benchmarks

Typical test times:

| Test | Duration | Purpose |
|------|----------|---------|
| Structure Test | ~1s | Quick validation |
| Full Simulation (no tests) | ~5-10min | Build validation |
| Full Simulation (with tests) | ~10-20min | Complete validation |
| GitHub Actions (matrix) | ~15-20min | Production builds |

## Best Practices

1. **Always run structure test** before committing
2. **Run full simulation** before major changes
3. **Check test reports** when PRoot tests fail
4. **Verify checksums** after packaging
5. **Test on Linux** for accurate results
6. **Use --no-tests** for faster iteration during development

## Adding New Tests

To add a new test:

1. Create test script in `test/` directory
2. Follow naming convention: `test-{feature}.sh`
3. Make it executable: `chmod +x test/test-{feature}.sh`
4. Add to this documentation
5. Consider adding to CI workflow

## Test Coverage

Current test coverage:

- ✅ Script existence and executability
- ✅ CLI argument validation
- ✅ Workflow structure
- ✅ Configuration validation
- ✅ Source download and verification
- ✅ Binary compilation
- ✅ Bootstrap assembly
- ✅ PRoot compatibility
- ✅ Archive packaging
- ✅ Checksum generation
- ✅ Archive integrity

Future test coverage:

- ⏳ Unit tests for individual functions
- ⏳ Integration tests for script interactions
- ⏳ Performance regression tests
- ⏳ Security vulnerability scanning
