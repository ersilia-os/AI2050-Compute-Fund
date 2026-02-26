# Chemical Library Processing Pipeline

This repository contains a pipeline to extract SMILES from publicly available chemical databases and prepare them for downstream virtual screening or machine learning workflows.

---

## Overview

The script `process_chemical_libraries.py` processes raw chemical database files, extracts canonical SMILES and compound IDs, and produces:

1. **Chunk files** — SMILES-only CSVs split into 10,000-row files, named `<library_name>_chunk_NNN.csv`
2. **Full ID file** — A single CSV with both SMILES and the original collection ID, named `<library_name>_smiles_ids.csv`

---

## Source Libraries

| File | Library Name | Size | Format |
|------|-------------|------|--------|
| `Enamine_Hit_Locator_Library_plated.zip` | `Enamine_Hit_Locator_460K` | ~460K cpds | CSV (Excel-style, comma-separated) |
| `Enamine_Liquid-Stock-Collection-US.zip` | `Enamine_Liquid_Stock_2.5M` | ~2.5M cpds | CSV (Excel-style, comma-separated) |
| `Molport_Screening_Compound_Database.zip` | `Molport_Screening_Compounds_5.3M` | ~5.3M cpds | ZIP of `.txt.gz` shards (TSV) |
| `coconut_csv-02-2026.zip` | `Coconut_715K` | ~715K cpds | CSV |
| `2025.02_Enamine_REAL_DB_10.4M.cxsmiles.bz2` | `Enamine_Real_Sample_10.4M` | ~10.4M cpds | BZ2-compressed TSV (cxsmiles) |

### SMILES and ID columns used per source

| Library | SMILES column | ID column |
|---------|--------------|-----------|
| Enamine Hit Locator | `SMILES` | `Catalog ID` |
| Enamine Liquid Stock | `SMILES` | `CatalogId` |
| Molport | `SMILES_CANONICAL` | `MOLPORTID` |
| Coconut | `canonical_smiles` | `identifier` |
| Enamine REAL | `smiles` | `id` |

---

## Output Structure

```
output/
├── Enamine_Hit_Locator_460K/
│   ├── Enamine_Hit_Locator_460K_chunk_000.csv
│   ├── Enamine_Hit_Locator_460K_chunk_001.csv
│   ├── ...
│   └── Enamine_Hit_Locator_460K_smiles_ids.csv
├── Enamine_Liquid_Stock_2.5M/
│   └── ...
├── Molport_Screening_Compounds_5.3M/
│   └── ...
├── Coconut_715K/
│   └── ...
└── Enamine_Real_Sample_10.4M/
    └── ...
```

Each chunk CSV has a single `smiles` column. The `_smiles_ids.csv` file has two columns: `smiles` and `collection_id`.

---

## Usage

```bash
# Process all libraries (raw files in ./raw, output to current directory)
python process_chemical_libraries.py --input-dir raw --output-dir .

# Process a single library
python process_chemical_libraries.py --input-dir raw --output-dir . \
  --files coconut_csv-02-2026.zip

# Process a subset
python process_chemical_libraries.py --input-dir raw --output-dir . \
  --files Enamine_Hit_Locator_Library_plated.zip \
          Enamine_Liquid-Stock-Collection-US.zip
```

### Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `--input-dir` | `.` | Directory containing the raw database files |
| `--output-dir` | `./output` | Root directory for all output files |
| `--files` | *(all)* | Optional subset of filenames to process |

---

## Requirements

Python 3.10+ — no external dependencies (stdlib only: `csv`, `gzip`, `bz2`, `zipfile`).

---

## Implementation Notes

- **Molport** is distributed as a ZIP archive containing many `.txt.gz` shard files. These are streamed and processed sequentially without full decompression into RAM.
- **Enamine REAL** (10.4M compounds) is a bz2-compressed TSV streamed line-by-line to avoid high memory usage.
- **Enamine Hit Locator and Liquid Stock** files include an Excel-style `sep=,` directive on the first line which is automatically detected and skipped.
- **Coconut** contains very long InChI strings, requiring an increased CSV field size limit (set to 10 MB per field).
- All SMILES and ID columns are resolved case-insensitively.