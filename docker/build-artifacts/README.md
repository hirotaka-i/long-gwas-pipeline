# Build Artifacts

This directory contains pre-downloaded binary tools and source archives used to build the Docker image. These files are committed to the repository to ensure reproducible, offline builds.

## Why Are These Committed to Git?

1. **Reproducibility** - Exact versions are preserved and guaranteed
2. **Offline builds** - No internet connection required during Docker builds
3. **Build speed** - No download time (faster CI/CD)
4. **Reliability** - Immune to upstream URL changes or deletions
5. **Transparency** - Clear audit trail of tool versions

## Binary Tools

### PLINK 2.0
- **File**: `plink2_linux_x86_64_20251205.zip`
- **Version**: 2.0.0-a.7LM (December 5, 2025)
- **Purpose**: Genome-wide association analysis, QC, and data management
- **Download**: https://www.cog-genomics.org/plink/2.0/
- **Direct Link**: https://s3.amazonaws.com/plink2-assets/alpha6/plink2_linux_x86_64_20251205.zip
- **License**: GPLv3
- **Reference**: Chang CC, et al. (2015) Second-generation PLINK. GigaScience, 4.

### PLINK 1.9
- **File**: `plink_linux_x86_64_20210606.zip`
- **Version**: 1.90b6.21 (June 6, 2021)
- **Purpose**: Legacy PLINK for compatibility
- **Download**: https://www.cog-genomics.org/plink/1.9/
- **Direct Link**: https://s3.amazonaws.com/plink1-assets/plink_linux_x86_64_20210606.zip
- **License**: GPLv3
- **Reference**: Purcell S, et al. (2007) Am J Hum Genet, 81:559-575.

### GCTA
- **File**: `gcta_1.93.2beta.zip`
- **Version**: 1.93.2beta
- **Purpose**: Genome-wide Complex Trait Analysis (kinship, REML)
- **Download**: https://yanglab.westlake.edu.cn/software/gcta/
- **Direct Link**: https://yanglab.westlake.edu.cn/software/gcta/bin/gcta_1.93.2beta.zip
- **License**: MIT License
- **Reference**: Yang J, et al. (2011) Am J Hum Genet, 88:76-82.

## Source Code Archives

### bcftools
- **File**: `bcftools-1.20.tar.bz2` (7.5 MB)
- **Version**: 1.20
- **Purpose**: VCF/BCF manipulation, variant calling, liftover
- **Download**: https://github.com/samtools/bcftools/releases/tag/1.20
- **Direct Link**: https://github.com/samtools/bcftools/releases/download/1.20/bcftools-1.20.tar.bz2
- **License**: MIT/Expat
- **Reference**: Danecek P, et al. (2021) GigaScience, 10(2):giab008.

### HTSlib
- **File**: `htslib-1.20.tar.bz2` (4.6 MB)
- **Version**: 1.20
- **Purpose**: C library for SAM/BAM/CRAM/VCF/BCF formats
- **Download**: https://github.com/samtools/htslib/releases/tag/1.20
- **Direct Link**: https://github.com/samtools/htslib/releases/download/1.20/htslib-1.20.tar.bz2
- **License**: MIT/Expat
- **Reference**: Bonfield JK, et al. (2021) GigaScience, 10(2):giab007.

### SAMtools
- **File**: `samtools-1.20.tar.bz2` (8.8 MB)
- **Version**: 1.20
- **Purpose**: SAM/BAM/CRAM manipulation, faidx indexing
- **Download**: https://github.com/samtools/samtools/releases/tag/1.20
- **Direct Link**: https://github.com/samtools/samtools/releases/download/1.20/samtools-1.20.tar.bz2
- **License**: MIT/Expat
- **Reference**: Danecek P, et al. (2021) GigaScience, 10(2):giab008.

### METAL
- **File**: `METAL-2020-05-05.tar.gz` (970 KB)
- **Version**: 2020-05-05
- **Purpose**: Meta-analysis of GWAS
- **Download**: https://github.com/statgen/METAL/releases/tag/2020-05-05
- **Direct Link**: https://github.com/statgen/METAL/archive/refs/tags/2020-05-05.tar.gz
- **License**: BSD-3-Clause
- **Reference**: Willer CJ, et al. (2010) Bioinformatics, 26(17):2190-2191.

### bcftools liftover plugin
- **File**: `liftover.c` (120 KB)
- **Version**: Latest from master
- **Purpose**: Genome coordinate conversion for VCF files
- **Repository**: https://github.com/freeseek/score
- **Direct Link**: https://raw.githubusercontent.com/freeseek/score/master/liftover.c
- **Author**: Giulio Genovese (third-party, not official bcftools)
- **License**: MIT


## License Summary

All tools are open-source:
- **MIT/Expat**: bcftools, HTSlib, SAMtools, liftover plugin, GCTA
- **GPLv3**: PLINK 1.9, PLINK 2.0
- **BSD-3-Clause**: METAL

See individual tool websites for full license terms
