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
2. **Extract example:**
   ```bash
   tar -xzf example/genotype/example_data.tar.gz -C example/genotype/
   ```
3. **Run the pipeline:**   
   If docker is available, run:
   ```bash
   nextflow run main.nf -profile standard -params-file params.yml
   ```
   
   - `main.nf`: Main Nextflow script
   - `-profile`: Environment configuration (see Profiles below)
   - `params.yml`: Parameter settings file

    **TIPS**: the following option will also creates some reports
    ```
    nextflow run main.nf -profile standard -params-file params.yml \
    --report report.html\
    --timeline timeline.html\
    --trace trace.txt\
    --dag flowchart.png
    ```
## Profiles

The pipeline supports multiple execution profiles for different environments, such as local, HPC, and cloud setups. Profiles define resource allocation, containerization, and execution settings.

For detailed information on available profiles and their configurations, see the [Configuration Guide](docs/config.md).

### Example Usage

- **Standard Profile** (local execution with Docker):
  ```bash
  nextflow run main.nf -profile standard -params-file params.yml
  ```

- **Biowulf Profile** (HPC execution with Singularity):
  ```bash
  nextflow run main.nf -profile biowulf -params-file params.yml
  ```

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

### For Developers
- 🚀 **[Developer's Guide](docs/DEVELOPER_GUIDE.md)**: Complete development workflow, Docker builds, testing, and deployment
- 🐳 **[Docker Improvements](docs/DOCKER_IMPROVEMENTS.md)**: Dockerfile.ubuntu22 architecture and optimizations
- 🏗️ **[Repository Guide](docs/REPOSITORY_GUIDE.md)**: Code organization, architecture, and quick reference

## Architecture Notes

### Nextflow bin/ Auto-Mounting
Nextflow automatically mounts your project's `bin/` directory into containers and adds it to PATH. This means you can modify Python, R, and shell scripts without rebuilding Docker. See the [Developer's Guide](docs/DEVELOPER_GUIDE.md) for details.

### Reference Files
The Docker image includes large reference files (~900 MB) required for the pipeline:
- `hg38.fa.gz`: Human genome reference
- `hg19ToHg38.over.chain.gz` / `hg18ToHg38.over.chain.gz`: Liftover chain files
- Ancestry reference panel (1000 Genomes)

These files are automatically mounted from the container at runtime.

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
