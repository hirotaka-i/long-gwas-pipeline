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

### Directory Structure

The pipeline uses a standardized directory structure across all profiles:

```
$LONG_GWAS_DIR/
└── $PROJECT_NAME/
    ├── cache/           # Persistent cache for genetic QC (p1_run_cache/)
    ├── results/         # Final GWAS results and plots
    └── work/            # Nextflow work directory (temporary, cloud profiles only)
```

**Environment variables:**
- `LONG_GWAS_DIR`: Root directory for all pipeline data (default: `$PWD`)
- `PROJECT_NAME`: Unique identifier for your project (default: `unnamed_project`)

**Examples:**
```bash
# Local execution (defaults to current directory)
nextflow run main.nf -profile standard -params-file params.yml
# → Output: $PWD/unnamed_project/{cache,results}

# Set custom project name
export PROJECT_NAME="my_gwas_2025"
nextflow run main.nf -profile standard -params-file params.yml
# → Output: $PWD/my_gwas_2025/{cache,results}

# Custom base directory and project name
export LONG_GWAS_DIR="/data/gwas_projects"
export PROJECT_NAME="parkinsons_study"
nextflow run main.nf -profile standard -params-file params.yml
# → Output: /data/gwas_projects/parkinsons_study/{cache,results}

# Biowulf HPC
export LONG_GWAS_DIR="/data/$USER/gwas"
export PROJECT_NAME="cohort_analysis"
nextflow run main.nf -profile biowulf -params-file params.yml
# → Output: /data/$USER/gwas/cohort_analysis/{cache,results}

# Google Cloud
export LONG_GWAS_DIR="gs://my-bucket/gwas"
export PROJECT_NAME="multi_cohort_2025"
nextflow run main.nf -profile gls -params-file params.yml
# → Output: gs://my-bucket/gwas/multi_cohort_2025/{cache,results,work}
```

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
NOTE: Options are set in the `params.yml` file but the command line example below will override them. (not recommended for production)

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

### Caching and Resume Behavior

The pipeline uses **two complementary caching strategies**:

#### 1. Nextflow `-resume` (Task-level caching)
Nextflow automatically caches completed tasks in the `work/` directory. Use `-resume` to skip successfully completed steps after a failure:

```bash
nextflow run main.nf -profile standard -params-file params.yml -resume
```

**How it works:**
- Only **failed or incomplete** tasks are re-run
- **Successful parallel tasks are skipped** (e.g., if chr17 and chr18 succeeded but chr19 failed, only chr19 re-runs)
- Cache is stored in `work/` directory and persists until manually deleted
- **Limitation:** Cache is invalidated if you change input files, parameters, or delete `work/`

#### 2. Persistent Cache (`p1_run_cache/`)
The pipeline stores processed genetic QC outputs in `${LONG_GWAS_DIR}/${PROJECT_NAME}/cache/p1_run_cache/` for **cross-session reuse**.

**Current behavior (cumulative mode):**
```bash
# First run: Process chr1-3
export PROJECT_NAME="genome_wide_study"
input: "genotype/chr{1,2,3}.vcf"
# → Outputs saved to $LONG_GWAS_DIR/genome_wide_study/cache/p1_run_cache/
# → Final analysis includes: chr1, chr2, chr3

# Second run: Process chr17-19 (same PROJECT_NAME)
input: "genotype/chr{17,18,19}.vcf"
# → chr1-3 automatically loaded from cache
# → chr17-19 newly processed
# → Final analysis includes: chr1, chr2, chr3, chr17, chr18, chr19 (all 6)
```

**Why this happens:**
The pipeline concatenates ALL cached files with newly processed files (see `main.nf` line ~168: `.concat(cache)`). This enables **incremental genome-wide analysis** where each run builds on previous chromosomes.

**Important considerations:**
- ✅ **Use cumulative mode** if you're building a complete genome-wide dataset over multiple runs
- ⚠️ **Beware** if you want to analyze only specific chromosomes in isolation:
  - Cached chromosomes from previous runs will be included in downstream analyses (PCA, GWAS, results)
  - To analyze chr17-19 only, use a different `PROJECT_NAME` or manually remove chr1-3 cache files
- 💡 **Tip:** Use different `PROJECT_NAME` values for different chromosome sets to maintain separate caches

**Example workflows:**

*Incremental genome-wide analysis:*
```bash
# Week 1: Process chr1-10
export PROJECT_NAME="genome_wide"
nextflow run main.nf --input "chr{1..10}.vcf" -resume

# Week 2: Add chr11-22 (final result has all 22 chromosomes)
nextflow run main.nf --input "chr{11..22}.vcf" -resume
```

*Isolated chromosome analysis:*
```bash
# Analyze chr17-19 only (use unique PROJECT_NAME)
export PROJECT_NAME="chr17_19_analysis"
nextflow run main.nf --input "chr{17,18,19}.vcf" -resume
```

**Best practices:**
- Always use `-resume` for failure recovery
- Use unique `PROJECT_NAME` values for different analyses to avoid cache conflicts
- Clear cache if you want a fresh start: `rm -rf ${LONG_GWAS_DIR}/${PROJECT_NAME}/cache/p1_run_cache/`

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
