# Nextflow Profiles - Complete Explanation

## What Are Profiles?

**Profiles** in Nextflow are **execution environments** that define:
- Where the pipeline runs (local computer, cluster, cloud)
- What resources are available (CPU, memory)
- How containerization works (Docker, Singularity)
- Where files are stored

Think of profiles as **presets** for different computing environments.

---

## How to Use Profiles

### Run with a specific profile:
```bash
# Use standard profile (default)
nextflow run main.nf

# Use specific profile
nextflow run main.nf -profile adwb
nextflow run main.nf -profile biowulf
nextflow run main.nf -profile gls
```

### Multiple profiles:
```bash
nextflow run main.nf -profile standard,docker
```

---

## Your 6 Profiles Explained

### 1. **`standard`** - Local Development (Default)

**Use when:** Running on your laptop/desktop for testing

```groovy
profiles {
  standard {
    env {
      RESOURCE_DIR = "$PWD/files"
      OUTPUT_DIR = "$PWD/files/longGWAS_pipeline/results"
      STORE_DIR = "$PWD/files/longGWAS_pipeline/results/cache"
      ADDI_QC_PIPELINE = '/usr/src/ADDI-GWAS-QC-pipeline/addi_qc_pipeline.py'
    }
    process {
      container = 'amcalejandro/longgwas:v2'
      cpus = 2
      withLabel: small {
        cpus = 2
        memory = '6 GB'
      }
      withLabel: medium {
        cpus = 4
        memory = '12 GB'
      }
      withLabel: large_mem {
        cpus = 4
        memory = '12 GB'
      }
    }
    docker {
      enabled = true
      temp = 'auto'
    }
  }
}
```

**Breakdown:**
- **env:** Environment variables
  - `RESOURCE_DIR`: Where reference files live (`$PWD/files`)
  - `OUTPUT_DIR`: Where results go
  - `STORE_DIR`: Where cached intermediate files are stored
  - `ADDI_QC_PIPELINE`: Path to QC script (inside Docker container)

- **process:** How tasks run
  - `container`: Docker image to use
  - `cpus`: Default 2 CPUs
  - **Labels** (process tags for different resource needs):
    - `small`: Quick tasks (2 CPUs, 6 GB RAM)
    - `medium`: Standard tasks (4 CPUs, 12 GB RAM)
    - `large_mem`: Memory-intensive tasks (4 CPUs, 12 GB RAM)

- **docker:** Container settings
  - `enabled = true`: Use Docker
  - `temp = 'auto'`: Auto-manage temp directories

**When to use:** Local testing, small datasets

---

### 2. **`adwb`** - Azure Data Workbench

**Use when:** Running on Azure Data Workbench platform

```groovy
adwb {
  env {
    RESOURCE_DIR = '/files'                    # Absolute paths (not $PWD)
    OUTPUT_DIR = '/files/longGWAS_pipeline/results'
    STORE_DIR = '/files/longGWAS_pipeline/cache'
  }
  process {
    container = 'gwas-pipeline'               # Different container name
    withLabel: large_mem {
      cpus = 10                               # More resources
      memory = '70 GB'
    }
  }
  executor {
    cpus = 20                                 # Total available CPUs
    name = 'local'
    memory = '75 GB'                          # Total available memory
  }
  docker {
    enabled = true
  }
}
```

**Key Differences from `standard`:**
- **Absolute paths** (`/files` not `$PWD/files`)
- **More resources** (10 CPUs, 70 GB for large tasks)
- **Executor limits** (max 20 CPUs, 75 GB total)
- **Different container** (pre-loaded locally)

**When to use:** Azure Data Workbench environment

---

### 3. **`biowulf`** - NIH Biowulf HPC

**Use when:** Running on NIH's Biowulf supercomputer

```groovy
biowulf {
  env {
    OUTPUT_DIR = "$LONG_GWAS_DIR/$PROJECT_NAME/results"  # Uses env vars
    STORE_DIR = "$LONG_GWAS_DIR/Data/Cache"
  }
  process {
    container = "$LONG_GWAS_DIR/Docker/gwas-pipeline_survival.sif"  # Singularity image
    withLabel: large_mem {
      cpus = 10
      memory = '115 GB'                       # Much more memory!
    }
  }
  executor {
    cpus = 20
    name = 'local'
    memory = '125 GB'
  }
  singularity {                               # Uses Singularity, not Docker
    enabled = true
    runOptions = "--bind $PWD --env APPEND_PATH=$PWD/bin"
  }
}
```

