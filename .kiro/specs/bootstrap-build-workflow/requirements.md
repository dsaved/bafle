# Requirements Document

## Introduction

This document defines the requirements for an automated GitHub Actions workflow that builds bootstrap archives for a mobile code editor application, creates GitHub releases, and maintains an up-to-date bootstrap manifest file. The workflow automates the entire bootstrap build and deployment pipeline, eliminating manual steps and ensuring consistency across releases.

## Glossary

- **Bootstrap Archive**: A tar.gz file containing a complete Linux development environment (bash, git, Node.js, Python, etc.) for a specific Android architecture
- **GitHub Actions Workflow**: An automated CI/CD pipeline that runs on GitHub's infrastructure
- **Bootstrap Manifest**: A JSON file (bootstrap-manifest.json) containing metadata about available bootstrap archives including URLs, checksums, and file sizes
- **Architecture**: The CPU instruction set architecture (arm64-v8a, armeabi-v7a, x86_64, x86)
- **Checksum**: A SHA-256 hash used to verify file integrity
- **GitHub Release**: A versioned distribution point on GitHub containing downloadable assets
- **Termux**: An Android terminal emulator that provides the base packages for the bootstrap environment
- **Build System**: The automated process that compiles and packages bootstrap archives

## Requirements

### Requirement 1

**User Story:** As a release manager, I want an automated workflow that builds bootstrap archives for all supported architectures, so that I can create consistent releases without manual intervention

#### Acceptance Criteria

1. WHEN the workflow is triggered, THE Build System SHALL download or build bootstrap packages for arm64-v8a architecture
2. WHEN the workflow is triggered, THE Build System SHALL download or build bootstrap packages for armeabi-v7a architecture
3. WHEN the workflow is triggered, THE Build System SHALL download or build bootstrap packages for x86_64 architecture
4. WHEN the workflow is triggered, THE Build System SHALL download or build bootstrap packages for x86 architecture
5. WHEN building each architecture, THE Build System SHALL create a tar.gz archive containing the usr/ directory structure with correct permissions

### Requirement 2

**User Story:** As a release manager, I want the workflow to automatically create GitHub releases with all bootstrap archives, so that the archives are publicly accessible for download

#### Acceptance Criteria

1. WHEN all bootstrap archives are built successfully, THE GitHub Actions Workflow SHALL create a new GitHub release with a version tag
2. WHEN creating the release, THE GitHub Actions Workflow SHALL upload all four architecture-specific bootstrap archives as release assets
3. WHEN creating the release, THE GitHub Actions Workflow SHALL include release notes describing the bootstrap contents
4. WHEN the release is created, THE GitHub Actions Workflow SHALL make the release publicly accessible
5. IF any archive build fails, THEN THE GitHub Actions Workflow SHALL fail the workflow and prevent release creation

### Requirement 3

**User Story:** As a release manager, I want the workflow to automatically calculate checksums and file sizes for all archives, so that the manifest contains accurate verification data

#### Acceptance Criteria

1. WHEN each bootstrap archive is created, THE Build System SHALL calculate the SHA-256 checksum for the archive
2. WHEN each bootstrap archive is created, THE Build System SHALL determine the exact file size in bytes
3. WHEN calculating checksums, THE Build System SHALL format checksums as "sha256:" followed by 64 hexadecimal characters
4. WHEN all archives are processed, THE Build System SHALL store checksums and sizes for manifest generation
5. IF checksum calculation fails for any archive, THEN THE GitHub Actions Workflow SHALL fail the workflow

### Requirement 4

**User Story:** As a release manager, I want the workflow to automatically update the bootstrap-manifest.json file with correct URLs, checksums, and sizes, so that the mobile app can download the correct bootstrap version

#### Acceptance Criteria

1. WHEN the GitHub release is created, THE GitHub Actions Workflow SHALL update the bootstrap-manifest.json file with the new version number
2. WHEN updating the manifest, THE GitHub Actions Workflow SHALL set the correct GitHub release download URLs for each architecture
3. WHEN updating the manifest, THE GitHub Actions Workflow SHALL include the calculated SHA-256 checksums for each architecture
4. WHEN updating the manifest, THE GitHub Actions Workflow SHALL include the exact file sizes in bytes for each architecture
5. WHEN updating the manifest, THE GitHub Actions Workflow SHALL set the last_updated field to the current date in YYYY-MM-DD format
6. WHEN the manifest is updated, THE GitHub Actions Workflow SHALL commit and push the changes to the repository

### Requirement 5

**User Story:** As a release manager, I want to trigger the workflow manually with a version number input, so that I can control when releases are created and what version they use

#### Acceptance Criteria

1. THE GitHub Actions Workflow SHALL support manual triggering via workflow_dispatch event
2. WHEN manually triggering the workflow, THE GitHub Actions Workflow SHALL accept a version number input parameter
3. WHEN a version number is provided, THE GitHub Actions Workflow SHALL validate the version follows semantic versioning format (X.Y.Z)
4. WHEN the workflow is triggered, THE GitHub Actions Workflow SHALL use the provided version number for the release tag and manifest
5. IF no version number is provided, THEN THE GitHub Actions Workflow SHALL fail with a clear error message

### Requirement 6

**User Story:** As a developer, I want the workflow to validate all archives before creating the release, so that broken or incomplete archives are not published

#### Acceptance Criteria

1. WHEN each archive is created, THE Build System SHALL verify the archive can be extracted successfully
2. WHEN validating an archive, THE Build System SHALL verify the usr/bin directory exists and contains expected executables
3. WHEN validating an archive, THE Build System SHALL verify critical binaries (bash, git, node, python3) are present
4. IF any validation check fails, THEN THE GitHub Actions Workflow SHALL fail the workflow and report which validation failed
5. WHEN all validations pass, THE GitHub Actions Workflow SHALL proceed to release creation

### Requirement 7

**User Story:** As a release manager, I want the workflow to upload the updated manifest to the GitHub release, so that the mobile app can fetch the manifest from a consistent location

#### Acceptance Criteria

1. WHEN the manifest file is updated, THE GitHub Actions Workflow SHALL upload the bootstrap-manifest.json file as a release asset
2. WHEN uploading the manifest, THE GitHub Actions Workflow SHALL ensure the manifest is accessible at the release download URL
3. WHEN the release is complete, THE GitHub Actions Workflow SHALL verify the manifest URL is accessible
4. THE GitHub Actions Workflow SHALL upload a checksums.txt file containing all archive checksums to the release
5. WHEN all assets are uploaded, THE GitHub Actions Workflow SHALL mark the release as the latest release

### Requirement 8

**User Story:** As a developer, I want clear workflow logs and error messages, so that I can quickly diagnose and fix any build failures

#### Acceptance Criteria

1. WHEN each workflow step executes, THE GitHub Actions Workflow SHALL output clear progress messages indicating the current operation
2. WHEN an error occurs, THE GitHub Actions Workflow SHALL output a descriptive error message indicating what failed and why
3. WHEN building each architecture, THE GitHub Actions Workflow SHALL log which architecture is being processed
4. WHEN generating checksums, THE GitHub Actions Workflow SHALL log the checksum value for each archive
5. WHEN the workflow completes successfully, THE GitHub Actions Workflow SHALL output a summary of created assets and the release URL
