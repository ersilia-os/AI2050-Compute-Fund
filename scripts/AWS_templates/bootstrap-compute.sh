#!/bin/bash
# Bootstrap script for COMPUTE NODES (Private Subnet - NO INTERNET)
# Compute nodes use shared Apptainer from head node

set -e

echo "=========================================="
echo "COMPUTE NODE Bootstrap Script"
echo "Node: $(hostname)"
echo "Date: $(date)"
echo "No internet access - using shared resources"
echo "=========================================="

S3_BUCKET="${S3_BUCKET:-ai2050-ersilia-cluster}"

# ==========================================
# Method 1: Use Apptainer from /shared (PRIMARY)
# ==========================================
echo "Method 1: Checking for shared Apptainer..."

if [ -f /shared/apptainer/bin/apptainer ]; then
    echo "✓ Found Apptainer in /shared!"
    
    # Add to PATH
    echo 'export PATH=/shared/apptainer/bin:$PATH' >> /etc/profile.d/apptainer.sh
    export PATH=/shared/apptainer/bin:$PATH
    
    /shared/apptainer/bin/apptainer --version
    
    APPTAINER_INSTALLED=true
else
    echo "⚠ Apptainer not found in /shared (may not be mounted yet)"
    APPTAINER_INSTALLED=false
fi

# ==========================================
# Method 2: Install from S3 cache (BACKUP)
# ==========================================
if [ "$APPTAINER_INSTALLED" = false ]; then
    echo ""
    echo "Method 2: Installing Apptainer from S3 cache..."
    
    mkdir -p /tmp/install
    cd /tmp/install
    
    # Try to download from S3
    if aws s3 cp s3://$S3_BUCKET/packages/apptainer/ /tmp/install/ --recursive --region eu-north-1 2>/dev/null; then
        echo "✓ Downloaded Apptainer files from S3"
        
        # Install Go
        if [ -f go*.tar.gz ]; then
            echo "Installing Go..."
            tar -C /usr/local -xzf go*.tar.gz
            export PATH=$PATH:/usr/local/go/bin
            echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/go.sh
        fi
        
        # Install build dependencies (available in Amazon Linux repos - no internet needed)
        echo "Installing build dependencies..."
        yum install -y \
            gcc \
            gcc-c++ \
            make \
            libuuid-devel \
            openssl-devel \
            libseccomp-devel \
            squashfs-tools \
            cryptsetup
        
        # Build Apptainer
        if [ -f apptainer*.tar.gz ]; then
            echo "Building Apptainer..."
            tar -xzf apptainer*.tar.gz
            cd apptainer-*/
            ./mconfig --prefix=/usr/local
            make -C builddir
            make -C builddir install
            
            # Verify
            apptainer --version && echo "✓ Apptainer installed from S3"
            APPTAINER_INSTALLED=true
        fi
    else
        echo "⚠ Could not download from S3"
    fi
    
    # Cleanup
    cd /
    rm -rf /tmp/install
fi

# ==========================================
# Final Apptainer check
# ==========================================
if command -v apptainer &> /dev/null; then
    echo "✓ Apptainer available: $(apptainer --version)"
elif [ -f /shared/apptainer/bin/apptainer ]; then
    echo "✓ Apptainer available at: /shared/apptainer/bin/apptainer"
else
    echo "⚠ WARNING: Apptainer not found on this compute node"
    echo "   Jobs may fail if they require Apptainer"
fi

# ==========================================
# Install Python 3 (available in Amazon Linux repos)
# ==========================================
echo ""
echo "Installing Python 3..."
yum install -y python3 python3-pip

# ==========================================
# ersilia-apptainer from /shared (if available)
# ==========================================
echo ""
echo "Checking for ersilia-apptainer..."

# The head node installs this system-wide, so compute nodes should have access
# via shared Python environment or can import if packages are shared
if ! python3 -c "import ersilia_apptainer" 2>/dev/null; then
    echo "⚠ ersilia-apptainer not available"
    echo "   Jobs can still run using Apptainer directly with SIF files"
else
    echo "✓ ersilia-apptainer available"
fi

# ==========================================
# Setup environment
# ==========================================
cat >> /etc/profile.d/cluster-env.sh << 'EOF'
# Compute node environment
export SHARED_DIR=/shared
export SIF_DIR=/shared/sif-files
export S3_BUCKET=ai2050-ersilia-cluster
export PATH=/shared/apptainer/bin:$PATH

export APPTAINER_CACHEDIR=/tmp/apptainer-cache
mkdir -p $APPTAINER_CACHEDIR
EOF

chmod 644 /etc/profile.d/cluster-env.sh

# ==========================================
# Create local working directories
# ==========================================
mkdir -p /tmp/job-scratch
chmod 1777 /tmp/job-scratch

# ==========================================
# Verify setup
# ==========================================
echo ""
echo "=========================================="
echo "Compute Node Bootstrap Verification:"
echo "=========================================="
echo "Node: $(hostname)"
echo ""

# Python
if command -v python3 &> /dev/null; then
    echo "✓ Python: $(python3 --version)"
else
    echo "✗ Python not found"
fi

# Apptainer
if command -v apptainer &> /dev/null; then
    echo "✓ Apptainer: $(apptainer --version)"
elif [ -f /shared/apptainer/bin/apptainer ]; then
    echo "✓ Apptainer: $(/shared/apptainer/bin/apptainer --version) (in /shared)"
else
    echo "✗ Apptainer not found"
fi

# S3 access
echo ""
echo "Testing S3 access via Gateway Endpoint..."
if aws s3 ls s3://$S3_BUCKET/ --region eu-north-1 2>/dev/null | head -3; then
    echo "✓ S3 access working"
else
    echo "✗ S3 access failed"
fi

# Shared storage
echo ""
echo "Shared storage:"
if [ -d /shared ]; then
    echo "✓ /shared mounted"
    ls -la /shared/ 2>/dev/null | head -10
else
    echo "⚠ /shared not yet mounted (will mount later)"
fi

if [ -d /fsx ]; then
    echo "✓ /fsx mounted"
else
    echo "⚠ /fsx not yet mounted (will mount later)"
fi

echo ""
echo "=========================================="
echo "Compute node bootstrap completed!"
echo "=========================================="