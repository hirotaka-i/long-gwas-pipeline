# longitudinal-GWAS-pipeline

Repository for Nextflow pipeline to perform GWAS with longitudinal capabilities

## Overview

This pipeline supports three types of genetic assoc## Documentation

### For Users
- 🚀 **[Quick Start](#quick-start)**: Installation and basic usage (see above)
- 📋 **[Parameters](docs/parameters.md)**: Complete parameter reference
- 📊 **[File Formats](docs/file_formats.md)**: Comprehensive input/output file format specifications
- 📝 **[Examples](docs/examples.md)**: Practical usage examples with params.yml
- 🔧 **[Configuration & Profiles](docs/config.md)**: Execution environments and resource management

### For Developers
- 📖 **[Docker Improvements](docs/DOCKER_IMPROVEMENTS.md)**: Complete guide including software versions, pandas/numpy fixes, and build optimization
- 🏗️ **[Repository Guide](docs/REPOSITORY_GUIDE.md)**: Complete architecture and code organization guide
- ⚡ **[Quick Reference](docs/QUICK_REFERENCE.md)**: Fast lookup for common tasks and troubleshooting
- 🔬 **[Reference Files Setup](docs/REFERENCE_FILES_SETUP.md)**: Reference file architecture and setups:
- **Cross-sectional** (GLM): Standard GWAS with single time-point phenotypes
- **Longitudinal** (GALLOP/LMM): Repeated measures analysis with time-varying phenotypes
- **Survival** (Cox PH): Time-to-event analysis

**Pipeline stages:**
```
Input: VCF files + Phenotypes + Covariates
  ↓
Stage 1: Genetic QC (filtering, normalization, merging)
  ↓
Stage 2: Data Preparation (outlier removal, PCA, formatting)
  ↓
Stage 3: GWAS Execution (GLM/GALLOP/CPH)
  ↓
Output: Association statistics + Manhattan plots
```

## Quick Start

### Prerequisites

- **Nextflow** >= 21.04.0 (DSL2 required)
  ```bash
  # Check your version
  nextflow -version
  
  # Install/update Nextflow
  curl -s https://get.nextflow.io | bash
  ```
- **Docker** or **Singularity** (for containerized execution)
  - Docker Desktop (Mac/Windows) or Docker Engine (Linux)
  - OR Singularity/Apptainer (HPC environments)

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/hirotaka-i/long-gwas-pipeline.git
   cd long-gwas-pipeline
   ```

2. **Run the pipeline:**
   ```bash
   nextflow run main.nf -profile standard -params-file params.yml
   ```
   
   - `main.nf`: Main Nextflow script
   - `-profile`: Environment configuration (see Profiles below)
   - `params.yml`: Parameter settings file

## Profiles

The pipeline supports multiple execution profiles defined in `nextflow.config`:

### 1. `standard` (Recommended for most users)
Uses the official Docker image from DockerHub:
```bash
nextflow run main.nf -profile standard -params-file params.yml
```
- **Docker image**: `amcalejandro/longgwas:v2` (stable, production-ready)
- **Scripts**: Uses your local `bin/` directory (auto-mounted by Nextflow)
- **No build required**: Just pull and run

### 2. `localtest` (For developers)
Uses a locally built Docker image for testing modifications:
```bash
# First, build the Docker image (Apple Silicon requires --platform flag)
docker build --platform linux/amd64 -f Dockerfile.ubuntu22 -t longgwas-local-test .

# Then run the pipeline
nextflow run main.nf -profile localtest -params-file params.yml
```
- **Docker image**: `longgwas-local-test` (built locally)
- **Scripts**: Uses your local `bin/` directory (auto-mounted by Nextflow)
- **Purpose**: Test Docker image changes before pushing to DockerHub

### 3. Other profiles
- `adwb`: All-of-Us Data Workbench environment
- `biowulf`: NIH Biowulf HPC with Singularity
- `gls`: Google Life Sciences
- `gcb`: Google Cloud Batch
- `gs-data`: Google Cloud Storage with local executor

See [Configuration Guide](docs/config.md) for details on each profile.

## Analysis Types

### Cross-sectional (GLM)
For single time-point phenotypes:
```bash
nextflow run main.nf -profile standard -params-file params.yml \
  --linear_flag true \
  --phenofile phenotype.cs.tsv
```

### Longitudinal (GALLOP/LMM)
For repeated measures with time-varying phenotypes:
```bash
nextflow run main.nf -profile standard -params-file params.yml \
  --longitudinal_flag true \
  --phenofile phenotype.lt.tsv \
  --time_col study_days
```

### Survival (Cox Proportional Hazards)
For time-to-event analysis:
```bash
nextflow run main.nf -profile standard -params-file params.yml \
  --survival_flag true \
  --phenofile phenotype.surv.tsv \
  --time_col time_to_event
```

See [Examples](docs/examples.md) for detailed use cases.

## Developer's Guide

### What changes are reflected immediately (no rebuild needed):

✅ **Scripts in `bin/` directory**
- Nextflow automatically mounts `bin/` into containers
- Modify any `.py`, `.sh`, or `.R` script and run immediately
- Examples: `manhattan.py`, `process1.sh`, `qc.py`, `gallop.py`

✅ **Workflow files**
- `workflows/*.nf`
- `subworkflows/*.nf`  
- `modules/**/*.nf`

### What requires Docker rebuild:

🔧 **Package installations and software updates**
- Python packages (pip install)
- R packages
- System packages (apt-get)
- Bioinformatics tools (plink, bcftools, etc.)

**To rebuild:**
```bash
docker build --platform linux/amd64 -f Dockerfile.ubuntu22 -t longgwas-local-test .
```

> **Note for Apple Silicon (M1/M2/M3) users**: Always use `--platform linux/amd64` flag when building. The pipeline uses x86_64 binaries (liftOver, plink, etc.) that require amd64 platform.

### Pushing Docker updates

Once your modifications work with the local Docker image:

1. **Tag the image:**
   ```bash
   docker tag longgwas-local-test yourusername/longgwas:v3
   ```

2. **Push to DockerHub:**
   ```bash
   docker push yourusername/longgwas:v3
   ```

3. **Update `nextflow.config`:**
   ```groovy
   process.container = 'yourusername/longgwas:v3'
   ```

### Current Docker Images

- ✅ **`amcalejandro/longgwas:v2`**: Stable production version (built from original `Dockerfile`)
- 🚧 **`Dockerfile.ubuntu22`**: Modern Ubuntu 22.04 build with optimizations (in testing)

## Documentation

### For Users
- � **[Getting Started](docs/getting_started.md)**: Detailed quickstart guide
- 📋 **[Parameters](docs/parameters.md)**: Description of all pipeline parameters
- 📊 **[File Formats](docs/file_formats.md)**: Input/output file format specifications
- 📝 **[Examples](docs/examples.md)**: Example workflows and use cases
- 🔧 **[Configuration](docs/config.md)**: Detailed Nextflow configuration guide
- 💻 **[Software](docs/software.md)**: List of included bioinformatics tools

### For Developers
- � **[Docker Improvements](docs/DOCKER_IMPROVEMENTS.md)**: Complete guide to Dockerfile.ubuntu22 improvements, pandas/numpy fixes, and build optimization
- 🏗️ **[Repository Guide](docs/REPOSITORY_GUIDE.md)**: Complete architecture and code organization guide
- ⚡ **[Quick Reference](docs/QUICK_REFERENCE.md)**: Fast lookup for common tasks and troubleshooting

## Architecture Notes

### Nextflow bin/ Auto-Mounting
Nextflow automatically mounts your project's `bin/` directory into Docker containers at `/workspace/bin/` and adds it to PATH. This means:
- Scripts in `bin/` override any copies inside the Docker image
- You can modify scripts without rebuilding Docker
- The Docker image doesn't need to include `bin/` scripts (they're mounted at runtime)

### Reference Files
The Docker image includes large reference files (~900 MB) required for the pipeline:
- `hg38.fa.gz`: Human genome reference (for normalization)
- `hg19ToHg38.over.chain.gz`: Liftover chain file (hg19 → hg38)
- `hg18ToHg38.over.chain.gz`: Liftover chain file (hg18 → hg38)
- Ancestry reference panel (1000 Genomes)

These are built into the Docker image to ensure availability without external downloads during pipeline execution.

## Troubleshooting

### Common Issues

**1. Permission denied on scripts**
```bash
chmod +x bin/*.py bin/*.sh
```

**2. Platform mismatch on Apple Silicon**
Always use `--platform linux/amd64` when building:
```bash
docker build --platform linux/amd64 -f Dockerfile.ubuntu22 -t longgwas-local-test .
```

**3. Missing Python modules**
If you see `ModuleNotFoundError`, the Docker image needs to be rebuilt with the missing package added to `Dockerfile.ubuntu22`.

**4. liftOver errors**
Ensure the Docker image was built for `linux/amd64` platform (not `arm64`).

## Citation

If you use this pipeline, please cite:
- [Original publication information]

## License

[License information]

## Support

For issues and questions:
- 🐛 **Bug reports**: [GitHub Issues](https://github.com/hirotaka-i/long-gwas-pipeline/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/hirotaka-i/long-gwas-pipeline/discussions) 