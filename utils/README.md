# Standalone Utilities

This directory contains standalone tools that use the pipeline's Docker image but are independent of the main Nextflow workflow.

## Available Tools


### Liftover Summary Statistics
Convert GWAS summary statistics between genome builds (e.g. hg19 ↔ hg38) effect allele and effect allele frequency adjustments included.
- **liftover_sumstats.py** - Python script to perform liftover of GWAS summary statistics using UCSC liftOver tool.
- **liftover_sumstats_wrapper.sh** - Docker wrapper for liftover_sumstats.py. 

These tools can be used independently without running the full pipeline.
