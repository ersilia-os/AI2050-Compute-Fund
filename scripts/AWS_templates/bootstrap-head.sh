#!/bin/bash
# Bootstrap script for HEAD NODE
# Head node has internet access to download packages

set -e

echo "=========================================="
echo "HEAD NODE Bootstrap Script"
echo "Node: $(hostname)"
echo "Date: $(date)"
echo "=========================================="

# Update system
echo "Updating system packages..."
yum update -y

# ==========================================
# Install Python and pip
# ==========================================
echo "Installing Python 3 and pip..."
yum install -y python3 python3-pip git

# Upgrade pip
python3 -m pip install --upgrade pip

# ==========================================
# Install Apptainer - SHARED INSTALLATION
# ==========================================
echo "Installing Apptainer to shared location..."

# Install dependencies
yum install -y \
    wget \
    gcc \
    gcc-c++ \
    make \
    libuuid-devel \
    openssl-devel \
    libseccomp-devel \
    squashfs-tools \
    cryptsetup \
    rpm-build

# Install Go
cd /tmp
GO_VERSION="1.21.5"
echo "Downloading Go ${GO_VERSION}..."
wget -q https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

# Make Go available system-wide
echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/go.sh

# Verify Go
/usr/local/go/bin/go version

# Download and build Apptainer
echo "Downloading Apptainer..."
APPTAINER_VERSION="1.2.5"
wget -q https://github.com/apptainer/apptainer/releases/download/v${APPTAINER_VERSION}/apptainer-${APPTAINER_VERSION}.tar.gz
tar -xzf apptainer-${APPTAINER_VERSION}.tar.gz
cd apptainer-${APPTAINER_VERSION}

echo "Building Apptainer (this takes ~5-10 minutes)..."
# Install to /shared so compute nodes can access it
./mconfig --prefix=/shared/apptainer
make -C builddir
make -C builddir install

# Add Apptainer to system PATH
echo 'export PATH=/shared/apptainer/bin:$PATH' >> /etc/profile.d/apptainer.sh
export PATH=/shared/apptainer/bin:$PATH

# Verify Apptainer installation
/shared/apptainer/bin/apptainer --version

# ==========================================
# Upload Apptainer files to S3 for compute nodes
# ==========================================
echo "Uploading Apptainer installer files to S3..."
S3_BUCKET="${S3_BUCKET:-ai2050-ersilia-cluster}"

cd /tmp
# Upload Go
if [ -f go${GO_VERSION}.linux-amd64.tar.gz ]; then
    aws s3 cp go${GO_VERSION}.linux-amd64.tar.gz s3://$S3_BUCKET/packages/apptainer/ && \
        echo "✓ Uploaded Go to S3"
fi

# Upload Apptainer source
if [ -f apptainer-${APPTAINER_VERSION}.tar.gz ]; then
    aws s3 cp apptainer-${APPTAINER_VERSION}.tar.gz s3://$S3_BUCKET/packages/apptainer/ && \
        echo "✓ Uploaded Apptainer source to S3"
fi

# Verify S3 uploads
echo "Verifying S3 uploads..."
aws s3 ls s3://$S3_BUCKET/packages/apptainer/

# ==========================================
# Install ersilia-apptainer
# ==========================================
echo "Installing ersilia-apptainer..."

# Try from pip first
python3 -m pip install ersilia-apptainer || true

# If pip install failed, try GitHub
if ! python3 -c "import ersilia_apptainer" 2>/dev/null; then
    echo "Installing ersilia-apptainer from GitHub..."
    cd /tmp
    git clone https://github.com/ersilia-os/ersilia-apptainer.git
    cd ersilia-apptainer
    python3 -m pip install -e .
fi

# Verify installation
python3 -c "import ersilia_apptainer; print('✓ ersilia-apptainer installed')"

# ==========================================
# Install AWS CLI v2
# ==========================================
if ! command -v aws &> /dev/null; then
    echo "Installing AWS CLI v2..."
    cd /tmp
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    ./aws/install
    rm -rf aws awscliv2.zip
fi

aws --version

# ==========================================
# Create shared directories
# ==========================================
echo "Creating shared directory structure..."

mkdir -p /shared/sif-files
mkdir -p /shared/scripts
mkdir -p /shared/data
mkdir -p /shared/logs
mkdir -p /shared/output

chmod 755 /shared/sif-files
chmod 755 /shared/scripts
chmod 755 /shared/data
chmod 755 /shared/logs
chmod 755 /shared/output

