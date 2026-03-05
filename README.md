# AI2050 Compute Fund

This repository contains workflows and infrastructure templates for large-scale chemical library processing with Ersilia models on AWS ParallelCluster.

It currently covers two main areas:

1. Chemical library preprocessing into model-ready SMILES chunks.
2. AWS ParallelCluster templates and operational guides for batch inference at scale.

## Repository Contents

```text
AI2050-Compute-Fund/
├── scripts/
│   ├── 01_chemical_libraries_processing.py
│   ├── CHEMICAL_LIRARIES.md
│   └── AWS_templates/
│       ├── hpc_vpc_template.yaml
│       ├── cluster-config.yaml
│       ├── bootstrap-head-simplified.sh
│       ├── bootstrap-compute-simplified.sh
│       ├── check-results.sh
│       ├── PRE_DEPLOYMENT_CHECKLIST.md
│       ├── CLUSTER_DETAILS.md
│       └── CLUSTER_USAGE_HOWTO.md
├── assets/
├── README.md
└── LICENSE
```

## Chemical Library Processing

The script [`scripts/01_chemical_libraries_processing.py`](scripts/01_chemical_libraries_processing.py) extracts SMILES and compound IDs from supported public datasets and writes:

1. Chunked CSV files with one `smiles` column (10,000 rows per chunk).
2. A full `<library_name>_smiles_ids.csv` file with `smiles` and `collection_id`.

### Supported input files

- `Enamine_Hit_Locator_Library_plated.zip`
- `Enamine_Liquid-Stock-Collection-US.zip`
- `Molport_Screening_Compound_Database.zip`
- `coconut_csv-02-2026.zip`
- `2025.02_Enamine_REAL_DB_10.4M.cxsmiles.bz2`

### Usage

```bash
# Process all configured libraries from a directory
python scripts/01_chemical_libraries_processing.py \
  --input-dir ./raw \
  --output-dir ./output

# Process selected files only
python scripts/01_chemical_libraries_processing.py \
  --input-dir ./raw \
  --output-dir ./output \
  --files coconut_csv-02-2026.zip Enamine_Hit_Locator_Library_plated.zip
```

### Output layout

```text
output/
└── <library_name>/
    ├── <library_name>_chunk_000.csv
    ├── <library_name>_chunk_001.csv
    ├── ...
    └── <library_name>_smiles_ids.csv
```

More details: [`scripts/CHEMICAL_LIRARIES.md`](scripts/CHEMICAL_LIRARIES.md)

## AWS ParallelCluster Templates

Cluster infrastructure and operating docs are under [`scripts/AWS_templates/`](scripts/AWS_templates/).

### Key files

- VPC stack template: `hpc_vpc_template.yaml`
- Cluster config: `cluster-config.yaml`
- Bootstrap scripts: `bootstrap-head-simplified.sh`, `bootstrap-compute-simplified.sh`
- Results validation: `check-results.sh`
- Deployment checklist: `PRE_DEPLOYMENT_CHECKLIST.md`
- Operations guides: `CLUSTER_DETAILS.md`, `CLUSTER_USAGE_HOWTO.md`

### Typical flow

1. Validate prerequisites with `PRE_DEPLOYMENT_CHECKLIST.md`.
2. Provision networking (VPC/subnets/endpoints/security groups).
3. Deploy ParallelCluster with `cluster-config.yaml`.
4. Upload SIF models and input chunks to S3.
5. Submit jobs from the head node and monitor with Slurm.
6. Merge outputs and sync results back from S3.

## Notes

- `requirements.txt` is currently empty because the chemical processing script uses Python standard library modules only.
- `install.sh` is currently empty.
- Some docs include environment-specific IDs (VPC/subnet/security group, bucket names). Update them before reuse.

## About Ersilia

The [Ersilia Open Source Initiative](https://ersilia.io) builds open tools for AI-enabled drug discovery, with a focus on enabling research in low-resource settings.

![Ersilia Logo](assets/Ersilia_Brand.png)
