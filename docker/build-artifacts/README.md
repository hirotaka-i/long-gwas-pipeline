# Docker Build Artifacts

This directory contains frozen versions of bioinformatics tools used in the Docker image.

## Why are these stored here?

These binaries are committed to the repository because:

1. **Upstream availability is not guaranteed** - URLs frequently break or get reorganized
2. **Version freezing** - Ensures exact reproducibility of the pipeline
3. **Build reliability** - Docker builds work offline and don't depend on external servers

## Contents

- `plink2_linux_x86_64_20210920.zip` (8.7 MB) - PLINK 2.0 (Sep 20, 2021)
- `plink_linux_x86_64_20210606.zip` (8.5 MB) - PLINK 1.9 (Jun 6, 2021)
- `gcta_1.93.2beta.zip` (11 MB) - GCTA 1.93.2 beta
- `liftOver_20250627.zip` (8.8 MB, 24 MB uncompressed) - UCSC Genome Browser liftOver tool (build date: Jun 27, 2025)

## Original URLs (may be broken)

- PLINK2: `https://s3.amazonaws.com/plink2-assets/plink2_linux_x86_64_20210920.zip` ❌ 404
- PLINK1: `https://s3.amazonaws.com/plink1-assets/plink_linux_x86_64_20210606.zip`
- GCTA: `https://cnsgenomics.com/software/gcta/bin/gcta_1.93.2beta.zip`
- liftOver: `http://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64/liftOver` (Last-Modified: Fri, 27 Jun 2025)

## Updating versions

If you need to update to newer versions:

1. Download the new binaries
2. Place them in this directory
3. Update the COPY commands in `Dockerfile`
4. Test the Docker build thoroughly
5. Update this README with new version info
