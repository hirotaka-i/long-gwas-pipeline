# longitudinal-GWAS-pipeline

Repository for Nextflow pipeline to perform GWAS with longitudinal capabilities

## Workflow Overview

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

## Starting Guide

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


### Output Directory Structure

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

### Reference Folder Setup

The `References/` folder contains reference genome FASTA files and chain files for liftover (to Hg38). They are required to be placed in the directory specified by the `reference_dir` parameter (default: `./References/`) with the following structure. 

```
<reference_dir>/ # Directory specified by `reference_dir` parameter. Default: `./References/`
├── Genome/
│   ├── hg38.fa.gz
│   ├── hg38.fa.gz.fai
│   ├── hg19.fa.gz
│   └── hg19.fa.gz.fai
└── liftOver/
    ├── hg19ToHg38.over.chain.gz
    └── hg18ToHg38.over.chain.gz
```

Foe example, if your target genotyping data is hg19, you can download required files using the provided script:
```bash
bin/download_references.sh hg19 References
```

### Script and Module Folders

- `bin/`: Pipeline scripts (auto-mounted into containers)
- `modules/`: Nextflow modules for each pipeline stage

Nextflow automatically mounts these directory into containers and adds it to PATH. This means you can modify Python, R, shell and workflow scripts without rebuilding the container. The container is the working environment with all dependencies pre-installed but the actual scripts are in these directories.

### Example Data and Codes
`./example/` folder has the following structure
```
example/
├── genotype/          # Example VCF files (chr20-22)
├── genotype_plink/    # Example PLINK files converted from VCFs
├── covariate.csv      # Example covariate file     
├── phenotype.cs.tsv   # Example cross-sectional phenotype file
├── phenotype.lt.tsv   # Example longitudinal phenotype file (continuous)
└── phenotype.surv.tsv # Example longitudinal phenotype file (survival)
```
**Note**: long-gwas-pipeline can work with PLINK files but VCF is preferred. VCF workflow has multi-alellic splitting, ref/alt-aware liftover, imputation quality filtering and more parallelization.

### Configuration
The pipeline is highly configurable. `./conf/` folder has configuration files for profiles and parameters.
```
conf/
├── examples/    # Example parameter YAML files for different analytical modes using example dataset
├── profiles/    # Profile configurations for different execution environments (local, biowulf, gcb, etc)
├── base.config  # Base configuration file common to all profiles
└── param.config # All the paramaters with default values and explanations
```
For more details on parameters, see [conf/params.config](conf/params.config).


## Running the Pipeline


#### Set Environment Variables
```
export STORE_ROOT='path/to/store_root'    # Default $PWD. Can be GCS bucket for cloud runs
export PROJECT_NAME='my_gwas_test'        # Unique project identifier
```

#### Preparation of `Reference` folder. 


### Local Execution (from cloned repository)

```bash
# Basic test survival run with example data
nextflow run main.nf -profile standard -params-file conf/examples/test_survival.yml
```
Now you can customize `params.yml` with your own input files and parameters. see `conf/examples/` for more examples.

### Local Execution with local Docker Image

```bash
# Build local Docker image first
docker build --platform linux/amd64 -f Dockerfile.ubuntu22 -t longgwas-local-test .
# Run with localtest profile
nextflow run main.nf -profile localtest -params-file conf/examples/test_survival.yml
```

### Biowulf
First, build the Singularity image
```bash
mkdir -p ./Docker
cd ./Docker
singularity build long-gwas-pipeline.sif docker://ghcr.io/hirotaka-i/long-gwas-pipeline:0.1.0
cd ..
# Submit the slurm job from the main directory
nextflow run main.nf -profile biowulf -params-file conf/examples/test_survival.yml
# or local
nextflow run main.nf -profile biowulflocal -params-file conf/examples/test_survival.yml
```

### Verily Workbench / Google Cloud Batch
For verily Workbench, first create a GCS bucket to store your data. Then run the following commands from within the Verily Workbench VM. You would need to get a Tower access token from https://cloud.seqera.io/tokens to monitor your runs on Seqera Tower.
```bash
# From within Verily Workbench VM
export STORE_ROOT='gs://<your-bucket-name>'  # Bucket you created above
export PROJECT_NAME='testrun'                # Any name for your project
export TOWER_ACCESS_TOKEN='<your-token>'    # Get from https://cloud.seqera.io/tokens
cd ~/repos/long-gwas-pipeline
git pull origin main  # Update to latest code
wb nextflow run main.nf -profile gcb -params-file conf/examples/test_survival.yml -with-tower
```


### (In progress) Remote Execution - no clone needed)

```bash
# Run from GitHub main branch
nextflow run hirotaka-i/long-gwas-pipeline -r main -profile standard -params-file myparams.yml

```



## TIPS
* `-resume` flag can be used to resume failed runs. Data modifications and model changes can reuse the cached qced-genetics.
* `-with-dag flowchart.png` will also creates workflow DAG diagram in `flowchart.png`. 
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
The pipeline stores processed genetic QC outputs in `${STORE_ROOT}/${PROJECT_NAME}/cache/{genetic_cache}/p1_run_cache etc` for **cross-session reuse**.

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

If the pipeline fails, check the following:
- `.nextflow.log` for general errors
- Review Nextflow logs in `work/` directory for error details of the failed process.

## Support

For issues and questions:
- 🐛 **Bug reports**: [GitHub Issues](https://github.com/hirotaka-i/long-gwas-pipeline/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/hirotaka-i/long-gwas-pipeline/discussions)



## Appendix for Docker Image Maintenance
Docker images are built automatically via GitHub Actions. 

Local Docker image maintenance instructions are below.
```
# Weekly maintenance - safe - keeps tagged images, removes build cache
docker system prune -f

# After major builds - more aggressive - removes all unused images
docker builder prune -a -f

# Nuclear option - rarely - use with caution
docker system prune -a -f --volumes  # Only when you know what you're doing
```