# ==========================================
# Create helper scripts
# ==========================================

# Script 1: Download Ersilia model (S3 ONLY - no DockerHub)
cat > /shared/scripts/download-ersilia-model.sh << 'DOWNLOAD_SCRIPT'
#!/bin/bash
# Download Ersilia model SIF file from S3
# Usage: download-ersilia-model.sh <model_id>

MODEL_ID=$1
S3_BUCKET="${S3_BUCKET:-ai2050-ersilia-cluster}"
SIF_PATH="/shared/sif-files/${MODEL_ID}.sif"

if [ -z "$MODEL_ID" ]; then
    echo "Usage: $0 <model_id>"
    echo "Example: $0 eos2r5a"
    exit 1
fi

echo "=========================================="
echo "Ersilia Model: $MODEL_ID"
echo "=========================================="

# Check if already exists
if [ -f "$SIF_PATH" ]; then
    echo "✓ Model already exists: $SIF_PATH"
    echo "File size: $(du -h $SIF_PATH | cut -f1)"
    exit 0
fi

# Download from S3
echo "Downloading from S3..."

if aws s3 ls s3://$S3_BUCKET/sif-files/${MODEL_ID}.sif 2>/dev/null; then
    echo "✓ Found in S3! Downloading..."
    
    if aws s3 cp s3://$S3_BUCKET/sif-files/${MODEL_ID}.sif $SIF_PATH; then
        echo "✓ Downloaded from S3: $SIF_PATH"
        echo "File size: $(du -h $SIF_PATH | cut -f1)"
        ls -lh $SIF_PATH
        exit 0
    else
        echo "✗ Failed to download from S3"
        exit 1
    fi
else
    echo "✗ Model not found in S3: s3://$S3_BUCKET/sif-files/${MODEL_ID}.sif"
    echo ""
    echo "Available models in S3:"
    aws s3 ls s3://$S3_BUCKET/sif-files/ | grep "\.sif$" || echo "  (none found)"
    echo ""
    echo "Please upload ${MODEL_ID}.sif to S3 first:"
    echo "  aws s3 cp ${MODEL_ID}.sif s3://$S3_BUCKET/sif-files/"
    exit 1
fi
DOWNLOAD_SCRIPT

chmod +x /shared/scripts/download-ersilia-model.sh

# Script 2: Upload SIF to S3 (OPTIONAL - for backup/sharing only)
cat > /shared/scripts/upload-sif-to-s3.sh << 'UPLOAD_SCRIPT'
#!/bin/bash
# Upload SIF file(s) from cluster to S3
# 
# NOTE: Normal workflow is to upload SIF files directly from your local computer.
# This script is only needed for:
#   - Backing up models from cluster to S3
#   - Sharing models with team members
#   - Disaster recovery scenarios
#
# Usage: upload-sif-to-s3.sh <model_id|all>

MODEL_ID=$1
S3_BUCKET="${S3_BUCKET:-ai2050-ersilia-cluster}"

if [ -z "$MODEL_ID" ]; then
    echo "Usage: $0 <model_id|all>"
    echo "Example: $0 eos2r5a"
    echo "Example: $0 all"
    exit 1
fi

if [ "$MODEL_ID" == "all" ]; then
    echo "Uploading all SIF files to S3..."
    aws s3 sync /shared/sif-files/ s3://$S3_BUCKET/sif-files/ --exclude "*" --include "*.sif"
    echo "✓ Upload complete"
else
    SIF_FILE="/shared/sif-files/${MODEL_ID}.sif"
    if [ ! -f "$SIF_FILE" ]; then
        echo "✗ SIF file not found: $SIF_FILE"
        exit 1
    fi
    echo "Uploading ${MODEL_ID}.sif to S3..."
    aws s3 cp $SIF_FILE s3://$S3_BUCKET/sif-files/
    echo "✓ Uploaded: s3://$S3_BUCKET/sif-files/${MODEL_ID}.sif"
fi
UPLOAD_SCRIPT

chmod +x /shared/scripts/upload-sif-to-s3.sh

# Script 3: Sync SIF from S3
cat > /shared/scripts/sync-sif-from-s3.sh << 'SYNC_SCRIPT'
#!/bin/bash
S3_BUCKET="${S3_BUCKET:-ai2050-ersilia-cluster}"

