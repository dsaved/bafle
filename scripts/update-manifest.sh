#!/usr/bin/env bash

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# Script to update bootstrap-manifest.json with new version, URLs, checksums, and sizes
# Usage: ./update-manifest.sh <version> <repo_name> <checksums_json>
#   version: Version number (e.g., 1.0.0)
#   repo_name: GitHub repository in format owner/repo (e.g., dsaved/bafle)
#   checksums_json: JSON string with checksum and size data for each architecture

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
MANIFEST_FILE="bootstrap-manifest.json"

log_info "Starting manifest update process..."

# Validate inputs
if [[ -z "$VERSION" ]]; then
    log_error "Version number is required"
    log_error "Usage: $0 <version> <repo_name> <checksums_json>"
    log_error "Example: $0 1.0.0 dsaved/bafle '{...}'"
    exit 1
fi

if [[ -z "$REPO_NAME" ]]; then
    log_error "Repository name is required"
    log_error "Usage: $0 <version> <repo_name> <checksums_json>"
    log_error "Example: $0 1.0.0 dsaved/bafle '{...}'"
    exit 1
fi

if [[ -z "$CHECKSUMS_JSON" ]]; then
    log_error "Checksums JSON is required"
    log_error "Usage: $0 <version> <repo_name> <checksums_json>"
    log_error "This should be the JSON output from generate-checksums.sh"
    exit 1
fi

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
log_info "Date: $CURRENT_DATE"

# Parse checksums JSON to validate it
log_info "Validating checksums JSON..."
if ! echo "$CHECKSUMS_JSON" | jq empty 2>/dev/null; then
    log_error "Invalid JSON provided for checksums"
    log_error "The checksums JSON must be valid JSON format"
    exit 1
fi

# Validate that checksums JSON contains all required architectures
log_info "Checking for required architectures in checksums..."
required_archs=("arm64-v8a" "armeabi-v7a" "x86_64" "x86")
for arch in "${required_archs[@]}"; do
    if ! echo "$CHECKSUMS_JSON" | jq -e ".[\"$arch\"]" > /dev/null 2>&1; then
        log_error "Missing architecture in checksums JSON: $arch"
        exit 1
    fi
    log_info "  ✓ Found: $arch"
done

# Create backup of original manifest
BACKUP_FILE="${MANIFEST_FILE}.backup"
if ! cp "$MANIFEST_FILE" "$BACKUP_FILE"; then
    log_error "Failed to create backup of manifest file"
    exit 1
fi
log_info "Created backup: $BACKUP_FILE"

# Create temporary file for updated manifest
TEMP_MANIFEST=$(mktemp)

# Update manifest using jq
log_info "Updating manifest fields..."
if ! jq --arg version "$VERSION" \
   --arg date "$CURRENT_DATE" \
   --arg repo "$REPO_NAME" \
   --argjson checksums "$CHECKSUMS_JSON" '
  .version = $version |
  .last_updated = $date |
  .architectures |= with_entries(
    .value.url = "https://github.com/\($repo)/releases/download/v\($version)/bootstrap-\(.key)-\($version).tar.gz" |
    .value.checksum = $checksums[.key].checksum |
    .value.size = $checksums[.key].size
  )
' "$MANIFEST_FILE" > "$TEMP_MANIFEST" 2>/dev/null; then
    log_error "Failed to update manifest using jq"
    log_error "This could be due to invalid JSON structure in the manifest"
    rm -f "$TEMP_MANIFEST"
    exit 1
fi

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
echo "  ✓ last_updated: $CURRENT_DATE"
echo "  ✓ URLs for all architectures"
echo "  ✓ Checksums for all architectures"
echo "  ✓ Sizes for all architectures"
echo ""
log_info "Manifest validation: PASSED"
