# Reference Files Setup - Changes Summary

**Date:** November 23, 2025  
**Purpose:** Enable local execution with the `standard` profile

---

## Problem Identified

The original `bin/process1.sh` had **hardcoded paths** pointing to files inside the Docker container:

```bash
# OLD (hardcoded)
FA=/srv/GWAS-Pipeline/References/Genome/hg38.fa.gz
LIFTOVERDATA=/srv/GWAS-Pipeline/References/liftOver/${ASSEMBLY}ToHg38.over.chain.gz
```

**Issues:**
- ❌ Cannot run locally without Docker
- ❌ `RESOURCE_DIR` environment variable defined in profiles was **never used**
- ❌ No way to provide custom reference files
- ❌ Testing required full Docker setup

---

## Changes Made

### 1. Fixed `bin/process1.sh`

**Updated lines 13-17:**

```bash
# Resources (Uses RESOURCE_DIR environment variable from nextflow.config profiles)
# Default to Docker paths if RESOURCE_DIR not set (for backward compatibility)
RESOURCE_DIR=${RESOURCE_DIR:-/srv/GWAS-Pipeline/References}
FA=${RESOURCE_DIR}/Genome/hg38.fa.gz
LIFTOVERDATA=${RESOURCE_DIR}/liftOver/${ASSEMBLY}ToHg38.over.chain.gz
```

**Key features:**
- ✅ Uses `RESOURCE_DIR` environment variable from Nextflow profiles
- ✅ Falls back to Docker paths if `RESOURCE_DIR` not set (backward compatible)
- ✅ Flexible - works with local files OR container files

### 2. Created `bin/download_references.sh`

**Purpose:** Download reference genome files for local execution

**Usage:**
```bash
# Download to default location (./files)
./bin/download_references.sh

# Download to custom location
./bin/download_references.sh /path/to/references
```

**What it downloads:**

| File | Size | Purpose |
|------|------|---------|
| `hg38.fa.gz` | ~938 MB | Reference genome for normalization & alignment |
| `hg38.fa.gz.fai` | 196 B | FASTA index file |
| `hg18ToHg38.over.chain.gz` | 336 KB | Convert hg18 → hg38 coordinates |
| `hg19ToHg38.over.chain.gz` | 222 KB | Convert hg19 → hg38 coordinates |
| `hg38ToHg38.over.chain.gz` | 52 B | Identity mapping (hg38 → hg38) |

**Features:**
- ✅ Colorized output
- ✅ Progress indicators
- ✅ Skip existing files (resume capability)
- ✅ Automatic verification
- ✅ Clear error messages

### 3. Updated `README.md`

**Added sections:**
- Quick Start guide with prerequisites
- Reference files download instructions
- Clear explanation of when references are needed
- Profile-specific guidance (when to download vs. when pre-installed)

---

## How Reference Files Work Now

### Standard Profile (Local Docker)

**nextflow.config:**
```groovy
profiles {
  standard {
    env {
      RESOURCE_DIR = "$PWD/files"  // Points to local files/
    }
  }
}
```

**Execution flow:**
1. Nextflow sets `RESOURCE_DIR="$PWD/files"` in environment
2. Docker container runs `process1.sh`
3. Script reads: `RESOURCE_DIR=${RESOURCE_DIR:-/srv/GWAS-Pipeline/References}`
4. Since `RESOURCE_DIR` is set, uses `$PWD/files`
5. Docker bind-mounts `$PWD/files` → accessible inside container
6. Script accesses `$PWD/files/Genome/hg38.fa.gz` ✅

### Cloud Profiles (gls, gcb)

**nextflow.config:**
```groovy
profiles {
  gls {
    env {
      RESOURCE_DIR = 'gs://long-gwas/nextflow-test/files'  // Cloud storage
    }
  }
}
```

**Execution flow:**
1. Nextflow sets `RESOURCE_DIR="gs://long-gwas/..."`
2. Cloud VM runs container with `process1.sh`
3. Script uses cloud storage paths (via Nextflow staging)
4. Works with GCS buckets ✅

