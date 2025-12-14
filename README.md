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

## How to start

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

### Clone Repository

```bash
git clone https://github.com/hirotaka-i/long-gwas-pipeline.git
cd long-gwas-pipeline
```


#### Directory Structure

The pipeline uses a standardized directory structure across all profiles:

```
$STORE_ROOT/
└── $PROJECT_NAME/
    ├── cache/           # Persistent cache for genetic QC (p1_run_cache/)
    ├── results/         # Final GWAS results and plots
    └── work/            # Nextflow work directory (temporary)
```

**Environment variables:**
- `STORE_ROOT`: Root directory for all pipeline data - can be local path or GCS bucket (default: `$PWD`)
- `PROJECT_NAME`: Unique identifier for your project (default: `unnamed_project`)

**Other important folders**

Nextflow automatically mounts your project's `bin/` and `modules/` directory into containers and adds it to PATH. This means you can modify Python, R, shell and workflow scripts without rebuilding Docker. See the [Developer's Guide](docs/DEVELOPER_GUIDE.md) for details.

- `bin/`: Pipeline scripts (auto-mounted into containers)
- `modules/`: Nextflow modules for each pipeline stage
- `conf/`: Configuration profiles
- `example/`: Example input genetics and clinical data for testing.
- `References/`: Reference genome and chain files

```
<reference_dir>/ # Directory specified by `reference_dir` parameter. Default: `./References/`
├── Genome/
│   ├── hg38.fa.gz
│   ├── hg38.fa.gz.fai
│   ├── hg38.fa.gz.gzi
│   ├── hg19.fa.gz
│   ├── hg19.fa.gz.fai
│   └── hg19.fa.gz.gzi
└── liftOver/
    ├── hg19ToHg38.over.chain.gz
    └── hg18ToHg38.over.chain.gz
```

These files are required for variant liftover and alignment during QC steps. When not available, the pipeline downloads them automatically as needed (takes some time). 

## Running the Pipeline
We use profiles to configure different execution environments (local, cloud, HPC). See [Configuration Guide](docs/config.md) for details. Paramaters can be set via YAML files (see `conf/examples/`).

#### Set Environment Variables
```
export STORE_ROOT='path/to/store_root'    # Default $PWD. Can be GCS bucket for cloud runs
export PROJECT_NAME='my_gwas_test'        # Unique project identifier
```

#### Preparation of `Reference` folder. 
This is optional, if we have the folders already, skip this step and specify the path via `reference_dir` parameter)
```bash
# hg19 example
bin/download_references.sh hg19 References
```


### Local Execution (from cloned repository)

```bash
# Basic test run with example data
nextflow run main.nf -profile standard -params-file conf/examples/test_data.yml
```
Now you can customize `params.yml` with your own input files and parameters. see `conf/examples/` for more examples.

### Local Execution with local Docker Image

```bash
# Build local Docker image first
docker build --platform linux/amd64 -f Dockerfile.ubuntu22 -t longgwas-local-test .
# Run with localtest profile
nextflow run main.nf -profile localtest -params-file conf/examples/test_data.yml
```

### Biowulf
First, build the Singularity image
```bash
mkdir -p ./Docker
cd ./Docker
singularity build long-gwas-pipeline.sif docker://ghcr.io/hirotaka-i/long-gwas-pipeline:0.1.0
cd ..
# Submit the slurm job from the main directory
nextflow run main.nf -profile biowulf -params-file conf/examples/test_data.yml
# or local
nextflow run main.nf -profile biowulflocal -params-file conf/examples/test_data.yml
```

### Verily Workbench / Google Cloud Batch
```bash
# From within Verily Workbench VM
export STORE_ROOT='gs://<your-bucket-name>'  # Bucket you created above
export PROJECT_NAME='testrun'                # Any name for your project
export TOWER_ACCESS_TOKEN='<your-token>'    # Get from https://cloud.seqera.io/tokens
cd ~/repos/long-gwas-pipeline
git pull origin main  # Update to latest code
wb nextflow run main.nf -profile gcb -params-file conf/examples/test_data.yml -with-tower
```
See the [Verily Workbench Setup Guide](docs/vwb_setup.md) for complete instructions.

[Configuration Guide](docs/config.md).


### (In progress) Remote Execution - no clone needed)

```bash
# Run from GitHub main branch
nextflow run hirotaka-i/long-gwas-pipeline -r main -profile standard -params-file myparams.yml

# Run specific version/tag
nextflow run hirotaka-i/long-gwas-pipeline -r v0.1.0 -profile standard -params-file conf/examples/test_data.yml

# Latest release
nextflow run hirotaka-i/long-gwas-pipeline -r latest -profile standard -params-file myparams.yml
```

