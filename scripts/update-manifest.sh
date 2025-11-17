#!/usr/bin/env bash

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# Script to update bootstrap-manifest.json with new version, URLs, checksums, and sizes
# Supports multiple build modes (static, linux-native, android-native)
# Usage: ./update-manifest.sh <version> <repo_name> <checksums_json> [build_mode] [test_report_base_url]
#   version: Version number (e.g., 1.0.0)
#   repo_name: GitHub repository in format owner/repo (e.g., dsaved/bafle)
#   checksums_json: JSON string with checksum and size data for each architecture
#   build_mode: Build mode (static, linux-native, or android-native) - optional, defaults to static
#   test_report_base_url: Base URL for test reports - optional

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

VERSION="${1:-}"
REPO_NAME="${2:-}"
CHECKSUMS_JSON="${3:-}"
BUILD_MODE="${4:-static}"
TEST_REPORT_BASE_URL="${5:-}"
MANIFEST_FILE="bootstrap-manifest.json"

log_info "Starting manifest update process..."

# Validate inputs
if [[ -z "$VERSION" ]]; then
    log_error "Version number is required"
    log_error "Usage: $0 <version> <repo_name> <checksums_json> [build_mode] [test_report_base_url]"
    log_error "Example: $0 1.0.0 dsaved/bafle '{...}' static"
    exit 1
fi

if [[ -z "$REPO_NAME" ]]; then
    log_error "Repository name is required"
    log_error "Usage: $0 <version> <repo_name> <checksums_json> [build_mode] [test_report_base_url]"
    log_error "Example: $0 1.0.0 dsaved/bafle '{...}' static"
    exit 1
fi

if [[ -z "$CHECKSUMS_JSON" ]]; then
    log_error "Checksums JSON is required"
    log_error "Usage: $0 <version> <repo_name> <checksums_json> [build_mode] [test_report_base_url]"
    log_error "This should be the JSON output from generate-checksums.sh"
    exit 1
fi

# Validate build mode
case "$BUILD_MODE" in
    static|linux-native|android-native)
        log_info "Build mode: $BUILD_MODE"
        ;;
    *)
        log_error "Invalid build mode: $BUILD_MODE"
        log_error "Supported modes: static, linux-native, android-native"
        exit 1
        ;;
esac

# Validate version format
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_error "Invalid version format: $VERSION"
    log_error "Version must follow semantic versioning (X.Y.Z)"
    exit 1
fi

# Check if manifest file exists
if [[ ! -f "$MANIFEST_FILE" ]]; then
    log_error "Manifest file not found: $MANIFEST_FILE"
    log_error "Please ensure the manifest file exists in the current directory"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    log_error "jq is required but not installed"
    log_error "Please install jq to update the manifest"
    log_error "  Ubuntu/Debian: sudo apt-get install jq"
    log_error "  macOS: brew install jq"
    exit 1
fi

# Get current date in YYYY-MM-DD format
CURRENT_DATE=$(date +%Y-%m-%d)

log_info "Updating manifest with version $VERSION"
log_info "Repository: $REPO_NAME"
log_info "Build mode: $BUILD_MODE"
log_info "Date: $CURRENT_DATE"

# Determine PRoot compatibility based on build mode
PROOT_COMPATIBLE="true"
if [[ "$BUILD_MODE" == "android-native" ]]; then
    PROOT_COMPATIBLE="false"
    log_warn "Android-native mode is not PRoot compatible"
fi

# Determine additional metadata based on build mode
case "$BUILD_MODE" in
    static)
        LIBC="musl"
        LINKER=""
        ;;
    linux-native)
        LIBC=""
        LINKER="/lib/ld-linux-aarch64.so.1"
        ;;
    android-native)
        LIBC=""
        LINKER="/system/bin/linker64"
        ;;
esac

# Parse checksums JSON to validate it
log_info "Validating checksums JSON..."
if ! echo "$CHECKSUMS_JSON" | jq empty 2>/dev/null; then
    log_error "Invalid JSON provided for checksums"
    log_error "The checksums JSON must be valid JSON format"
    exit 1
fi

# Validate that checksums JSON contains at least one architecture
log_info "Checking architectures in checksums JSON..."
available_archs=()
all_archs=("arm64-v8a" "armeabi-v7a" "x86_64" "x86")

for arch in "${all_archs[@]}"; do
    if echo "$CHECKSUMS_JSON" | jq -e ".[\"$arch\"]" > /dev/null 2>&1; then
        available_archs+=("$arch")
        log_info "  ✓ Found: $arch"
    fi
done

