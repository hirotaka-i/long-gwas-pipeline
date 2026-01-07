#!/bin/bash
#
# Container wrapper for liftover_sumstats.py
# Uses the long-gwas-pipeline container (Docker or Singularity) with bcftools +liftover
#

set -e

# Default container image
CONTAINER_IMAGE="ghcr.io/hirotaka-i/long-gwas-pipeline:latest"
SINGULARITY_IMAGE="docker://${CONTAINER_IMAGE}"

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(dirname "$SCRIPT_DIR")"

# Function to show usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Container wrapper for liftover_sumstats.py (auto-detects Docker or Singularity)

Required Arguments:
  -i, --input FILE           Input summary statistics file (txt or txt.gz)
  -o, --output FILE          Output lifted summary statistics file
  -u, --unmatched FILE       Output file for unmatched variants
  
  --chr-col NAME             Chromosome column name
  --pos-col NAME             Position column name
  --ea-col NAME              Effect allele column name
  --ref-col NAME             Reference allele column name
  
  --source-fasta FILE        Source reference fasta file
  --target-fasta FILE        Target reference fasta file
  --chain-file FILE          Chain file for liftover

Optional Arguments:
  --effect-col NAME          Effect column name to flip (e.g., Z, BETA)
                             Can specify multiple times
  --eaf-col NAME             Effect allele frequency column to flip when alleles swap
                             (e.g., EAF, EAF_UKB). Can specify multiple times
  --rsid-col NAME            RSID column name
  --add-chr-prefix           Add 'chr' prefix to chromosomes (use if source fasta has chr1, chr2, etc.)
  --container-image IMAGE    Container image to use (default: $CONTAINER_IMAGE)
  --keep-temp               Keep temporary files
  -h, --help                Show this help message

Example:
  $0 \\
    --input ~/sumstats.txt.gz \\
    --output sumstats_hg38.txt.gz \\
    --unmatched sumstats_unmatched.txt.gz \\
    --chr-col CHR \\
    --pos-col POS \\
    --ea-col A1 \\
    --ref-col A2 \\
    --effect-col Z \\
    --eaf-col EAF_UKB \\
    --rsid-col RSID \\
    --source-fasta References/Genome/hg19.fa.gz \\
    --target-fasta References/Genome/hg38.fa.gz \\
    --chain-file References/liftOver/hg19ToHg38.over.chain.gz

EOF
    exit 1
}

# Parse arguments
ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --container-image|--docker-image)
            CONTAINER_IMAGE="$2"
            SINGULARITY_IMAGE="docker://${CONTAINER_IMAGE}"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done

# Detect container runtime (prefer Singularity for HPC environments)
CONTAINER_RUNTIME=""
if command -v singularity &> /dev/null; then
    CONTAINER_RUNTIME="singularity"
elif command -v docker &> /dev/null; then
    CONTAINER_RUNTIME="docker"
else
    echo "Error: Neither Singularity nor Docker is installed or in PATH" >&2
    exit 1
fi

# Get absolute paths for mounting
# We need to mount:
# 1. The pipeline directory (contains the script)
# 2. User's home directory (for input/output files)
# 3. Current working directory (if different)
# 4. /tmp directory for temporary files

HOME_DIR="$(cd ~ && pwd)"
CURRENT_DIR="$(pwd)"
TMP_DIR="/tmp"

echo "Running liftover in Docker container..." >&2
echo "Docker image: $DOusing $CONTAINER_RUNTIME..." >&2
echo "Container image: $CONTAINER_IMAGE" >&2
echo "" >&2

# Run the Python script inside container
if [[ "$CONTAINER_RUNTIME" == "singularity" ]]; then
    # Singularity command
    singularity exec \
        --bind "$PIPELINE_DIR:/pipeline:ro" \
        --bind "$HOME_DIR:$HOME_DIR" \
        --bind "$CURRENT_DIR:$CURRENT_DIR" \
        --bind "$TMP_DIR:$TMP_DIR" \
        --pwd "$CURRENT_DIR" \
        "$SINGULARITY_IMAGE" \
        python3 /pipeline/utils/liftover_sumstats.py "${ARGS[@]}"
else
    # Docker command
    docker run --rm \
        -v "$PIPELINE_DIR:/pipeline:ro" \
        -v "$HOME_DIR:$HOME_DIR" \
        -v "$CURRENT_DIR:$CURRENT_DIR" \
        -v "$TMP_DIR:$TMP_DIR" \
        -w "$CURRENT_DIR" \
        -u "$(id -u):$(id -g)" \
        "$CONTAINER_IMAGE" \
        python3 /pipeline/utils/liftover_sumstats.py "${ARGS[@]}"
fi
echo "" >&2
echo "Liftover complete!" >&2