**Key Features:**
- **Singularity** instead of Docker (common in HPC)
- **Environment variables** (`$LONG_GWAS_DIR`, `$PROJECT_NAME`) - you must set these
- **Much more memory** (115 GB for large tasks)
- **Bind mounts** (`--bind $PWD`) to access filesystems
- **Path appending** to access local scripts

**When to use:** NIH Biowulf cluster

---

### 4. **`gls`** - Google Life Sciences

**Use when:** Running on Google Cloud Platform (old API)

```groovy
gls {
  env {
    RESOURCE_DIR = 'gs://long-gwas/nextflow-test/files'  # Google Storage
    OUTPUT_DIR = 'gs://long-gwas/nextflow-test/files/results'
    STORE_DIR = 'gs://long-gwas/nextflow-test/files/cache'
  }
  workDir = 'gs://long-gwas/nextflow-test/workdir'       # Work in cloud storage
  process.executor = 'google-lifesciences'               # Cloud executor
  process.container = 'amcalejandro/longgwas:v2'
  
  google.location = 'us-central1'
  google.project = 'gp2-data-explorer'
  google.region  = 'us-central1'
  google.lifeSciences.bootDiskSize = '20GB'
  
  process.cpus = 8
  process.memory = '32 GB'
  process.disk = '30 GB'
  errorStrategy = { task.exitStatus==14 ? 'retry' : 'terminate' }
}
```

**Key Features:**
- **Cloud storage** (`gs://` Google Cloud Storage buckets)
- **Google Life Sciences API** (being deprecated)
- **No local executor** - runs in cloud VMs
- **Error handling** - retry on specific errors (code 14)
- **Disk allocation** (30 GB per task)

**When to use:** Google Cloud (legacy API)

---

### 5. **`gcb`** - Google Cloud Batch

**Use when:** Running on Google Cloud Platform (new API)

```groovy
gcb {
  env {
    RESOURCE_DIR = 'gs://long-gwas/nextflow-test-batch/files'
    OUTPUT_DIR = 'gs://long-gwas/nextflow-test-batch/files/results'
    STORE_DIR = 'gs://long-gwas/nextflow-test-batch/files/cache'
  }
  workDir = 'gs://long-gwas/nextflow-test-batch/workdir'
  
  process.executor = 'google-batch'           # New Batch API
  google.batch.spot = true                    # Use spot instances (cheaper!)
  
  errorStrategy = { task.exitStatus==14 ? 'retry' : 'terminate' }
  maxRetries = 5
}
```

**Key Features:**
- **Google Batch API** (newer, better than Life Sciences)
- **Spot instances** - up to 80% cheaper (can be preempted)
- **Automatic retries** (up to 5 times)
- **Same cloud storage** as `gls`

**When to use:** Google Cloud (modern API, cost-optimized)

---

### 6. **`gs-data`** - Google Cloud with Local Executor

**Use when:** Running locally but with Google Cloud access

```groovy
'gs-data' {
  env {
    RESOURCE_DIR = "$PWD/files"               # Local files
    OUTPUT_DIR = "$PWD/files/longGWAS_pipeline/results"
    STORE_DIR = "$PWD/files/longGWAS_pipeline/results/cache"
  }
  process.container = 'amcalejandro/longgwas:v2'
  google.region = 'us-central1'
  process.executor = 'local'                  # Runs locally!
}
```

**Key Features:**
- **Local execution** but Google Cloud setup
- **Local file paths** (not cloud storage)
- Hybrid setup (maybe for development?)

**When to use:** Testing on local machine with GCP credentials

---

## Profile Comparison Table

| Profile | Environment | Container | Executor | Storage | Best For |
|---------|------------|-----------|----------|---------|----------|
| `standard` | Local/laptop | Docker | local | Local disk | Development/testing |
| `adwb` | Azure | Docker | local | Azure storage | Azure Data Workbench |
| `biowulf` | NIH HPC | Singularity | local | HPC filesystem | Biowulf cluster |
| `gls` | Google Cloud | Docker | google-lifesciences | GCS buckets | GCP (legacy) |
| `gcb` | Google Cloud | Docker | google-batch | GCS buckets | GCP (modern, cheap) |
| `gs-data` | Local + GCP | Docker | local | Local disk | Hybrid/testing |