if [ ${#available_archs[@]} -eq 0 ]; then
    log_error "No valid architectures found in checksums JSON"
    log_error "Expected at least one of: ${all_archs[*]}"
    exit 1
fi

log_info "Processing ${#available_archs[@]} architecture(s)"

# Create backup of original manifest
BACKUP_FILE="${MANIFEST_FILE}.backup"
if ! cp "$MANIFEST_FILE" "$BACKUP_FILE"; then
    log_error "Failed to create backup of manifest file"
    exit 1
fi
log_info "Created backup: $BACKUP_FILE"

# Create temporary file for updated manifest
TEMP_MANIFEST=$(mktemp)

# Determine file extension based on compression (default to xz for now)
FILE_EXTENSION="tar.xz"

# Build the jq command dynamically based on available metadata
log_info "Updating manifest fields..."

# Build jq filter for mode-specific metadata
MODE_METADATA=""
if [[ -n "$LIBC" ]]; then
    MODE_METADATA="$MODE_METADATA | .libc = \$libc"
fi
if [[ -n "$LINKER" ]]; then
    MODE_METADATA="$MODE_METADATA | .linker = \$linker"
fi

# Build test report URL if base URL is provided
TEST_REPORT_FILTER=""
if [[ -n "$TEST_REPORT_BASE_URL" ]]; then
    TEST_REPORT_FILTER='| .testReport = "\($testReportBase)/test-report-\($mode)-\(.key).json"'
fi

# Update manifest using jq with new schema supporting multiple build modes
# Temporarily disable exit on error to capture jq output
set +e
JQ_OUTPUT=$(jq --arg version "$VERSION" \
   --arg date "$CURRENT_DATE" \
   --arg repo "$REPO_NAME" \
   --arg mode "$BUILD_MODE" \
   --arg prootCompatible "$PROOT_COMPATIBLE" \
   --arg libc "$LIBC" \
   --arg linker "$LINKER" \
   --arg testReportBase "$TEST_REPORT_BASE_URL" \
   --arg extension "$FILE_EXTENSION" \
   --argjson checksums "$CHECKSUMS_JSON" '
  # Update version and date at root level
  .version = $version |
  .releaseDate = $date |
  
  # Initialize bootstraps object if it does not exist
  if .bootstraps == null then .bootstraps = {} else . end |
  
  # Initialize mode object if it does not exist
  if .bootstraps[$mode] == null then .bootstraps[$mode] = {} else . end |
  
  # Update each architecture within the build mode
  .bootstraps[$mode] |= (
    $checksums | to_entries | map(
      .key as $arch |
      .value as $data |
      {
        key: $arch,
        value: (
          {
            url: "https://github.com/\($repo)/releases/download/v\($version)/bootstrap-\($mode)-\($arch)-\($version).\($extension)",
            sha256: $data.checksum,
            size: $data.size,
            buildMode: $mode,
            prootCompatible: ($prootCompatible == "true")
          } |
          if $libc != "" then . + {libc: $libc} else . end |
          if $linker != "" then . + {linker: $linker} else . end |
          if $testReportBase != "" then . + {testReport: "\($testReportBase)/test-report-\($mode)-\($arch).json"} else . end
        )
      }
    ) | from_entries
  ) |
  
  # Maintain backward compatibility with old architectures field for android-native
  if $mode == "android-native" then
    .architectures = .bootstraps["android-native"]
  else . end
' "$MANIFEST_FILE" 2>&1)

JQ_EXIT_CODE=$?
set -e  # Re-enable exit on error

if [ $JQ_EXIT_CODE -ne 0 ]; then
    log_error "Failed to update manifest using jq (exit code: $JQ_EXIT_CODE)"
    log_error "JQ Error output:"
    echo "$JQ_OUTPUT"
    log_error "Checksums JSON:"
    echo "$CHECKSUMS_JSON" | jq . 2>&1 || echo "$CHECKSUMS_JSON"
    rm -f "$TEMP_MANIFEST"
    exit 1
fi

# Write output to temp file
echo "$JQ_OUTPUT" > "$TEMP_MANIFEST"

# Validate the updated JSON syntax
log_info "Validating updated manifest JSON syntax..."
if ! jq empty "$TEMP_MANIFEST" 2>/dev/null; then
    log_error "Generated manifest has invalid JSON syntax"
    log_error "Restoring original manifest from backup"
    rm -f "$TEMP_MANIFEST"
    exit 1
fi

# Replace original manifest with updated version
if ! mv "$TEMP_MANIFEST" "$MANIFEST_FILE"; then
    log_error "Failed to replace manifest file"
    log_error "Restoring original manifest from backup"
    mv "$BACKUP_FILE" "$MANIFEST_FILE"
    exit 1
fi

# Remove backup after successful update
rm -f "$BACKUP_FILE"

echo ""
log_info "Manifest updated successfully!"
echo ""
log_info "Updated fields:"
echo "  ✓ version: $VERSION"
echo "  ✓ releaseDate: $CURRENT_DATE"
echo "  ✓ buildMode: $BUILD_MODE"
echo "  ✓ prootCompatible: $PROOT_COMPATIBLE"
if [[ -n "$LIBC" ]]; then
    echo "  ✓ libc: $LIBC"
fi
if [[ -n "$LINKER" ]]; then
    echo "  ✓ linker: $LINKER"
fi
echo "  ✓ URLs for all architectures"
echo "  ✓ Checksums for all architectures"
echo "  ✓ Sizes for all architectures"
if [[ -n "$TEST_REPORT_BASE_URL" ]]; then
    echo "  ✓ Test report URLs"
fi
echo ""
log_info "Manifest validation: PASSED"
