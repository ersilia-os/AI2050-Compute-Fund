

## 🚀 Getting Started

### **1. Connect to Cluster**

```bash
# SSH to head node
ssh -i ~/.ssh/ersilia-key.pem ec2-user@HEAD_NODE_IP
```

### **2. First Time Setup**

```bash
# Check cluster status
 /shared/scripts/test-cluster.sh

# Download SIF files from S3
 /shared/scripts/sync-sif-from-s3.sh

# Verify models available
ls -lh  /shared/sif-files/
```

---

## 📦 Managing SIF Files

### **Method 1: Upload to S3 First** ⭐ RECOMMENDED

**From your local computer:**
```bash
# Upload individual SIF files
aws s3 cp eos2r5a.sif s3://ai2050-ersilia-cluster/sif-files/

# Or upload entire directory
aws s3 sync ./my-sif-files/ s3://ai2050-ersilia-cluster/sif-files/ --exclude "*" --include "*.sif"

# Verify upload
aws s3 ls s3://ai2050-ersilia-cluster/sif-files/
```

**Then from cluster:**
```bash
# Download all from S3
 /shared/scripts/sync-sif-from-s3.sh
```

### **Method 2: Download Individual Models On-Demand (from head node)**

```bash
# Download specific model from S3
 /shared/scripts/download-ersilia-model.sh eos2r5a
```

---

## 🔢 Processing Large Libraries

### **Step 1: Prepare Input Files (Local Computer)**

```bash
# Split your library into chunks, then upload to S3 in library folder structure

aws s3 sync ./library_001_chunks/ s3://ai2050-ersilia-cluster/input/library_001/

# Verify upload
aws s3 ls s3://ai2050-ersilia-cluster/input/library_001/
```

### **Step 2: Submit Batch Jobs (From Cluster)**

```bash
# Process entire library with one model
 /shared/scripts/submit-ersilia-batch.sh eos2r5a library_001 cpu-queue

# This submits one job per chunk file automatically
```

**Expected structure:**
```
Input:  /fsx/input/library_001/chunk_0001.csv
Output: /fsx/output/library_001/eos2r5a/eos2r5a_results_0001.csv
```

### **Step 3: Monitor Jobs**

```bash
# Watch job queue
watch -n 5 'squeue -u $USER'

# Check completed jobs
sacct -u $USER --format=JobID,JobName,State,Elapsed

# View specific job log
cat  /shared/logs/ersilia-JOBID.out
```

### **Step 4: Merge Results**

```bash
# After all jobs complete, merge chunk results
 /shared/scripts/merge-results.sh \
  /fsx/output/library_001/eos2r5a \
  /fsx/output/library_001/eos2r5a_final.csv

# Results automatically uploaded to S3
```

### **Step 5: Download Results (Local Computer)**

```bash
# Download final merged file
aws s3 cp s3://ai2050-ersilia-cluster/output/library_001/eos2r5a_final.csv ./

# Or download entire output directory
aws s3 sync s3://ai2050-ersilia-cluster/output/library_001/ ./library_001_results/
```

---


## 💡 Example Workflows

### **Process One Library with One Model**

```bash
# 1. Upload chunks to S3 (from local)
aws s3 sync ./library_001/ s3://ai2050-ersilia-cluster/input/library_001/

# 2. SSH to cluster
ssh ai2050cluster

# 3. Submit jobs
 /shared/scripts/submit-ersilia-batch.sh eos2r5a library_001 cpu-queue

# 4. Monitor
watch -n 5 'squeue -u $USER'

# 5. When complete, merge
 /shared/scripts/merge-results.sh \
  /fsx/output/library_001/eos2r5a \
  /fsx/output/library_001/eos2r5a_final.csv

# 6. Download results (from local)
aws s3 cp s3://ai2050-ersilia-cluster/output/library_001/eos2r5a_final.csv ./
```

### **Process Multiple Libraries with Multiple Models**

```bash
# Can run in parallel!
 /shared/scripts/submit-ersilia-batch.sh eos2r5a library_001 cpu-queue
 /shared/scripts/submit-ersilia-batch.sh eos3b5e library_001 cpu-queue
 /shared/scripts/submit-ersilia-batch.sh eos2r5a library_002 cpu-queue

# Monitor all jobs
watch -n 5 'squeue -u $USER | head -20'
```

**Output structure:**
```
/fsx/output/
├── library_001/
│   ├── eos2r5a/
│   │   └── eos2r5a_results_*.csv
│   ├── eos2r5a_final.csv
│   ├── eos3b5e/
│   │   └── eos3b5e_results_*.csv
│   └── eos3b5e_final.csv
└── library_002/
    ├── eos2r5a/
    │   └── eos2r5a_results_*.csv
    └── eos2r5a_final.csv
```

---

### **File Naming Conventions**

**Input chunks:**
- Format: `chunk_0001.csv`, `chunk_0002.csv`, ...
- Location: `/fsx/input/<library_name>/`

**Output results:**
- Format: `<model_id>_results_0001.csv`, `<model_id>_results_0002.csv`, ...
- Location: `/fsx/output/<library_name>/<model_id>/`

**Final merged:**
- Format: `<model_id>_final.csv`
- Location: `/fsx/output/<library_name>/`

### **Cost Optimization Tips**
1. ✅ Use Spot instances (already configured)
2. ✅ Process multiple libraries in one session
3. ✅ Delete cluster when not in use for weeks
4. ✅ Use test-queue for small tests
5. ✅ Monitor with Budget Alerts ($200/month threshold)

---

## 🔍 Troubleshooting

### **Compute Nodes Not Starting**

Check:
1. Service-Linked Role exists: `AWSServiceRoleForEC2Spot`
2. VPC endpoints: S3 and DynamoDB
3. Security group: HTTPS egress to pl-adae4bc4 and pl-c3aa4faa

### **Jobs Stuck in CF (Configuring)**

```bash
# SSH to compute node
ssh <node-name>

# Check Chef log
sudo tail -f /var/log/chef-client.log

# Check Slurm
systemctl status slurmd
```

### **SIF Files Not Found**

```bash
# Check if files are in S3
aws s3 ls s3://ai2050-ersilia-cluster/sif-files/

# Download from S3
 /shared/scripts/sync-sif-from-s3.sh

# Verify locally
ls -lh  /shared/sif-files/
```

---
