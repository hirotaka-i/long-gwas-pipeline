#!/bin/bash
#
# Download and prepare reference genomes for bcftools +liftover
#
# This script downloads reference genomes on-demand based on the source assembly.
# It automatically handles bgzip compression and fai indexing required by bcftools +liftover.
#
# Usage: 
#   ./bin/download_references.sh <source_assembly> [reference_dir]
#
# Arguments:
#   source_assembly: Source genome assembly (hg18, hg19, or hg38)
#   reference_dir: Reference directory (default: ./References)
#
# Examples:
#   ./bin/download_references.sh hg19
#   ./bin/download_references.sh hg18 /path/to/references
#

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
SOURCE_ASSEMBLY="${1}"
REF_DIR="${2:-${RESOURCE_DIR:-./References}}"

# Validate source assembly argument
if [ -z "$SOURCE_ASSEMBLY" ]; then
    echo -e "${RED}Error: Source assembly required${NC}"
    echo "Usage: $0 <hg18|hg19|hg38> [reference_dir]"
    exit 1
fi

if [[ ! "$SOURCE_ASSEMBLY" =~ ^(hg18|hg19|hg38)$ ]]; then
    echo -e "${RED}Error: Invalid assembly '${SOURCE_ASSEMBLY}'${NC}"
    echo "Valid options: hg18, hg19, hg38"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Reference Genome Setup${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Source assembly: ${SOURCE_ASSEMBLY}"
echo "Reference directory: ${REF_DIR}"
echo ""

# Create directory structure
mkdir -p "${REF_DIR}/Genome"
mkdir -p "${REF_DIR}/liftOver"

# Function to download and process a reference genome
download_genome() {
    local assembly=$1
    local output_file="${REF_DIR}/Genome/${assembly}.fa.gz"
    local fai_file="${output_file}.fai"
    
    if [ -f "$output_file" ] && [ -f "$fai_file" ]; then
        echo -e "${YELLOW}${assembly}.fa.gz already exists with index. Skipping.${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}Downloading and processing ${assembly} reference genome...${NC}"
    
    # Check for required tools
    if ! command -v bgzip &> /dev/null; then
        echo -e "${RED}Error: bgzip not found. Please install htslib/samtools.${NC}"
        exit 1
    fi
    
    if ! command -v samtools &> /dev/null; then
        echo -e "${RED}Error: samtools not found. Please install samtools.${NC}"
        exit 1
    fi
    
    # Download, decompress, and recompress with bgzip
    echo "Downloading ${assembly}.fa.gz from UCSC..."
    if command -v wget &> /dev/null; then
        wget -q --show-progress -O - \
            "https://hgdownload.soe.ucsc.edu/goldenPath/${assembly}/bigZips/${assembly}.fa.gz" | \
            gunzip | bgzip -c > "$output_file"
    else
        curl -L --progress-bar \
            "https://hgdownload.soe.ucsc.edu/goldenPath/${assembly}/bigZips/${assembly}.fa.gz" | \
            gunzip | bgzip -c > "$output_file"
    fi
    
    echo "Generating .fai index..."
    samtools faidx "$output_file"
    
    echo -e "${GREEN}✓ ${assembly}.fa.gz ready ($(du -h "$output_file" | cut -f1))${NC}"
}

# Function to download chain file
download_chain() {
    local source=$1
    local chain_file="${REF_DIR}/liftOver/${source}ToHg38.over.chain.gz"
    
    if [ -f "$chain_file" ]; then
        echo -e "${YELLOW}${source}ToHg38.over.chain.gz already exists. Skipping.${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}Downloading ${source}ToHg38 chain file...${NC}"
    if command -v wget &> /dev/null; then
        wget -q --show-progress -O "$chain_file" \
            "https://hgdownload.cse.ucsc.edu/goldenpath/${source}/liftOver/${source}ToHg38.over.chain.gz"
    else
        curl -L --progress-bar -o "$chain_file" \
            "https://hgdownload.cse.ucsc.edu/goldenpath/${source}/liftOver/${source}ToHg38.over.chain.gz"
    fi
    
    echo -e "${GREEN}✓ ${source}ToHg38.over.chain.gz ready ($(du -h "$chain_file" | cut -f1))${NC}"
}

# Always download hg38 (destination assembly for liftover)
echo -e "${GREEN}[1/3] Preparing destination assembly (hg38)...${NC}"
download_genome "hg38"
echo ""

# Download source assembly if different from hg38
if [ "$SOURCE_ASSEMBLY" != "hg38" ]; then
    echo -e "${GREEN}[2/3] Preparing source assembly (${SOURCE_ASSEMBLY})...${NC}"
    download_genome "$SOURCE_ASSEMBLY"
    echo ""
    
    echo -e "${GREEN}[3/3] Downloading chain file...${NC}"
    download_chain "$SOURCE_ASSEMBLY"
    echo ""
else
    echo -e "${GREEN}[2/3] Source assembly is hg38 - no liftover needed${NC}"
    echo -e "${GREEN}[3/3] Skipping chain file download${NC}"
    echo ""
fi

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Reference setup complete!${NC}"
echo ""
echo "Directory structure:"
echo "${REF_DIR}/"
echo "├── Genome/"

if [ "$SOURCE_ASSEMBLY" != "hg38" ]; then
    echo "│   ├── ${SOURCE_ASSEMBLY}.fa.gz"
    echo "│   ├── ${SOURCE_ASSEMBLY}.fa.gz.fai"
fi

echo "│   ├── hg38.fa.gz"
echo "│   └── hg38.fa.gz.fai"

if [ "$SOURCE_ASSEMBLY" != "hg38" ]; then
    echo "└── liftOver/"
    echo "    └── ${SOURCE_ASSEMBLY}ToHg38.over.chain.gz"
fi

echo ""
echo -e "${GREEN}Ready for pipeline execution!${NC}"
