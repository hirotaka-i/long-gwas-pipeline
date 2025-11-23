# longitudinal-GWAS-pipeline
Repository for Nextflow pipeline to perform GWAS with longitudinal capabilities

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
- **Reference Files** (for local execution only - see below)
  - ~1 GB disk space for reference genome files

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/hirotaka-i/long-gwas-pipeline.git
   cd long-gwas-pipeline
   ```

2. **Download reference files (ONLY if running WITHOUT Docker):**
   
   ⚠️ **Skip this step if using Docker!** The Docker container already includes reference files.
   
   If you plan to run the pipeline **locally WITHOUT Docker** (using native tools), you need to download reference genome files:
   
   ```bash
   # Only run this if NOT using Docker
   ./bin/download_references.sh
   ```
   
   This will create the following structure:
   ```
   files/
   ├── Genome/
   │   ├── hg38.fa.gz          (~938 MB)
   │   └── hg38.fa.gz.fai
   └── liftOver/
       ├── hg18ToHg38.over.chain.gz
       ├── hg19ToHg38.over.chain.gz
       └── hg38ToHg38.over.chain.gz
   ```
   
   **When to download:**
   - ✅ Creating a custom profile without Docker
   - ✅ Running tools natively on your system
   - ✅ Debugging or testing individual scripts
   
   **When to skip:**
   - ❌ Using `standard` profile (Docker) - references already in container
   - ❌ Using cloud profiles (`gls`, `gcb`) - references in container
   - ❌ Using HPC profiles (`biowulf`) - references on cluster

3. **Prepare your input data and parameters:**
   
   Edit `params.yml` to specify your input files and analysis parameters.

### Running the Pipeline

```bash
# Local execution with Docker (standard profile)
nextflow run main.nf -profile standard -params-file params.yml

# Google Cloud with Batch API (recommended for cloud)
nextflow run main.nf -profile gcb -params-file params.yml

# NIH Biowulf HPC cluster
nextflow run main.nf -profile biowulf -params-file params.yml
```

For detailed information about profiles, see [docs/PROFILES_EXPLAINED.md](docs/PROFILES_EXPLAINED.md).

## Documentation

- **[Getting Started Guide](docs/getting_started.md)** - Detailed setup and usage instructions
- **[Repository Guide](REPOSITORY_GUIDE.md)** - Comprehensive overview of the codebase
- **[Quick Reference](QUICK_REFERENCE.md)** - At-a-glance developer reference
- **[Profiles Explained](docs/PROFILES_EXPLAINED.md)** - Understanding execution environments
- **[Parameters Guide](docs/parameters.md)** - All configuration options
- **[File Formats](docs/file_formats.md)** - Input/output file specifications

## Reference Files Explained

The pipeline requires reference genome files for:
- **Genome normalization** - Aligning variants to the hg38 reference
- **LiftOver** - Converting coordinates from hg18/hg19 to hg38

### Docker Containers Include References

**All Docker/Singularity containers already have reference files built-in** at `/srv/GWAS-Pipeline/References/`:
- `hg38.fa.gz` - Human genome reference
- `hg18ToHg38.over.chain.gz` - Coordinate conversion
- `hg19ToHg38.over.chain.gz` - Coordinate conversion

### When You Need to Download References:

**Download required (run `./bin/download_references.sh`):**
- ✅ Creating a **non-Docker profile** (native tools)
- ✅ Testing scripts **outside of containers**
- ✅ Running on systems **without Docker/Singularity**

**Download NOT needed (references in container):**
- ❌ Using `standard` profile (Docker) - **references built into container**
- ❌ Using `gls` or `gcb` profiles (Google Cloud) - **references in container**
- ❌ Using `biowulf` profile (NIH HPC) - **references in Singularity container**
- ❌ Using `adwb` profile (Azure) - **references in container**

### Summary

- **With Docker/Singularity:** No download needed! ✅
- **Without containers:** Run `./bin/download_references.sh` 📥

## Support

For issues, questions, or contributions, please open an issue on GitHub.

