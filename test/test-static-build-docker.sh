#!/usr/bin/env bash

# test-static-build-docker.sh - Test static build in Docker (Linux environment)
# This simulates the GitHub Actions environment

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "================================================"
echo "Static Build Test (Docker/Linux)"
echo "================================================"
echo ""

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed"
    echo ""
    echo "Static builds require a Linux environment."
    echo "Please install Docker to test locally:"
    echo "  - macOS: brew install --cask docker"
    echo "  - Linux: apt-get install docker.io"
    echo ""
    echo "Or run this test in GitHub Actions which has Linux runners."
    exit 1
fi

echo "✅ Docker is available"
echo ""

# Create Dockerfile for build environment
cat > "$PROJECT_ROOT/Dockerfile.test" << 'EOF'
FROM ubuntu:22.04

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    gcc \
    g++ \
    make \
    wget \
    curl \
    jq \
    xz-utils \
    bzip2 \
    file \
    musl-tools \
    musl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# Copy project files
COPY . .

# Make scripts executable
RUN chmod +x scripts/*.sh

CMD ["/bin/bash"]
EOF

echo "Building Docker image..."
if ! docker build -t bootstrap-builder-test -f "$PROJECT_ROOT/Dockerfile.test" "$PROJECT_ROOT"; then
    echo "❌ Failed to build Docker image"
    exit 1
fi

echo "✅ Docker image built"
echo ""

echo "Running static build test in Docker..."
echo ""

# Run the build in Docker
docker run --rm \
    -v "$PROJECT_ROOT:/workspace" \
    -w /workspace \
    bootstrap-builder-test \
    bash -c "
        set -e
        echo '=== Testing Static Build ==='
        echo ''
        
        # Test 1: Config validation
        echo 'Step 1: Config Validation'
        ./scripts/config-validator.sh build-config.json
        echo '✅ Config validation passed'
        echo ''
        
        # Test 2: Download sources
        echo 'Step 2: Download Sources'
        ./scripts/download-sources.sh
        echo '✅ Sources downloaded'
        echo ''
        
        # Test 3: Build static (x86_64 only - native)
        echo 'Step 3: Build Static (x86_64)'
        ./scripts/build-static.sh --arch x86_64 --version 0.0.1-test
        echo '✅ Build completed'
        echo ''
        
        # Test 4: Check binaries exist
        echo 'Step 4: Verify Binaries'
        if [ -f build/static-x86_64/bin/bash ]; then
            echo '✅ bash binary exists'
            file build/static-x86_64/bin/bash
        else
            echo '❌ bash binary not found'
            exit 1
        fi
        
        if [ -f build/static-x86_64/bin/busybox ]; then
            echo '✅ busybox binary exists'
            file build/static-x86_64/bin/busybox
        else
            echo '❌ busybox binary not found'
            exit 1
        fi
        
        echo ''
        echo '=== All Tests Passed ==='
    "

exit_code=$?

# Cleanup
rm -f "$PROJECT_ROOT/Dockerfile.test"

if [ $exit_code -eq 0 ]; then
    echo ""
    echo "================================================"
    echo "✅ STATIC BUILD TEST PASSED"
    echo "================================================"
else
    echo ""
    echo "================================================"
    echo "❌ STATIC BUILD TEST FAILED"
    echo "================================================"
fi

exit $exit_code
