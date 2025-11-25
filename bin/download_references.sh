#!/bin/bash
#
# Download reference files for local execution of long-gwas-pipeline
#
# This script downloads the necessary reference genome and liftOver chain files
# required for running the pipeline with the 'standard' profile (local execution).
#
# Usage: ./bin/download_references.sh [target_directory]
#
# Default target: ./files (as specified in standard profile)
#

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Target directory (default: ./files)
TARGET_DIR="${1:-$PWD/files}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Reference Files Download Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Target directory: ${TARGET_DIR}"
echo ""

# Create directory structure
echo -e "${YELLOW}[1/5] Creating directory structure...${NC}"
mkdir -p "${TARGET_DIR}/Genome"
mkdir -p "${TARGET_DIR}/liftOver"
echo -e "${GREEN}✓ Directories created${NC}"
echo ""

# Download hg38 reference genome
echo -e "${YELLOW}[2/5] Downloading hg38 reference genome...${NC}"
echo "Source: UCSC Genome Browser"
echo "File: hg38.fa.gz (~938 MB)"
echo ""

if [ -f "${TARGET_DIR}/Genome/hg38.fa.gz" ]; then
    echo -e "${YELLOW}hg38.fa.gz already exists. Skipping download.${NC}"
else
    echo "Downloading hg38.fa.gz..."
    curl -L -o "${TARGET_DIR}/Genome/hg38.fa.gz" \
        "https://hgdownload.soe.ucsc.edu/goldenPath/hg38/bigZips/hg38.fa.gz"
    echo -e "${GREEN}✓ hg38.fa.gz downloaded${NC}"
fi
echo ""

# Download hg38 index (optional but recommended)
echo -e "${YELLOW}[3/5] Downloading hg38 FASTA index...${NC}"
if [ -f "${TARGET_DIR}/Genome/hg38.fa.gz.fai" ]; then
    echo -e "${YELLOW}hg38.fa.gz.fai already exists. Skipping download.${NC}"
else
    echo "Downloading hg38.fa.gz.fai..."
    curl -L -o "${TARGET_DIR}/Genome/hg38.fa.gz.fai" \
        "https://hgdownload.soe.ucsc.edu/goldenPath/hg38/bigZips/hg38.fa.gz.fai"
    echo -e "${GREEN}✓ hg38.fa.gz.fai downloaded${NC}"
fi
echo ""

# Download liftOver chain files
echo -e "${YELLOW}[4/5] Downloading liftOver chain files...${NC}"
echo "These files convert genome coordinates between assemblies"
echo ""

# hg18 to hg38
if [ -f "${TARGET_DIR}/liftOver/hg18ToHg38.over.chain.gz" ]; then
    echo -e "${YELLOW}hg18ToHg38.over.chain.gz already exists. Skipping.${NC}"
else
    echo "Downloading hg18ToHg38.over.chain.gz..."
    curl -L -o "${TARGET_DIR}/liftOver/hg18ToHg38.over.chain.gz" \
        "https://hgdownload.soe.ucsc.edu/goldenPath/hg18/liftOver/hg18ToHg38.over.chain.gz"
    echo -e "${GREEN}✓ hg18ToHg38.over.chain.gz downloaded${NC}"
fi

# hg19 to hg38
if [ -f "${TARGET_DIR}/liftOver/hg19ToHg38.over.chain.gz" ]; then
    echo -e "${YELLOW}hg19ToHg38.over.chain.gz already exists. Skipping.${NC}"
else
    echo "Downloading hg19ToHg38.over.chain.gz..."
    curl -L -o "${TARGET_DIR}/liftOver/hg19ToHg38.over.chain.gz" \
        "https://hgdownload.soe.ucsc.edu/goldenPath/hg19/liftOver/hg19ToHg38.over.chain.gz"
    echo -e "${GREEN}✓ hg19ToHg38.over.chain.gz downloaded${NC}"
fi

# hg38 to hg38 (identity - for consistency)
if [ -f "${TARGET_DIR}/liftOver/hg38ToHg38.over.chain.gz" ]; then
    echo -e "${YELLOW}hg38ToHg38.over.chain.gz already exists. Skipping.${NC}"
else
    echo "Creating hg38ToHg38.over.chain.gz (identity mapping)..."
    # Create a minimal identity chain file
    echo "chain 1 chr1 248956422 + 0 248956422 chr1 248956422 + 0 248956422 1" | gzip > "${TARGET_DIR}/liftOver/hg38ToHg38.over.chain.gz"
    echo -e "${GREEN}✓ hg38ToHg38.over.chain.gz created${NC}"
fi
echo ""

# Verify downloads
echo -e "${YELLOW}[5/5] Verifying downloads...${NC}"
echo ""

MISSING_FILES=0

# Check hg38 reference
if [ -f "${TARGET_DIR}/Genome/hg38.fa.gz" ]; then
    SIZE=$(du -h "${TARGET_DIR}/Genome/hg38.fa.gz" | cut -f1)
    echo -e "${GREEN}✓${NC} hg38.fa.gz (${SIZE})"
else
    echo -e "${RED}✗${NC} hg38.fa.gz MISSING"
    MISSING_FILES=$((MISSING_FILES + 1))
fi

# Check liftOver files
for assembly in hg18 hg19 hg38; do
    FILE="${TARGET_DIR}/liftOver/${assembly}ToHg38.over.chain.gz"
    if [ -f "$FILE" ]; then
        SIZE=$(du -h "$FILE" | cut -f1)
        echo -e "${GREEN}✓${NC} ${assembly}ToHg38.over.chain.gz (${SIZE})"
    else
        echo -e "${RED}✗${NC} ${assembly}ToHg38.over.chain.gz MISSING"
        MISSING_FILES=$((MISSING_FILES + 1))
    fi
done

echo ""
echo -e "${GREEN}========================================${NC}"

if [ $MISSING_FILES -eq 0 ]; then
    echo -e "${GREEN}✓ All reference files downloaded successfully!${NC}"
    echo ""
    echo "Directory structure:"
    echo "${TARGET_DIR}/"
    echo "├── Genome/"
    echo "│   ├── hg38.fa.gz"
    echo "│   └── hg38.fa.gz.fai"
    echo "└── liftOver/"
    echo "    ├── hg18ToHg38.over.chain.gz"
    echo "    ├── hg19ToHg38.over.chain.gz"
    echo "    └── hg38ToHg38.over.chain.gz"
    echo ""
    echo -e "${GREEN}You can now run the pipeline with:${NC}"
    echo "  nextflow run main.nf -profile standard -params-file params.yml"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Some files are missing!${NC}"
    echo "Please check your internet connection and try again."
    exit 1
fi
