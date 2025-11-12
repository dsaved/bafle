# Implementation Plan

- [x] 1. Create scripts directory and bootstrap download script
  - Create `scripts/` directory in repository root
  - Implement `scripts/download-bootstraps.sh` to download Termux bootstrap packages for all architectures
  - Add architecture mapping (aarch64→arm64-v8a, arm→armeabi-v7a, x86_64→x86_64, i686→x86)
  - Include retry logic for network failures with exponential backoff
  - Add error handling and logging for download failures
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 8.3_

- [x] 2. Create archive packaging script
  - Implement `scripts/package-archives.sh` to create tar.gz archives from bootstrap directories
  - Set correct permissions on usr/bin and usr/libexec directories
  - Create archives with owner/group set to 0 and numeric owner IDs
  - Use gzip compression level 9 for optimal compression
  - Generate archives named `bootstrap-{arch}-{version}.tar.gz`
  - _Requirements: 1.5, 8.3_

- [x] 3. Create archive validation script
  - Implement `scripts/validate-archives.sh` to verify archive integrity
  - Check that archives can be extracted without errors
  - Verify usr/bin directory exists in extracted content
  - Validate presence of critical binaries (bash, git, node/nodejs, python3/python)
  - Check that binaries have executable permissions
  - Return appropriate exit codes and error messages for failures
  - _Requirements: 6.1, 6.2, 6.3, 6.4, 8.2_

- [x] 4. Create checksum generation script
  - Implement `scripts/generate-checksums.sh` to calculate SHA-256 checksums
  - Calculate checksum for each architecture archive
  - Get exact file size in bytes for each archive
  - Generate `checksums.txt` file with format: `{checksum}  {filename}`
  - Output JSON data structure with checksum and size for each architecture
  - Format checksums as "sha256:{hash}" for manifest
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 8.4_

- [x] 5. Create manifest update script
  - Implement `scripts/update-manifest.sh` to update bootstrap-manifest.json
  - Read current manifest file
  - Update version field with new version number
  - Update last_updated field with current date in YYYY-MM-DD format
  - Update URL for each architecture using pattern: https://github.com/dsaved/bafle/releases/download/v{version}/bootstrap-{arch}-{version}.tar.gz
  - Update checksum and size for each architecture from JSON input
  - Validate JSON syntax after update using jq
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

- [x] 6. Create GitHub Actions workflow file
  - Create `.github/workflows/build-bootstrap.yml` workflow file
  - Configure workflow_dispatch trigger with version input parameter
  - Set up ubuntu-latest runner with contents:write permissions
  - Add checkout step to clone repository
  - Add step to make all scripts executable
  - Set environment variables (VERSION, GITHUB_TOKEN, REPO_NAME)
  - _Requirements: 5.1, 5.2, 5.4_

- [x] 7. Add workflow steps for bootstrap download and packaging
  - Add workflow step to execute download-bootstraps.sh script
  - Add workflow step to execute package-archives.sh script
  - Add workflow step to execute validate-archives.sh script
  - Configure steps to fail workflow if any script returns non-zero exit code
  - Add logging output for each step showing progress
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 6.5, 8.1_

- [x] 8. Add workflow steps for checksum generation and manifest update
  - Add workflow step to execute generate-checksums.sh script
  - Capture JSON output from checksum script for use in manifest update
  - Add workflow step to execute update-manifest.sh script with checksum data
  - Add workflow step to validate updated manifest JSON syntax
  - _Requirements: 3.1, 3.2, 3.3, 3.5, 4.1, 4.2, 4.3, 4.4, 4.5, 8.4_

- [x] 9. Add workflow step to create GitHub release
  - Install GitHub CLI (gh) if not available
  - Create release with tag v{version} and title "Bootstrap v{version}"
  - Generate release notes describing architectures and included tools
  - Upload all four bootstrap archives as release assets
  - Upload checksums.txt file as release asset
  - Mark release as latest release
  - Capture and log release URL
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 7.1, 7.2, 7.4, 8.5_

- [x] 10. Add workflow steps to commit and push manifest changes
  - Configure git user name and email for commits
  - Add bootstrap-manifest.json to git staging
  - Commit changes with message "Update bootstrap manifest to v{version}"
  - Push commit to main branch
  - Add error handling for commit/push failures
  - _Requirements: 4.6_

- [x] 11. Add workflow step to upload manifest to release
  - Upload updated bootstrap-manifest.json to the GitHub release
  - Verify manifest URL is accessible after upload
  - Add error handling if upload fails
  - _Requirements: 7.1, 7.2, 7.3_

- [x] 12. Add version validation to workflow
  - Add workflow step to validate version input format
  - Check version matches semantic versioning pattern (X.Y.Z)
  - Fail workflow with clear error message if version format is invalid
  - Log the validated version number
  - _Requirements: 5.3, 5.5, 8.2_

- [x] 13. Add comprehensive error handling and logging
  - Add set -e, set -u, set -o pipefail to all bash scripts
  - Add descriptive error messages for each failure scenario
  - Add progress logging for each major operation
  - Add workflow summary output with created assets and release URL
  - Ensure all error messages indicate what failed and why
  - _Requirements: 2.5, 3.5, 6.4, 8.1, 8.2, 8.3, 8.4, 8.5_

- [ ] 14. Create workflow testing and validation documentation
  - Document how to test scripts locally before committing
  - Create checklist for verifying workflow execution
  - Document how to verify release assets and manifest
  - Add troubleshooting guide for common workflow failures
  - _Requirements: 8.1, 8.2, 8.5_