## Documentation
- 📋 **[Parameters](docs/parameters.md)**: All pipeline parameters and options
- 📊 **[File Formats](docs/file_formats.md)**: Input/output file specifications
- 🔧 **[Configuration](docs/config.md)**: Profile and resource configuration
- ☁️ **[Verily Workbench Setup](docs/vwb_setup.md)**: Running on Verily Workbench with Google Cloud Batch


## TIPS
* `-with-dag flowchart.png` will also creates workflow DAG diagram in `flowchart.png`. 
* `-resume` flag can be used to resume failed runs.
* `-with-tower` flag can be used to monitor runs on Seqera Tower.

### More about Caching and Resume Behavior

The pipeline uses **two complementary caching strategies** that serve different purposes:

#### 1. Nextflow `-resume` (Task-level caching)
Nextflow automatically caches completed tasks in the `work/` directory. Use `-resume` to skip successfully completed steps after a failure:

```bash
nextflow run main.nf -profile standard -params-file params.yml -resume
```

**What is `work/` directory?**
- Stores temporary task execution files (intermediate files, scripts, logs)
- Used by Nextflow's built-in resume mechanism
- Location: `${STORE_ROOT}/${PROJECT_NAME}/work/`

**How it works:**
- Only **failed or incomplete** tasks are re-run
- **Successful parallel tasks are skipped** (e.g., if chr17 and chr18 succeeded but chr19 failed, only chr19 re-runs)
- Cache persists until manually deleted
- **Limitation:** Cache is invalidated if you change input files, parameters, or code

**Cleanup:**
```bash
# Safe to delete after successful run to save space
rm -rf ${STORE_ROOT}/${PROJECT_NAME}/work/
```

#### 2. Persistent Cache (`cache/p1_run_cache/`)
The pipeline stores processed genetic QC outputs in `${STORE_ROOT}/${PROJECT_NAME}/cache/p1_run_cache/` for **cross-session reuse**.

**What is `cache/` directory?**
- Stores persistent QC results that survive across different pipeline runs
- Independent from Nextflow's `-resume` mechanism
- Location: `${STORE_ROOT}/${PROJECT_NAME}/cache/`
- **Keep this directory** - contains valuable preprocessed genetic data

**Key difference from `work/`:**
| Feature | `work/` (Nextflow) | `cache/` (Pipeline) |
|---------|-------------------|---------------------|
| **Purpose** | Resume failed runs | Reuse QC across runs |
| **Checked by** | `-resume` flag | Pipeline logic (main.nf) |
| **Lifetime** | Single run session | Multiple runs |
| **Safe to delete** | Yes (after success) | No (loses QC data) |

**Current behavior (cumulative mode):**
```bash
# First run: Process chr1-3
export PROJECT_NAME="genome_wide_study"
input: "genotype/chr{1,2,3}.vcf"
# → Outputs saved to cache/p1_run_cache/
# → Final analysis includes: chr1, chr2, chr3

# Second run: Process chr17-19 (same PROJECT_NAME)
input: "genotype/chr{17,18,19}.vcf"
# → chr1-3 automatically loaded from cache
# → chr17-19 newly processed
# → Final analysis includes: chr1, chr2, chr3, chr17, chr18, chr19 (all 6)
```

**Why this happens:**
The pipeline concatenates ALL cached files with newly processed files (see `main.nf` line ~168: `.concat(cache)`). This enables **incremental genome-wide analysis** where each run builds on previous chromosomes.

**Practical example:**
```bash
# Scenario 1: Pipeline fails mid-run
nextflow run main.nf -profile gcb -params-file params.yml
# ... fails at step 5/10
nextflow run main.nf -profile gcb -params-file params.yml -resume  
# → Resumes from step 5 using work/ directory

# Scenario 2: Fresh run, but reuse previous QC
rm -rf ${STORE_ROOT}/${PROJECT_NAME}/work/  # Delete temp files
nextflow run main.nf -profile gcb -params-file params.yml
# → Fresh Nextflow run (no -resume)
# → BUT cache/ still has QC data from previous session
# → Skips expensive QC steps automatically
```

**Important considerations:**
- ✅ **Use cumulative mode** if you're building a complete genome-wide dataset over multiple runs
- ⚠️ **Beware** if you want to analyze only specific chromosomes in isolation:
  - Cached chromosomes from previous runs will be included in downstream analyses (PCA, GWAS, results)
  - To analyze chr17-19 only, use a different `PROJECT_NAME` or manually remove cache files
- 💡 **Tip:** Use different `PROJECT_NAME` values for different chromosome sets to maintain separate caches

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



## Appendix for Docker Image Maintenance
Docker images are built automatically via GitHub Actions. See [.github/DOCKER_BUILDS.md](.github/DOCKER_BUILDS.md) for details.

Local Docker image maintenance instructions are below.
# Weekly maintenance - safe - keeps tagged images, removes build cache
docker system prune -f

# After major builds - more aggressive - removes all unused images
docker builder prune -a -f

# Nuclear option - rarely - use with caution
docker system prune -a -f --volumes  # Only when you know what you're doing