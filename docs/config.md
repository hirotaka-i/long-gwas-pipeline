# Nextflow Configuration & Profiles

Complete guide to pipeline configuration and execution profiles.

---

## Table of Contents

1. [Overview](#overview)
2. [Configuration Files](#configuration-files)
3. [Execution Profiles](#execution-profiles)
4. [Resource Management](#resource-management)
5. [Environment Variables](#environment-variables)
6. [Profile Details](#profile-details)
7. [Custom Configuration](#custom-configuration)

---

## Overview

The longitudinal GWAS pipeline uses Nextflow's configuration system to manage:
- **Execution environments** (local, HPC, cloud)
- **Resource allocation** (CPU, memory, disk)
- **Containerization** (Docker, Singularity)
- **File paths** (inputs, outputs, cache)

**Configuration is loaded from:**
1. `nextflow.config` (in repository)
2. `params.yml` (your parameter file via `-params-file`)
3. Command line (`--parameter value`)

**Priority:** Command line > params.yml > nextflow.config

---

## Configuration Files

### nextflow.config

Main configuration file defining profiles and defaults.

**Location:** Repository root (`long-gwas-pipeline/nextflow.config`)

**Key sections:**
```groovy
// Default parameters
params {
  input = null
  phenofile = null
  covarfile = null
  // ... more defaults
}

// Execution profiles
profiles {
  standard { /* local execution */ }
  localtest { /* local Docker testing */ }
  adwb { /* Azure Data Workbench */ }
  biowulf { /* NIH Biowulf HPC */ }
  gls { /* Google Life Sciences */ }
  gcb { /* Google Cloud Batch */ }
}

// Process resource labels
process {
  withLabel: small { /* light tasks */ }
  withLabel: medium { /* standard tasks */ }
  withLabel: large_mem { /* memory-intensive */ }
}
```

### params.yml

User-specific parameter file (recommended approach).

**Create your own:** `my_analysis.yml`

```yaml
# Input files
input: "data/chr*.vcf.gz"
phenofile: "phenotypes/bmi.tsv"
covarfile: "covariates/baseline.tsv"

# Analysis settings
linear_flag: true
assembly: hg19
dataset: my_study_2025

# QC parameters
r2thres: 0.3
minor_allele_freq: "0.05"
kinship: "0.177"
```

**Usage:**
```bash
nextflow run main.nf -profile standard -params-file my_analysis.yml
```

---

## Execution Profiles

### What Are Profiles?

Profiles are **execution environment presets** that define:
- Where the pipeline runs
- What resources are available
- How containerization works
- Where files are stored

### Available Profiles

| Profile | Environment | Container | Use Case |
|---------|-------------|-----------|----------|
| `standard` | Local (default) | Docker | Development, testing, small datasets |
| `localtest` | Local | Docker (custom) | Testing Docker image changes |
| `adwb` | Azure Data Workbench | Docker | All of Us platform |
| `biowulf` | NIH Biowulf HPC | Singularity (SLURM) | HPC cluster - submits SLURM jobs |
| `biowulflocal` | NIH Biowulf HPC | Singularity (local) | HPC cluster - within allocated resources |
| `gls` | Google Cloud | Docker | Google Life Sciences API |
| `gcb` | Google Cloud | Docker | Google Cloud Batch |

### Using Profiles

**Single profile:**
```bash
nextflow run main.nf -profile standard -params-file params.yml

# From Biowulf login node (submits SLURM jobs)
nextflow run main.nf -profile biowulf -params-file params.yml

# From Biowulf allocated node (sinteractive)
nextflow run main.nf -profile biowulflocal -params-file params.yml
```

**Multiple profiles (combine configurations):**
```bash
nextflow run main.nf -profile standard,docker
```

**Default:** If no `-profile` specified, `standard` is used.

---

## Resource Management

### Process Labels

The pipeline uses labels to assign appropriate resources to different task types:

#### `small` - Light Tasks
**Used for:** GLM computations per chunk, data formatting

**Resources:**
- **standard profile:** 2 CPUs, 6 GB RAM
- **adwb profile:** 2 CPUs, 6 GB RAM
- **biowulf profile:** 2 CPUs, 6 GB RAM

**Tasks:** Model fitting, simple transformations

#### `medium` - Standard Tasks
**Used for:** QC processing, PCA computation, file merging

**Resources:**
- **standard profile:** 4 CPUs, 12 GB RAM
- **adwb profile:** 4 CPUs, 12 GB RAM
- **biowulf profile:** 8 CPUs, 60 GB RAM

**Tasks:** Genetic QC, bcftools operations, plink operations

#### `large_mem` - Memory-Intensive Tasks
**Used for:** Genome-wide operations, large file processing

**Resources:**
- **standard profile:** 4 CPUs, 12 GB RAM
- **adwb profile:** 10 CPUs, 70 GB RAM
- **biowulf profile:** 10 CPUs, 115 GB RAM

**Tasks:** Manhattan plot generation, large VCF processing

### Adjusting Resources

**Per profile in nextflow.config:**
```groovy
profiles {
  myprofile {
    process {
      withLabel: medium {
        cpus = 8
        memory = '32 GB'
      }
    }
  }
}
```

**Override at runtime:**
```bash
nextflow run main.nf --cpus 8 --memory '32 GB'
```

---

## Environment Variables

### Standard Environment Variables

Set within profiles to control paths and behavior:

| Variable | Purpose | Example |
|----------|---------|---------|
| `RESOURCE_DIR` | Reference files location | `/srv/GWAS-Pipeline/References` |
| `OUTPUT_DIR` | Results output directory | `$PWD/files/longGWAS_pipeline/results` |
| `STORE_DIR` | Cache directory | `$PWD/files/longGWAS_pipeline/results/cache` |
| `ADDI_QC_PIPELINE` | QC script path (in container) | `/usr/src/ADDI-GWAS-QC-pipeline/addi_qc_pipeline.py` |

### Setting Environment Variables

**In profile:**
```groovy
env {
  RESOURCE_DIR = '/path/to/references'
  OUTPUT_DIR = '/path/to/results'
}
```

**At runtime:**
```bash
export RESOURCE_DIR=/my/references
nextflow run main.nf -profile standard
```

---

## Profile Details

### 1. `standard` Profile (Default)

**Best for:** Local development, testing, small datasets

**Configuration:**
```groovy
standard {
  env {
    RESOURCE_DIR = "$PWD/files"
    OUTPUT_DIR = "$PWD/files/longGWAS_pipeline/results"
    STORE_DIR = "$PWD/files/longGWAS_pipeline/results/cache"
  }
  process {
    container = 'amcalejandro/longgwas:v2'
    cpus = 2
    withLabel: small { cpus = 2; memory = '6 GB' }
    withLabel: medium { cpus = 4; memory = '12 GB' }
    withLabel: large_mem { cpus = 4; memory = '12 GB' }
  }
  docker {
    enabled = true
    temp = 'auto'
  }
}
```

**Key features:**
- Uses official Docker image from DockerHub
- Relative paths (`$PWD/files`)
- Moderate resources for desktop/laptop
- Auto-pulls Docker image on first run

**Requirements:**
- Docker installed and running
- At least 12 GB RAM available
- 4 CPU cores recommended

**Usage:**
```bash
nextflow run main.nf -profile standard -params-file params.yml
```

---

### 2. `localtest` Profile

**Best for:** Testing custom Docker images before pushing to DockerHub

**Configuration:**
```groovy
localtest {
  env {
    RESOURCE_DIR = "/srv/GWAS-Pipeline/References"
    OUTPUT_DIR = "$PWD/files/longGWAS_pipeline/results"
    STORE_DIR = "$PWD/files/longGWAS_pipeline/results/cache"
  }
  process {
    container = 'longgwas-local-test'  // Local image
    cpus = 2
    withLabel: small { cpus = 2; memory = '6 GB' }
    withLabel: medium { cpus = 4; memory = '12 GB' }
    withLabel: large_mem { cpus = 4; memory = '12 GB' }
  }
  docker {
    enabled = true
    temp = 'auto'
  }
}
```

**Key features:**
- Uses locally built Docker image
- Same resource allocation as `standard`
- Reference files inside Docker container
- bin/ scripts auto-mounted from local directory

**Requirements:**
- Build Docker image first:
  ```bash
  docker build --platform linux/amd64 -f Dockerfile.ubuntu22 -t longgwas-local-test .
  ```

**Usage:**
```bash
nextflow run main.nf -profile localtest -params-file params.yml
```

**Note for Apple Silicon users:** Always use `--platform linux/amd64` flag.

---

### 3. `adwb` Profile

**Best for:** All of Us Data Workbench (Azure platform)

**Configuration:**
```groovy
adwb {
  env {
    RESOURCE_DIR = '/files'
    OUTPUT_DIR = '/files/longGWAS_pipeline/results'
    STORE_DIR = '/files/longGWAS_pipeline/cache'
  }
  process {
    container = 'gwas-pipeline'
    withLabel: large_mem {
      cpus = 10
      memory = '70 GB'
    }
  }
  executor {
    cpus = 20
    name = 'local'
    memory = '75 GB'
  }
  docker.enabled = true
}
```

**Key features:**
- Absolute paths (Azure mounts)
- More resources (10 CPUs, 70 GB for large tasks)
- Pre-loaded Docker image
- Total limits: 20 CPUs, 75 GB

**Usage:**
```bash
nextflow run main.nf -profile adwb -params-file params.yml
```

---

### 4. `biowulf` Profile

**Best for:** NIH Biowulf HPC cluster - submitting SLURM jobs from login node

**Preparation:**
We need to use Singularity instead of Docker on Biowulf. First, convert the Docker image to Singularity:

```bash
mkdir -p $LONG_GWAS_DIR/Docker
cd $LONG_GWAS_DIR/Docker
singularity build gwas-pipeline_survival.sif docker://hirotakai/longgwas:v2.0.1
```

**Configuration:**
```groovy
biowulf {
  env {
    OUTPUT_DIR = "$LONG_GWAS_DIR/$PROJECT_NAME/results"
    STORE_DIR = "$LONG_GWAS_DIR/$PROJECT_NAME/Cache"
  }
  process {
    executor = 'slurm'
    queue = 'norm'
    container = "$LONG_GWAS_DIR/Docker/gwas-pipeline_survival.sif"
    
    withLabel: small {
      cpus = 2
      memory = '5 GB'
      time = '2h'
    }
    withLabel: large_mem {
      cpus = 10
      memory = '115 GB'
      time = '8h'
    }
  }
  executor {
    name = 'slurm'
    pollInterval = '2 min'
    queueSize = 200
    queueStatInterval = '5 min'
    submitRateLimit = '6/1min'
  }
  singularity {
    enabled = true
    autoMounts = true
    runOptions = "--bind $PWD --env APPEND_PATH=$PWD/bin"
  }
}
```

**Key features:**
- Uses **SLURM executor** - each task submits a separate SLURM job
- Jobs run on compute nodes (not login node)
- Follows [Biowulf's official recommendations](https://hpc.nih.gov/apps/nextflow.html)
- Environment variables: Set `LONG_GWAS_DIR` and `PROJECT_NAME`
- Much more memory (115 GB for large tasks)
- Time limits prevent runaway jobs

**Setup:**
```bash
# From login node (NOT sinteractive!)
export LONG_GWAS_DIR=/data/username/gwas
export PROJECT_NAME=my_study
module load nextflow singularity
```

**Usage:**
```bash
# Run from login node - will submit SLURM jobs
nextflow run main.nf -profile biowulf -params-file params.yml

# Check submitted jobs
squeue -u $USER
```

### 5. `biowulflocal` Profile

**Best for:** Running within already allocated Biowulf resources (sinteractive or sbatch)

**Configuration:**
```groovy
biowulflocal {
  env {
    OUTPUT_DIR = "$LONG_GWAS_DIR/$PROJECT_NAME/results"
    STORE_DIR = "$LONG_GWAS_DIR/$PROJECT_NAME/Cache"
  }
  process {
    executor = 'local'
    container = "$LONG_GWAS_DIR/Docker/gwas-pipeline_survival.sif"
    maxForks = 2  // Limits parallel tasks to prevent overload
    
    withLabel: large_mem {
      cpus = 2
      memory = '50 GB'
    }
  }
  singularity {
    enabled = true
    autoMounts = true
  }
}
```

**Key features:**
- Uses **local executor** - runs on your allocated node
- Does NOT submit new SLURM jobs
- `maxForks = 2` prevents spawning too many processes
- Suitable for interactive testing

**Setup:**
```bash
# Allocate resources first
sinteractive --cpus-per-task=4 --mem=50g

# Then run pipeline
module load nextflow singularity
export LONG_GWAS_DIR=$PWD # or /path/to/working/directory
export PROJECT_NAME=my_study
```

**Usage:**
```bash
# Run within your allocated resources
nextflow run main.nf -profile biowulflocal -params-file params.yml
```

---

### 5. `gls` Profile

**Best for:** Google Cloud Platform (Life Sciences API)

**Configuration:**
```groovy
gls {
  env {
    RESOURCE_DIR = 'gs://long-gwas/nextflow-test/files'
    OUTPUT_DIR = 'gs://long-gwas/nextflow-test/files/results'
    STORE_DIR = 'gs://long-gwas/nextflow-test/files/cache'
  }
  workDir = 'gs://long-gwas/nextflow-test/workdir'
  process.executor = 'google-lifesciences'
  process.container = 'amcalejandro/longgwas:v2'
  
  google.location = 'us-central1'
  google.project = 'your-project-id'
  google.region  = 'us-central1'
  
  process.cpus = 8
  process.memory = '32 GB'
  process.disk = '30 GB'
}
```

**Key features:**
- Cloud storage paths (`gs://`)
- Automatic VM provisioning
- Pay-per-use pricing
- Scalable resources

**Setup:**
1. Enable Google Life Sciences API
2. Configure `google.project` with your project ID
3. Set up Cloud Storage bucket

**Usage:**
```bash
nextflow run main.nf -profile gls -params-file params.yml
```

---

### 6. `gcb` Profile

**Best for:** Google Cloud Platform (Cloud Batch API - newer)

**Configuration:**
```groovy
gcb {
  env {
    RESOURCE_DIR = 'gs://long-gwas/nextflow-test/files'
    OUTPUT_DIR = 'gs://long-gwas/nextflow-test/files/results'
  }
  workDir = 'gs://long-gwas/nextflow-test/workdir'
  process.executor = 'google-batch'
  process.container = 'amcalejandro/longgwas:v2'
  
  google.location = 'us-central1'
  google.project = 'your-project-id'
  google.region  = 'us-central1'
  google.batch.bootDiskSize = '20GB'
  
  process.cpus = 8
  process.memory = '32 GB'
}
```

**Key features:**
- Newer Google Cloud Batch API
- Better integration with GCP
- Improved job scheduling

---

## Custom Configuration

### Creating a Custom Profile

Add to `nextflow.config`:

```groovy
profiles {
  myprofile {
    env {
      RESOURCE_DIR = '/my/references'
      OUTPUT_DIR = '/my/results'
    }
    process {
      container = 'my-custom-image:latest'
      cpus = 16
      memory = '64 GB'
      
      withLabel: small {
        cpus = 4
        memory = '8 GB'
      }
      
      withLabel: medium {
        cpus = 8
        memory = '32 GB'
      }
      
      withLabel: large_mem {
        cpus = 16
        memory = '64 GB'
      }
    }
    
    docker {
      enabled = true
      runOptions = '-v /my/data:/data'
    }
  }
}
```

**Usage:**
```bash
nextflow run main.nf -profile myprofile -params-file params.yml
```

### Overriding Configuration

**Override specific parameters:**
```bash
nextflow run main.nf -profile standard \
  --cpus 8 \
  --memory '32 GB' \
  -params-file params.yml
```

**Use custom config file:**
```bash
nextflow run main.nf -c my_custom.config -params-file params.yml
```

---

## Troubleshooting

### Common Configuration Issues

**1. Container not found**
```
Error: Unable to pull Docker image
```
**Solution:** Check Docker is running, or build local image for `localtest`

**2. Out of memory**
```
Error: Process exceeded available memory
```
**Solution:** Increase memory in profile or use profile with more resources

**3. Permission denied**
```
Error: Cannot write to directory
```
**Solution:** Check file permissions, ensure paths are writable

**4. Environment variable not set**
```
Error: LONG_GWAS_DIR not defined
```
**Solution:** Export required environment variables before running

### Debugging Configuration

**View effective configuration:**
```bash
nextflow config -profile standard
```

**Show all parameters:**
```bash
nextflow config -profile standard -flat
```

**Check specific profile:**
```bash
nextflow config -profile biowulf -show-profiles
```

---

## Best Practices

### Profile Selection

✅ **Do:**
- Use `standard` for local testing
- Use `localtest` when developing Docker changes
- Use HPC profiles (`biowulf`) for large datasets
- Use cloud profiles (`gls`, `gcb`) for scalability

❌ **Don't:**
- Mix incompatible profiles
- Use `standard` for large production runs
- Forget to set required environment variables

### Resource Allocation

✅ **Do:**
- Start with conservative resources
- Monitor memory usage
- Adjust based on dataset size
- Use `-resume` to restart failed jobs

❌ **Don't:**
- Over-allocate resources (wastes money/time)
- Under-allocate (causes failures)
- Ignore error messages

### File Paths

✅ **Do:**
- Use absolute paths in HPC/cloud profiles
- Use `$PWD` for local profiles
- Ensure paths are writable
- Keep data on fast storage

❌ **Don't:**
- Hard-code personal paths in shared configs
- Use network drives for work directory
- Mix local and cloud storage paths

---

## See Also

- **[Parameters](parameters.md)**: Complete parameter reference
- **[Examples](examples.md)**: Usage examples with different profiles
- **[Quick Reference](QUICK_REFERENCE.md)**: Fast troubleshooting
- **[Docker Improvements](DOCKER_IMPROVEMENTS.md)**: Container details
