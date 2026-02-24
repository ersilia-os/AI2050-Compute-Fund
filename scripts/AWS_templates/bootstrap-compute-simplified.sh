#!/bin/bash
# Simple bootstrap for COMPUTE nodes
# Everything we need is already in /shared!

set -e
set -x

echo "=========================================="
echo "COMPUTE NODE Bootstrap (Simple)"
echo "Node: $(hostname)"
echo "Date: $(date)"
echo "=========================================="

# Wait for /shared to mount (can take a few seconds)
TIMEOUT=60
ELAPSED=0
while [ ! -d /shared/apptainer ] && [ $ELAPSED -lt $TIMEOUT ]; do
    echo "Waiting for /shared to mount... ($ELAPSED seconds)"
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

# Verify /shared mounted
if [ ! -d /shared ]; then
    echo "ERROR: /shared not mounted after $TIMEOUT seconds!"
    exit 1
fi

# Add shared tools to PATH
echo 'export PATH=/shared/python39/bin:/shared/apptainer/bin:$PATH' | sudo tee /etc/profile.d/cluster-env.sh
echo 'export APPTAINER_CACHEDIR=/tmp/apptainer-cache' | sudo tee -a /etc/profile.d/cluster-env.sh
echo 'export S3_BUCKET=ai2050-ersilia-cluster' | sudo tee -a /etc/profile.d/cluster-env.sh

export PATH=/shared/python39/bin:/shared/apptainer/bin:$PATH

# Verify tools
echo ""
echo "Verification:"
if [ -x /shared/apptainer/bin/apptainer ]; then
    echo "✓ Apptainer: $(/shared/apptainer/bin/apptainer --version)"
else
    echo "✗ Apptainer not found!"
    exit 1
fi

if [ -x /shared/python39/bin/python3.9 ]; then
    echo "✓ Python: $(/shared/python39/bin/python3.9 --version)"
else
    echo "✗ Python 3.9 not found!"
    exit 1
fi

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


echo "=========================================="
echo "Bootstrap Complete! ($(date))"
echo "=========================================="