---

## Understanding the Components

### 1. Environment Variables (`env {}`)

These are available to all scripts:

```groovy
env {
  RESOURCE_DIR = "$PWD/files"   # $PWD = current directory
  OUTPUT_DIR = "/path/to/output"
  STORE_DIR = "/path/to/cache"  # Used in workflows/gwas.nf
}
```

**Problem in your pipeline:**
`workflows/gwas.nf` uses `${STORE_DIR}` which isn't always available during parsing!

### 2. Process Labels (`withLabel`)

Labels tag processes for different resource needs:

```groovy
// In a module file:
process MY_PROCESS {
  label 'medium'              // Uses 'medium' resources
  
  script:
  """
  # Do work
  """
}

// In config:
withLabel: medium {
  cpus = 4
  memory = '12 GB'
}
```

**Your labels:**
- `small`: Light tasks (file I/O, quick filters)
- `medium`: Standard tasks (QC, merging)
- `large_mem`: Memory-heavy (PCA, large merges)

### 3. Executor Settings

Controls HOW Nextflow runs tasks:

```groovy
executor {
  name = 'local'      # Run on this machine
  cpus = 20           # Max CPUs to use at once
  memory = '75 GB'    # Max memory to use at once
}
```

**Executor types:**
- `local`: This machine
- `google-lifesciences`: Google Cloud VMs
- `google-batch`: Google Batch API
- `slurm`, `sge`, `pbs`: Cluster schedulers

### 4. Container Settings

```groovy
docker {
  enabled = true
  temp = 'auto'
}

singularity {
  enabled = true
  runOptions = "--bind $PWD"
}
```

---

## Choosing the Right Profile

```
Where are you running?
│
├─ Local laptop/desktop → `standard`
│
├─ Azure Data Workbench → `adwb`
│
├─ NIH Biowulf HPC → `biowulf`
│
└─ Google Cloud
   │
   ├─ Want cheap (spot instances) → `gcb`
   │
   ├─ Legacy setup → `gls`
   │
   └─ Local testing with GCP → `gs-data`
```

---

## Common Issues & Solutions

### Issue 1: "Cannot find STORE_DIR"

**Problem:** Environment variables aren't available during script parsing

**Solution:** Use params instead:
```groovy
// In nextflow.config
params {
  store_dir = "$PWD/files/longGWAS_pipeline/results/cache"
}

// In workflows/gwas.nf
Channel.fromPath("${params.store_dir}/${params.dataset}/p1_run_cache/*")
```

### Issue 2: "Out of memory"

**Problem:** Process needs more RAM than allocated

**Solution:** Adjust profile or add label:
```groovy
// In module
process BIG_TASK {
  label 'large_mem'  // Use large_mem resources
}
```

### Issue 3: "Container not found"

**Problem:** Docker image doesn't exist or not pulled

**Solution:**
```bash
# Pull Docker image first
docker pull amcalejandro/longgwas:v2

# Or build locally
docker build -t gwas-pipeline .
```

---

## Best Practices

1. **Start with `standard` profile** for testing
2. **Set environment variables** before running on HPC
3. **Use appropriate labels** for process resource needs
4. **Check executor limits** match your system
5. **Use spot instances** (`gcb`) for cost savings on cloud

---

## Quick Reference Commands

```bash
# List available profiles
grep "^  [a-z]" nextflow.config

# Run with specific profile
nextflow run main.nf -profile standard
nextflow run main.nf -profile biowulf

# See what profile is active
nextflow run main.nf -profile standard -with-report
# Check report.html for executor details

# Test without running
nextflow run main.nf -profile standard -preview
```

---

## Summary

**Profiles = Execution Environments**

Each profile configures:
1. **Where** files are stored (`env` paths)
2. **How much** resources to use (`cpus`, `memory`)
3. **What** container system (`docker` or `singularity`)
4. **Where** to run (`executor`: local, cloud, HPC)

Choose based on your computing environment and scale up resources as needed!

---

**Need help?** 
- For local testing: Use `standard`
- For production: Match your infrastructure (Azure → `adwb`, NIH → `biowulf`, GCP → `gcb`)
