#!/bin/bash
# Check input vs output line counts for all libraries for a given model
# Reports missing chunks and chunks with fully-empty result rows
# Usage: check-results.sh <model_id>
#
# Example:
#   check-results.sh eos4k4f_v1

MODEL_ID=$1

if [ -z "$MODEL_ID" ]; then
    echo "Usage: $0 <model_id>"
    echo "Example: $0 eos4k4f_v1"
    exit 1
fi

LIBRARIES=(
    "Enamine_Hit_Locator_460K"
    "Coconut_715K"
    "Enamine_Liquid_Stock_2.5M"
    "Molport_Screening_Compounds_5.3M"
    "Enamine_Real_Sample_10.4M"
)

/shared/python39/bin/python3.9 << EOF
import csv
from pathlib import Path

csv.field_size_limit(10 * 1024 * 1024)

INPUT_COLS = {"key", "input", "smiles", "canonical_smiles"}

model_id  = "${MODEL_ID}"
libraries = [$(printf '"%s",' "${LIBRARIES[@]}")]

def check_chunk_empties(output_file, input_cols):
    """Return count of rows where ALL result columns are empty."""
    empty_rows = 0
    result_cols = None
    try:
        with open(output_file, newline="") as fh:
            reader = csv.DictReader(fh)
            if reader.fieldnames:
                result_cols = [c for c in reader.fieldnames
                               if c.strip().lower() not in input_cols]
            for row in reader:
                if result_cols and all(row.get(c, "").strip() == "" for c in result_cols):
                    empty_rows += 1
    except Exception as e:
        print(f"    WARNING: could not read {output_file.name}: {e}")
    return empty_rows

print()
print(f"Model: {model_id}")
print("=" * 75)
print(f"{'Library':<45} {'Chunks':>7} {'Missing':>8} {'Empty rows':>11} {'Done':>7}")
print("-" * 75)

for library in libraries:
    input_dir  = Path(f"/fsx/input/{library}")
    output_dir = Path(f"/fsx/output/{library}/{model_id}")

    if not input_dir.exists() or not output_dir.exists():
        print(f"{library:<45} {'—':>7} {'—':>8} {'—':>11} {'NOT RUN':>7}")
        continue

    input_chunks = sorted(input_dir.glob("*_chunk_*.csv"))
    if not input_chunks:
        print(f"{library:<45} {'—':>7} {'—':>8} {'—':>11} {'NO INPUT':>7}")
        continue

    missing_chunks = []
    mismatch_chunks = []
    empty_chunks = []   # (chunk_num, empty_row_count)
    done = 0

    for input_file in input_chunks:
        chunk_num   = input_file.stem.split("_")[-1]
        output_file = output_dir / f"{model_id}_results_{chunk_num}.csv"

        if not output_file.exists():
            missing_chunks.append(chunk_num)
            continue

        in_rows  = sum(1 for _ in input_file.open()) - 1
        out_rows = sum(1 for _ in output_file.open()) - 1

        if in_rows != out_rows:
            mismatch_chunks.append(chunk_num)
        else:
            done += 1

        empty_count = check_chunk_empties(output_file, INPUT_COLS)
        if empty_count > 0:
            empty_chunks.append((chunk_num, empty_count))

    total      = len(input_chunks)
    n_missing  = len(missing_chunks)
    n_empty    = sum(c for _, c in empty_chunks)
    status     = f"{done}/{total}"

    print(f"{library:<45} {total:>7,} {n_missing:>8,} {n_empty:>11,} {status:>7}")

    if missing_chunks:
        chunks_str = ", ".join(missing_chunks[:20])
        suffix = f" ... (+{len(missing_chunks)-20} more)" if len(missing_chunks) > 20 else ""
        print(f"  MISSING chunks : {chunks_str}{suffix}")

    if mismatch_chunks:
        chunks_str = ", ".join(mismatch_chunks[:20])
        suffix = f" ... (+{len(mismatch_chunks)-20} more)" if len(mismatch_chunks) > 20 else ""
        print(f"  MISMATCH chunks: {chunks_str}{suffix}")

    if empty_chunks:
        top = empty_chunks[:10]
        summary = ", ".join(f"{c}({n} rows)" for c, n in top)
        suffix = f" ... (+{len(empty_chunks)-10} more chunks)" if len(empty_chunks) > 10 else ""
        print(f"  EMPTY row chunks: {summary}{suffix}")

print("=" * 75)
print()
EOF
