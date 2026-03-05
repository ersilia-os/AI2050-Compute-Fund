#!/bin/bash
# Check input vs output line counts for a processed library
# Usage: check-results.sh <library_name> <model_id>
#
# Example:
#   check-results.sh Enamine_Hit_Locator_460K eos4k4f_v1

LIBRARY_NAME=$1
MODEL_ID=$2

if [ -z "$LIBRARY_NAME" ] || [ -z "$MODEL_ID" ]; then
    echo "Usage: $0 <library_name> <model_id>"
    echo "Example: $0 Enamine_Hit_Locator_460K eos4k4f_v1"
    exit 1
fi

INPUT_DIR="/fsx/input/${LIBRARY_NAME}"
OUTPUT_DIR="/fsx/output/${LIBRARY_NAME}/${MODEL_ID}"

if [ ! -d "$INPUT_DIR" ]; then
    echo "ERROR: Input directory not found: $INPUT_DIR"
    exit 1
fi

if [ ! -d "$OUTPUT_DIR" ]; then
    echo "ERROR: Output directory not found: $OUTPUT_DIR"
    exit 1
fi

/shared/python39/bin/python3.9 << EOF
from pathlib import Path

input_dir  = Path("${INPUT_DIR}")
output_dir = Path("${OUTPUT_DIR}")
model_id   = "${MODEL_ID}"

input_chunks = sorted(input_dir.glob("*_chunk_*.csv"))

if not input_chunks:
    print(f"ERROR: No chunk files found in {input_dir}")
    exit(1)

print(f"Library : ${LIBRARY_NAME}")
print(f"Model   : {model_id}")
print(f"Chunks  : {len(input_chunks)}")
print()
print(f"{'Chunk':<10} {'Input rows':>12} {'Output rows':>13} {'Status':>10}")
print("-" * 50)

total_in = total_out = mismatches = missing = 0

for input_file in input_chunks:
    chunk_num = input_file.stem.split("_")[-1]
    output_file = output_dir / f"{model_id}_results_{chunk_num}.csv"

    in_rows = sum(1 for _ in input_file.open()) - 1  # subtract header

    if output_file.exists():
        out_rows = sum(1 for _ in output_file.open()) - 1
        if in_rows == out_rows:
            status = "OK"
        else:
            status = "MISMATCH"
            mismatches += 1
    else:
        out_rows = 0
        status = "MISSING"
        missing += 1

    total_in  += in_rows
    total_out += out_rows
    print(f"{chunk_num:<10} {in_rows:>12,} {out_rows:>13,} {status:>10}")

print("-" * 50)
print(f"{'TOTAL':<10} {total_in:>12,} {total_out:>13,}")
print()
print(f"Missing output files : {missing}")
print(f"Mismatched row counts: {mismatches}")
print(f"Completed            : {len(input_chunks) - missing - mismatches} / {len(input_chunks)}")
EOF
