# longitudinal-GWAS-pipeline

Repository for Nextflow pipeline to perform GWAS with longitudinal capabilities

## Overview

This pipeline supports three types of genetic association analyses:
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
   git clone -b v2 https://github.com/hirotaka-i/long-gwas-pipeline.git
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

*TIPS*: When first attempt failed, you can resume where it failed with
```
nextflow run main.nf -profile standard -params-file params.yml -resume
```
Also, you can display the flowchart. 
```
nextflow run main.nf -profile standard -params-file params.yml -with-dag flowchart.html
```

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

## Quick Tips

### For Users

- Use `standard` profile for production analyses
- See [Examples](docs/examples.md) for common workflows
- Check [Parameters](docs/parameters.md) for all configuration options

### For Developers

Scripts in `bin/` and workflow files (`*.nf`) can be edited directly - changes take effect immediately without rebuilding Docker.

For package installations or Docker modifications, see the [Developer's Guide](docs/DEVELOPER_GUIDE.md).

> **Apple Silicon users**: Always use `--platform linux/amd64` when building Docker images

## Documentation

### For Users
- 📋 **[Parameters](docs/parameters.md)**: All pipeline parameters and options
- 📊 **[File Formats](docs/file_formats.md)**: Input/output file specifications
- 📝 **[Examples](docs/examples.md)**: Example workflows and use cases
- 🔧 **[Configuration](docs/config.md)**: Profile and resource configuration
- ⚡ **[Quick Reference](docs/QUICK_REFERENCE.md)**: Fast lookup for common tasks

### For Developers
- 🚀 **[Developer's Guide](docs/DEVELOPER_GUIDE.md)**: Complete development workflow, Docker builds, testing, and deployment
- 🐳 **[Docker Improvements](docs/DOCKER_IMPROVEMENTS.md)**: Dockerfile.ubuntu22 architecture and optimizations
- 🏗️ **[Repository Guide](docs/REPOSITORY_GUIDE.md)**: Code organization and architecture
- 📖 **[Reference Files Setup](docs/REFERENCE_FILES_SETUP.md)**: Managing genome references and resources

## Architecture Notes

### Nextflow bin/ Auto-Mounting
Nextflow automatically mounts your project's `bin/` directory into containers and adds it to PATH. This means you can modify Python, R, and shell scripts without rebuilding Docker. See the [Developer's Guide](docs/DEVELOPER_GUIDE.md) for details.

### Reference Files
The Docker image includes large reference files (~900 MB) required for the pipeline:
- `hg38.fa.gz`: Human genome reference
- `hg19ToHg38.over.chain.gz` / `hg18ToHg38.over.chain.gz`: Liftover chain files
- Ancestry reference panel (1000 Genomes)

See [Reference Files Setup](docs/REFERENCE_FILES_SETUP.md) for details.

## Troubleshooting

### Common Issues

**Permission denied on scripts**
```bash
chmod +x bin/*.py bin/*.sh bin/*.R
```

**Platform mismatch on Apple Silicon**
```bash
docker build --platform linux/amd64 -f Dockerfile.ubuntu22 -t longgwas-local-test .
```

**Pipeline errors**
Check the detailed logs:
```bash
cat .nextflow.log
cat work/XX/XXXXXXXXX/.command.log
```

For complete troubleshooting guide, see [Developer's Guide](docs/DEVELOPER_GUIDE.md#troubleshooting).

## Citation

If you use this pipeline, please cite:
- [Original publication information]

## License

[License information]

## Support

For issues and questions:
- 🐛 **Bug reports**: [GitHub Issues](https://github.com/hirotaka-i/long-gwas-pipeline/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/hirotaka-i/long-gwas-pipeline/discussions)