echo "Syncing SIF files from S3..."
aws s3 sync s3://$S3_BUCKET/sif-files/ /shared/sif-files/ --exclude "*" --include "*.sif"
echo "✓ Sync complete!"
ls -lh /shared/sif-files/*.sif 2>/dev/null || echo "No SIF files found"
SYNC_SCRIPT

chmod +x /shared/scripts/sync-sif-from-s3.sh

# Script 4: Run Ersilia job (simple sbatch format)
cat > /shared/scripts/run-ersilia-job.sh << 'RUN_SCRIPT'
#!/bin/bash
#SBATCH --job-name=ersilia
#SBATCH --partition=cpu-queue
#SBATCH --nodes=1
#SBATCH --time=02:00:00
#SBATCH --output=/shared/logs/ersilia-%j.out
#SBATCH --error=/shared/logs/ersilia-%j.err

# Process a single chunk file with an Ersilia model
# Usage: sbatch run-ersilia-job.sh <model_id> <input_file> <output_file>
#
# Example:
#   sbatch run-ersilia-job.sh eos2r5a /fsx/input/library_001/chunk_0001.csv /fsx/output/library_001/eos2r5a/eos2r5a_results_0001.csv

MODEL_ID=$1
INPUT_FILE=$2
OUTPUT_FILE=$3

echo "=========================================="
echo "Ersilia Job"
echo "=========================================="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $(hostname)"
echo "Date: $(date)"
echo "Model: $MODEL_ID"
echo "Input: $INPUT_FILE"
echo "Output: $OUTPUT_FILE"
echo "=========================================="

# Verify SIF file exists
SIF_FILE="/shared/sif-files/${MODEL_ID}.sif"
if [ ! -f "$SIF_FILE" ]; then
    echo "ERROR: SIF file not found: $SIF_FILE"
    echo "Please download it first: /shared/scripts/download-ersilia-model.sh $MODEL_ID"
    exit 1
fi

# Verify input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "ERROR: Input file not found: $INPUT_FILE"
    exit 1
fi

# Create output directory
OUTPUT_DIR=$(dirname "$OUTPUT_FILE")
mkdir -p "$OUTPUT_DIR"

# Run ersilia-apptainer
echo "Starting ersilia-apptainer..."
echo "Processing $(wc -l < $INPUT_FILE) molecules..."

python3 -m ersilia_apptainer \
    --sif "$SIF_FILE" \
    --input "$INPUT_FILE" \
    --output "$OUTPUT_FILE"

# Check if output was created
if [ -f "$OUTPUT_FILE" ]; then
    echo "✓ Success! Output: $OUTPUT_FILE"
    echo "Output size: $(wc -l < $OUTPUT_FILE) lines"
    
    # Upload to S3 if S3_BUCKET is set (preserve directory structure)
    if [ -n "$S3_BUCKET" ]; then
        # Extract path relative to /fsx/output/
        RELATIVE_PATH=$(echo "$OUTPUT_FILE" | sed 's|^/fsx/output/||')
        S3_OUTPUT="s3://$S3_BUCKET/output/$RELATIVE_PATH"
        aws s3 cp "$OUTPUT_FILE" "$S3_OUTPUT"
        echo "✓ Uploaded to: $S3_OUTPUT"
    fi
else
    echo "✗ ERROR: Output file was not created"
    exit 1
fi

echo "=========================================="
echo "Job completed: $(date)"
echo "=========================================="
RUN_SCRIPT

chmod +x /shared/scripts/run-ersilia-job.sh

# Script 5: Submit parallel jobs for a library with proper folder structure
cat > /shared/scripts/submit-ersilia-batch.sh << 'BATCH_SCRIPT'
#!/bin/bash
# Submit Ersilia batch jobs for pre-chunked input files
# Usage: submit-ersilia-batch.sh <model_id> <library_name> [queue]
#
# Expected structure:
#   /fsx/input/<library_name>/chunk_0001.csv
#   /fsx/input/<library_name>/chunk_0002.csv
#   ...
#
# Output structure:
#   /fsx/output/<library_name>/<model_id>/<model_id>_results_0001.csv
#   /fsx/output/<library_name>/<model_id>/<model_id>_results_0002.csv
#   ...

MODEL_ID=$1
LIBRARY_NAME=$2
QUEUE=${3:-cpu-queue}

# Validation
if [ -z "$MODEL_ID" ] || [ -z "$LIBRARY_NAME" ]; then
    echo "Usage: $0 <model_id> <library_name> [queue]"
    echo ""
    echo "Arguments:"
    echo "  model_id      - Ersilia model ID (e.g., eos2r5a)"
    echo "  library_name  - Library folder name (e.g., library_001)"
    echo "  queue         - Optional: test-queue, cpu-queue (default), gpu-queue"
    echo ""
    echo "Expected input structure:"
    echo "  /fsx/input/<library_name>/chunk_0001.csv"
    echo "  /fsx/input/<library_name>/chunk_0002.csv"
    echo "  ..."
    echo ""
    echo "Output structure:"
    echo "  /fsx/output/<library_name>/<model_id>/<model_id>_results_0001.csv"
    echo "  /fsx/output/<library_name>/<model_id>/<model_id>_results_0002.csv"
    echo "  ..."
    echo ""
    echo "Example:"
    echo "  $0 eos2r5a library_001 cpu-queue"
    exit 1
fi

# Define paths
INPUT_DIR="/fsx/input/${LIBRARY_NAME}"
OUTPUT_DIR="/fsx/output/${LIBRARY_NAME}/${MODEL_ID}"

# Check if input directory exists
if [ ! -d "$INPUT_DIR" ]; then
    echo "ERROR: Input directory not found: $INPUT_DIR"
    echo ""
    echo "Please ensure your chunks are uploaded to:"
    echo "  /fsx/input/${LIBRARY_NAME}/chunk_XXXX.csv"
    exit 1
fi

# Check if model SIF exists
if [ ! -f "/shared/sif-files/${MODEL_ID}.sif" ]; then
    echo "ERROR: Model SIF not found: /shared/sif-files/${MODEL_ID}.sif"
    echo "Download it first: /shared/scripts/download-ersilia-model.sh $MODEL_ID"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Find all chunk files
CHUNK_FILES=($INPUT_DIR/chunk_*.csv)
NUM_CHUNKS=${#CHUNK_FILES[@]}

if [ $NUM_CHUNKS -eq 0 ]; then
    echo "ERROR: No chunk files found in $INPUT_DIR"
    echo "Expected files: chunk_0001.csv, chunk_0002.csv, ..."
    exit 1
fi

echo "=========================================="
echo "Ersilia Batch Job Submission"
echo "=========================================="
echo "Model: $MODEL_ID"
echo "Library: $LIBRARY_NAME"
echo "Input directory: $INPUT_DIR"
echo "Output directory: $OUTPUT_DIR"
echo "Number of chunks: $NUM_CHUNKS"
echo "Queue: $QUEUE"
echo ""

# Submit jobs
echo "Submitting jobs to Slurm..."
SUBMITTED=0
FAILED=0

for chunk_file in "${CHUNK_FILES[@]}"; do
    if [ -f "$chunk_file" ]; then
        # Extract chunk number from filename (e.g., chunk_0001.csv -> 0001)
        CHUNK_BASE=$(basename "$chunk_file" .csv)
        CHUNK_NUM=$(echo "$CHUNK_BASE" | grep -oP '\d+$')
        
        # Create output filename: eos2r5a_results_0001.csv
        OUTPUT_FILE="${OUTPUT_DIR}/${MODEL_ID}_results_${CHUNK_NUM}.csv"
        
        # Submit job (override partition from batch script argument)
        JOB_ID=$(sbatch \
            --partition="$QUEUE" \
            /shared/scripts/run-ersilia-job.sh \
            "$MODEL_ID" \
            "$chunk_file" \
            "$OUTPUT_FILE" \
            2>&1 | grep -oP 'Submitted batch job \K\d+')
        
        if [ -n "$JOB_ID" ]; then
            echo "  ✓ Submitted chunk_${CHUNK_NUM} (Job ID: $JOB_ID)"
            SUBMITTED=$((SUBMITTED + 1))
        else
            echo "  ✗ Failed to submit chunk_${CHUNK_NUM}"
            FAILED=$((FAILED + 1))
        fi
    fi
done

echo ""
echo "=========================================="
echo "Submission Summary"
echo "=========================================="
echo "Library: $LIBRARY_NAME"
echo "Model: $MODEL_ID"
echo "Total chunks: $NUM_CHUNKS"
echo "Jobs submitted: $SUBMITTED"
echo "Jobs failed: $FAILED"
echo ""
echo "Output directory: $OUTPUT_DIR"
echo ""
echo "Monitor jobs:"
echo "  squeue -u \$USER"
echo "  watch -n 5 'squeue -u \$USER'"
echo ""
echo "When complete, merge results:"
echo "  /shared/scripts/merge-results.sh $OUTPUT_DIR ${OUTPUT_DIR}/../${MODEL_ID}_final.csv"
echo ""
echo "Or upload individual results to S3:"
echo "  aws s3 sync $OUTPUT_DIR s3://\$S3_BUCKET/output/${LIBRARY_NAME}/${MODEL_ID}/"
echo "=========================================="

# Save job info
JOB_INFO_FILE="${OUTPUT_DIR}/job_info.txt"
cat > "$JOB_INFO_FILE" << EOF
Library: $LIBRARY_NAME
Model: $MODEL_ID
Input Directory: $INPUT_DIR
Output Directory: $OUTPUT_DIR
Number of Chunks: $NUM_CHUNKS
Queue: $QUEUE
Submitted: $(date)
Jobs Submitted: $SUBMITTED
Jobs Failed: $FAILED
EOF

echo "Job info saved: $JOB_INFO_FILE"
BATCH_SCRIPT

chmod +x /shared/scripts/submit-ersilia-batch.sh

# Script 6: Merge chunked results into single file
cat > /shared/scripts/merge-results.sh << 'MERGE_SCRIPT'
#!/bin/bash
# Merge all chunk results into a single output file
# Usage: merge-results.sh <results_directory> <output_file>
#
# Example:
#   merge-results.sh /fsx/output/library_001/eos2r5a /fsx/output/library_001/eos2r5a_final.csv

RESULTS_DIR=$1
OUTPUT_FILE=$2

if [ -z "$RESULTS_DIR" ] || [ -z "$OUTPUT_FILE" ]; then
    echo "Usage: $0 <results_directory> <output_file>"
    echo ""
    echo "Example:"
    echo "  $0 /fsx/output/library_001/eos2r5a /fsx/output/library_001/eos2r5a_final.csv"
    echo ""
    echo "This will merge all files matching:"
    echo "  <results_directory>/*_results_*.csv"
    exit 1
fi

if [ ! -d "$RESULTS_DIR" ]; then
    echo "ERROR: Results directory not found: $RESULTS_DIR"
    exit 1
fi

echo "=========================================="
echo "Merging Results"
echo "=========================================="
echo "Results directory: $RESULTS_DIR"
echo "Output file: $OUTPUT_FILE"
echo ""

# Find result files (pattern: *_results_*.csv)
RESULT_FILES=($RESULTS_DIR/*_results_*.csv)
NUM_FILES=${#RESULT_FILES[@]}

if [ $NUM_FILES -eq 0 ] || [ ! -f "${RESULT_FILES[0]}" ]; then
    echo "ERROR: No result files found in $RESULTS_DIR"
    echo "Expected pattern: *_results_*.csv"
    echo ""
    echo "Contents of directory:"
    ls -lh "$RESULTS_DIR"
    exit 1
fi

echo "Found $NUM_FILES result files"
echo ""

# Create output directory
OUTPUT_DIR=$(dirname "$OUTPUT_FILE")
mkdir -p "$OUTPUT_DIR"

# Get header from first file
FIRST_FILE="${RESULT_FILES[0]}"
head -n 1 "$FIRST_FILE" > "$OUTPUT_FILE"
echo "Using header from: $(basename $FIRST_FILE)"

# Sort files naturally (chunk_0001, chunk_0002, ...) and append
echo ""
echo "Merging files in order..."
MERGED=0

# Sort the files by chunk number
IFS=$'\n' SORTED_FILES=($(sort -t_ -k3 -n <<<"${RESULT_FILES[*]}"))
unset IFS

for result_file in "${SORTED_FILES[@]}"; do
    if [ -f "$result_file" ]; then
        tail -n +2 "$result_file" >> "$OUTPUT_FILE"
        MERGED=$((MERGED + 1))
        echo "  ✓ Merged: $(basename $result_file)"
    fi
done

# Count total lines
TOTAL_LINES=$(wc -l < "$OUTPUT_FILE")
TOTAL_RESULTS=$((TOTAL_LINES - 1))  # Exclude header

echo ""
echo "=========================================="
echo "Merge Complete!"
echo "=========================================="
echo "Files merged: $MERGED"
echo "Total results: $TOTAL_RESULTS"
echo "Output file: $OUTPUT_FILE"
echo "File size: $(du -h $OUTPUT_FILE | cut -f1)"
echo ""

# Upload to S3 if S3_BUCKET is set (preserve directory structure)
if [ -n "$S3_BUCKET" ]; then
    echo "Uploading to S3..."
    RELATIVE_PATH=$(echo "$OUTPUT_FILE" | sed 's|^/fsx/output/||')
    S3_PATH="s3://$S3_BUCKET/output/$RELATIVE_PATH"
    aws s3 cp "$OUTPUT_FILE" "$S3_PATH"
    echo "✓ Uploaded to: $S3_PATH"
fi

echo "=========================================="
MERGE_SCRIPT

chmod +x /shared/scripts/merge-results.sh

# Script 7: Test cluster
cat > /shared/scripts/test-cluster.sh << 'TEST_SCRIPT'
#!/bin/bash
echo "=========================================="
echo "Cluster Test Script"
echo "=========================================="

echo "Test 1: Slurm"
sinfo &> /dev/null && echo "✓ Slurm running" || echo "✗ Slurm failed"

echo "Test 2: Storage"
[ -d /shared ] && echo "✓ /shared exists" || echo "✗ /shared missing"
[ -d /fsx ] && echo "✓ /fsx exists" || echo "✗ /fsx missing"

echo "Test 3: Apptainer"
apptainer --version &> /dev/null && echo "✓ Apptainer: $(apptainer --version)" || echo "✗ Apptainer missing"

echo "Test 4: S3"
aws s3 ls &> /dev/null && echo "✓ S3 access working" || echo "✗ S3 failed"

echo "=========================================="
TEST_SCRIPT

chmod +x /shared/scripts/test-cluster.sh

# ==========================================
# Environment configuration
# ==========================================
cat >> /etc/profile.d/cluster-env.sh << 'EOF'
export SHARED_DIR=/shared
export SIF_DIR=/shared/sif-files
export CLUSTER_SCRIPTS=/shared/scripts
export CLUSTER_LOGS=/shared/logs
export S3_BUCKET=ai2050-ersilia-cluster
export PATH=/shared/apptainer/bin:$PATH

export APPTAINER_CACHEDIR=/tmp/apptainer-cache
mkdir -p $APPTAINER_CACHEDIR

alias list-models='ls -lh /shared/sif-files/'
alias download-model='/shared/scripts/download-ersilia-model.sh'
alias sync-models='/shared/scripts/sync-sif-from-s3.sh'
alias test-cluster='/shared/scripts/test-cluster.sh'
EOF

chmod 644 /etc/profile.d/cluster-env.sh

# ==========================================
# Create README
# ==========================================
cat > /shared/README.md << 'README'
# Ersilia ParallelCluster User Guide

## Directory Structure

```
/fsx/input/
└── library_001/              ← Your library name
    ├── chunk_0001.csv
    ├── chunk_0002.csv
    └── chunk_XXXX.csv

/fsx/output/
└── library_001/              ← Same library name
    └── eos2r5a/              ← Model ID
        ├── eos2r5a_results_0001.csv
        ├── eos2r5a_results_0002.csv
        └── eos2r5a_results_XXXX.csv
```

## Quick Start

1. **Test cluster:**
   ```bash
   /shared/scripts/test-cluster.sh
   ```

2. **Download SIF files from S3:**
   ```bash
   /shared/scripts/sync-sif-from-s3.sh
   ```

3. **Process a library:**
   ```bash
   # Submit all chunks for processing
   /shared/scripts/submit-ersilia-batch.sh eos2r5a library_001 cpu-queue
   
   # Monitor jobs
   watch -n 5 squeue -u $USER
   
   # When complete, merge results
   /shared/scripts/merge-results.sh \
     /fsx/output/library_001/eos2r5a \
     /fsx/output/library_001/eos2r5a_final.csv
   ```

## Workflow: Processing a Large Library

### Step 1: Prepare Input (on your local computer)

```bash
# Split your large file into chunks
# Each chunk should be 10K-50K molecules

# Upload chunks to S3 in library folder
aws s3 sync ./library_001_chunks/ s3://ai2050-ersilia-cluster/input/library_001/

# Verify upload
aws s3 ls s3://ai2050-ersilia-cluster/input/library_001/
```

### Step 2: SSH to Cluster

```bash
ssh -i ~/.ssh/ersilia-key.pem ec2-user@HEAD_NODE_IP
```

### Step 3: Download Model SIF Files

```bash
# Download all models from S3
sync-models

# Or download specific model
download-model eos2r5a
```

### Step 4: Submit Batch Jobs

```bash
# Process library_001 with eos2r5a model
submit-ersilia-batch.sh eos2r5a library_001 cpu-queue

# This submits one job per chunk file in /fsx/input/library_001/
```

### Step 5: Monitor Progress

```bash
# Watch queue
watch -n 5 'squeue -u $USER'

# Check completed jobs
sacct -u $USER --format=JobID,JobName,State,Elapsed

# View specific job log
cat /shared/logs/library_001_eos2r5a_0001_*.out
```

### Step 6: Merge Results

```bash
# After all jobs complete, merge all chunk results
merge-results.sh \
  /fsx/output/library_001/eos2r5a \
  /fsx/output/library_001/eos2r5a_final.csv

# Download final results
aws s3 cp /fsx/output/library_001/eos2r5a_final.csv ./
```

## Available Scripts

- `test-cluster.sh` - Validate cluster setup
- `sync-sif-from-s3.sh` - Download ALL SIF files from S3
- `download-ersilia-model.sh` - Download single SIF file from S3
- `submit-ersilia-batch.sh` - Submit parallel jobs for a library ⭐
- `run-ersilia-job.sh` - Process one chunk (called automatically)
- `merge-results.sh` - Merge chunked results into single file

## File Naming Conventions

**Input chunks:**
- Format: `chunk_0001.csv`, `chunk_0002.csv`, ...
- Location: `/fsx/input/<library_name>/`

**Output results:**
- Format: `<model_id>_results_0001.csv`, `<model_id>_results_0002.csv`, ...
- Location: `/fsx/output/<library_name>/<model_id>/`

**Final merged:**
- Format: `<model_id>_final.csv`
- Location: `/fsx/output/<library_name>/`

## Important: SIF Files Must Be in S3

All Ersilia model SIF files must be uploaded to S3 BEFORE use:

```bash
# From your local computer, upload SIF files:
aws s3 cp eos2r5a.sif s3://ai2050-ersilia-cluster/sif-files/
aws s3 cp eos3b5e.sif s3://ai2050-ersilia-cluster/sif-files/

# Then on cluster, download them:
/shared/scripts/sync-sif-from-s3.sh
```

The cluster does NOT build models from DockerHub.

## Queues

- **test-queue** - t3.medium ($0.012/hr) - Testing with small chunks
- **cpu-queue** - c6i.16xlarge ($0.52/hr) - Production parallel processing
- **gpu-queue** - g5.4xlarge ($0.43/hr) - GPU models

## Example: Multiple Libraries, Multiple Models

```bash
# Process library_001 with eos2r5a
submit-ersilia-batch.sh eos2r5a library_001 cpu-queue

# Process library_001 with eos3b5e (can run in parallel!)
submit-ersilia-batch.sh eos3b5e library_001 cpu-queue

# Process library_002 with eos2r5a
submit-ersilia-batch.sh eos2r5a library_002 cpu-queue

# Monitor all jobs
watch -n 5 'squeue -u $USER | head -20'
```

Result structure:
```
/fsx/output/
├── library_001/
│   ├── eos2r5a/
│   │   ├── eos2r5a_results_0001.csv
│   │   └── ...
│   ├── eos2r5a_final.csv
│   ├── eos3b5e/
│   │   ├── eos3b5e_results_0001.csv
│   │   └── ...
│   └── eos3b5e_final.csv
└── library_002/
    ├── eos2r5a/
    │   ├── eos2r5a_results_0001.csv
    │   └── ...
    └── eos2r5a_final.csv
```
README

chmod 644 /shared/README.md

# ==========================================
# Final verification
# ==========================================
echo "=========================================="
echo "Head Node Bootstrap Complete!"
echo "=========================================="
echo "Python: $(python3 --version)"
echo "Apptainer: $(/shared/apptainer/bin/apptainer --version)"
echo "Apptainer location: /shared/apptainer/bin/apptainer"
echo "AWS CLI: $(aws --version)"
python3 -c "import ersilia_apptainer; print('ersilia-apptainer: installed')"
echo ""
echo "S3 packages uploaded:"
aws s3 ls s3://$S3_BUCKET/packages/apptainer/
echo ""
echo "Helper scripts: /shared/scripts/"
echo "README: /shared/README.md"
echo "=========================================="