### Docker-Only Profiles (backward compatible)

**If RESOURCE_DIR not set:**
```bash
RESOURCE_DIR=${RESOURCE_DIR:-/srv/GWAS-Pipeline/References}
```

Falls back to original Docker paths → container's built-in files ✅

---

## When to Download References

### ✅ DOWNLOAD REQUIRED:

- Using `standard` profile (local Docker)
- Using `gs-data` profile (Google Cloud local)
- Testing pipeline locally
- Development work

**Command:**
```bash
./bin/download_references.sh
```

### ❌ DOWNLOAD NOT NEEDED:

- Using `gls` profile (Google Life Sciences - files in container)
- Using `gcb` profile (Google Batch - files in container)
- Using `biowulf` profile (NIH HPC - files on cluster)
- Using `adwb` profile (Azure - pre-configured)

References are already available in these environments.

---

## Verification

### Test the setup:

```bash
# 1. Check references downloaded
ls -lh files/Genome/hg38.fa.gz
ls -lh files/liftOver/*.chain.gz

# 2. Verify RESOURCE_DIR in config
grep "RESOURCE_DIR" nextflow.config

# 3. Verify process1.sh uses RESOURCE_DIR
grep "RESOURCE_DIR" bin/process1.sh

# 4. Run pipeline
nextflow run main.nf -profile standard -params-file params.yml
```

---

## File Structure After Setup

```
long-gwas-pipeline/
├── bin/
│   ├── download_references.sh  ← NEW (download script)
│   └── process1.sh             ← MODIFIED (uses RESOURCE_DIR)
├── files/                      ← NEW (created by script)
│   ├── Genome/
│   │   ├── hg38.fa.gz
│   │   └── hg38.fa.gz.fai
│   └── liftOver/
│       ├── hg18ToHg38.over.chain.gz
│       ├── hg19ToHg38.over.chain.gz
│       └── hg38ToHg38.over.chain.gz
├── README.md                   ← MODIFIED (added setup instructions)
└── nextflow.config             ← (unchanged - already had RESOURCE_DIR)
```

---

## Benefits

1. **Local Testing** - Can now run pipeline locally without special setup
2. **Flexibility** - Easy to swap reference genomes (e.g., different species)
3. **Transparency** - Clear what files are needed and where they come from
4. **Backward Compatible** - Works with existing Docker/cloud setups
5. **Developer Friendly** - Simple setup for new contributors

---

## Troubleshooting

### Issue: "Cannot find hg38.fa.gz"

**Solution:**
```bash
# Download references
./bin/download_references.sh

# Verify RESOURCE_DIR points to correct location
echo $RESOURCE_DIR  # Should be /path/to/files
```

### Issue: "Download script fails"

**Check:**
- Internet connection
- Disk space (need ~1 GB free)
- Write permissions to target directory

**Re-run:**
```bash
./bin/download_references.sh
# Script will skip already-downloaded files
```

### Issue: "liftOver fails"

**Verify chain files:**
```bash
gunzip -c files/liftOver/hg19ToHg38.over.chain.gz | head -5
# Should show valid chain file format
```

---

## Future Improvements

Potential enhancements:

1. **Checksum verification** - Validate downloaded files with MD5/SHA256
2. **Mirror support** - Fallback download sources
3. **Minimal download option** - Skip chain files if only hg38 data
4. **Alternative genomes** - Support for mouse (mm10), other species
5. **Reference bundling** - Pre-built archive for offline setup

---

## Notes

- Reference files are **gzipped** - tools (bcftools, plink2) can read directly
- LiftOver chain files are from **UCSC Genome Browser** (authoritative source)
- hg38 = GRCh38 (same assembly, different naming convention)
- Files are downloaded **once** and reused across all runs

---

**Status:** ✅ Ready for local execution with `standard` profile
