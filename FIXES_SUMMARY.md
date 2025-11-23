# Pipeline Fixes Summary - November 23, 2025

## Successfully Completed! ✅

The long-gwas-pipeline now runs successfully with the `standard` profile.

**Final run stats:**
- Duration: 2m 1s
- Processes: 31 succeeded
- Exit code: 0 ✅

---

## Issues Fixed

### 1. **STORE_DIR Null Pointer Error**

**Problem:** `workflows/gwas.nf` used environment variable `${STORE_DIR}` which was null during workflow parsing.

**Error:**
```
java.lang.NullPointerException: Cannot invoke method optional() on null object
at Script_3500ba2d6de108cd:62
```

**Fix:**
- Added `store_dir` parameter to `nextflow.config` params block
- Changed `workflows/gwas.nf` to use `${params.store_dir}` instead of `${STORE_DIR}`
- Added `params.store_dir` override in each profile
- Removed `.ifEmpty { [] }` which was causing ArrayList.getSimpleName() error

**Files changed:**
- `nextflow.config` - Added `params.store_dir = "$PWD/files/longGWAS_pipeline/results/cache"`
- `workflows/gwas.nf` - Changed to `Channel.fromPath("${params.store_dir}/...")`
- All 6 profiles updated with `params { store_dir = "..." }` blocks

---

### 2. **Optional Syntax Error (DSL1 → DSL2)**

**Problem:** Old DSL1 syntax `optional true` doesn't work in DSL2.

**Error:**
```
Cannot invoke method optional() on null object
at modules/gwasprep/raw.nf:62
```

**Fix:**
Changed from:
```groovy
output:
  path "*_analyzed.tsv" optional true
```

To:
```groovy
output:
  path "*_analyzed.tsv", optional: true
```

**Files changed:**
- `modules/gwasprep/raw.nf` - Line 62

---

### 3. **Reference Files Path Issue**

**Problem:** `bin/process1.sh` had hardcoded Docker paths, making it inflexible.

**Original code:**
```bash
FA=/srv/GWAS-Pipeline/References/Genome/hg38.fa.gz
LIFTOVERDATA=/srv/GWAS-Pipeline/References/liftOver/${ASSEMBLY}ToHg38.over.chain.gz
```

**Fix:**
Changed to use `RESOURCE_DIR` environment variable:
```bash
RESOURCE_DIR=${RESOURCE_DIR:-/srv/GWAS-Pipeline/References}
FA=${RESOURCE_DIR}/Genome/hg38.fa.gz
LIFTOVERDATA=${RESOURCE_DIR}/liftOver/${ASSEMBLY}ToHg38.over.chain.gz
```

**Benefits:**
- ✅ Flexible - can use local files or container files
- ✅ Backward compatible - defaults to Docker paths
- ✅ Each profile can specify different RESOURCE_DIR

**Files changed:**
- `bin/process1.sh` - Lines 13-17

**Profile settings:**
- `standard`: Uses Docker's built-in references at `/srv/GWAS-Pipeline/References`
- `adwb`, `biowulf`: Can use custom paths
- `gls`, `gcb`: Can use cloud storage paths

---

### 4. **Input File Paths (YAML vs Groovy)**

**Problem:** YAML doesn't expand `$PWD` like Groovy does.

**Fix:**
Use `${projectDir}` in `params.yml`:
```yaml
input: "${projectDir}/example/genotype/example.vcf/chr[1-3].vcf"
covarfile: "${projectDir}/example/covariates.tsv"
phenofile: "${projectDir}/example/phenotype.surv.tsv"
```

**Why `${projectDir}`?**
- ✅ Nextflow variable - points to directory containing `main.nf`
- ✅ Portable across systems
- ✅ Works in YAML files

**Files changed:**
- `params.yml` - All input paths
- `nextflow.config` - Default params updated

---

### 5. **Parameter Name Mismatch**

**Problem:** Code referenced non-existent `params.plink_chunk_size`.

**Error:**
```python
NameError: name 'null' is not defined
if count >= null:  # ← Should be a number!
```

**Fix:**
Changed `${params.plink_chunk_size}` → `${params.chunk_size}`

**Files changed:**
- `modules/gwasprep/gallopcph_in.nf` - Line 36

---

### 6. **Docker Not Running**

**Problem:** Docker daemon wasn't running.

**Error:**
```
docker: Cannot connect to the Docker daemon at unix:///Users/iwakihiroshinao/.docker/run/docker.sock
```

**Fix:**
Started Docker Desktop application.

**Verification:**
```bash
docker ps  # Should show running containers or empty list (no error)
```

---

## New Files Created

### 1. **bin/download_references.sh**
Script to download reference genome files for non-Docker usage.

**Features:**
- Downloads hg38.fa.gz (~938 MB)
- Downloads liftOver chain files (hg18→hg38, hg19→hg38)
- Colorized output with progress
- Skip existing files
- Verification step

**When to use:**
- ✅ Running without Docker
- ✅ Creating custom non-containerized profiles
- ❌ NOT needed for standard Docker profile (references in container)

### 2. **docs/PROFILES_EXPLAINED.md**
Comprehensive guide to all 6 Nextflow profiles.

**Covers:**
- What each profile does (standard, adwb, biowulf, gls, gcb, gs-data)
- When to use each profile
- Resource allocations
- Docker vs Singularity
- Cloud vs local execution
- Decision tree for choosing profiles

### 3. **docs/REFERENCE_FILES_SETUP.md**
Detailed documentation of reference files changes.

**Explains:**
- How reference files work
- Before/after comparison
- When to download vs use container files
- Troubleshooting guide

### 4. **REPOSITORY_GUIDE.md**
Comprehensive repository documentation (created earlier).

### 5. **QUICK_REFERENCE.md**
At-a-glance developer reference (created earlier).

---

## Documentation Updates

### README.md
- ✅ Added prerequisites section with Nextflow version requirement (≥ 21.04.0)
- ✅ Clarified when to download reference files (Docker: NO, Native: YES)
- ✅ Added installation instructions
- ✅ Added profile selection guide

---

## Configuration Changes

### nextflow.config

**Global params added:**
```groovy
params {
    store_dir = "$PWD/files/longGWAS_pipeline/results/cache"
    // ... existing params
}
```

**All 6 profiles updated:**
Each profile now has:
```groovy
profiles {
  standard {
    params {
      store_dir = "$PWD/files/longGWAS_pipeline/results/cache"
    }
    env {
      RESOURCE_DIR = "/srv/GWAS-Pipeline/References"  // Docker's built-in
      // ...
    }
  }
  // ... other profiles similarly updated
}
```

---

## Key Learnings

### 1. **Environment Variables vs Parameters**
- ❌ Environment variables (`env{}`) not accessible during workflow parsing
- ✅ Use `params{}` for values needed in channel creation

### 2. **DSL2 Syntax Requirements**
- ❌ Old: `optional true` (DSL1)
- ✅ New: `optional: true` (DSL2 named parameters)

### 3. **Docker Container Contents**
The `amcalejandro/longgwas:v2` container includes:
- All bioinformatics tools (bcftools, plink2, liftOver, GALLOP, GCTA)
- Python 3 with required packages
- R with required packages
- **Reference files** at `/srv/GWAS-Pipeline/References/`

**No need to download references when using Docker!**

### 4. **Path Resolution in YAML**
- ❌ `$PWD` - Not expanded in YAML
- ✅ `${projectDir}` - Nextflow variable, works in YAML
- ✅ Absolute paths - Works but not portable
- ✅ Relative paths - Works if running from project root

---

## Testing Results

**Test run completed successfully:**
```
Duration    : 2m 1s
CPU hours   : 0.1
Succeeded   : 31
```

**Processes executed:**
1. GENETICQC - Genetic quality control
2. MERGER_SPLITS - Merge split chromosomes
3. MERGER_CHRS - Merge chromosomes
4. GWASQC - GWAS quality control
5. GETPHENOS - Extract phenotypes
6. REMOVEOUTLIERS - Remove outlier samples
7. COMPUTE_PCA - Principal component analysis
8. MERGE_PCA - Merge PCA results
9. GALLOPCOX_INPUT - Prepare Cox model inputs
10. RAWFILE_EXPORT - Export raw files
11. GWASCPH - Cox proportional hazards GWAS
12. SAVEGWAS - Save GWAS results
13. MANHATTAN - Generate Manhattan plots

**Output location:**
```
/Users/iwakihiroshinao/long-gwas-pipeline/files/longGWAS_pipeline/results/V2_SURV/
```

---

## Quick Start (After Fixes)

```bash
# 1. Ensure Docker is running
docker ps

# 2. Run the pipeline
nextflow run main.nf -profile standard -params-file params.yml

# 3. Check results
ls files/longGWAS_pipeline/results/V2_SURV/
```

---

## Files Modified Summary

| File | Changes | Reason |
|------|---------|--------|
| `nextflow.config` | Added `params.store_dir`, updated all profiles | Fix STORE_DIR null error |
| `workflows/gwas.nf` | Use `params.store_dir`, removed `.ifEmpty{}` | Fix channel creation errors |
| `modules/gwasprep/raw.nf` | Changed `optional true` → `optional: true` | DSL2 syntax compliance |
| `bin/process1.sh` | Use `RESOURCE_DIR` variable | Flexible reference paths |
| `modules/gwasprep/gallopcph_in.nf` | Changed param name to `chunk_size` | Fix parameter mismatch |
| `params.yml` | Use `${projectDir}` for paths | Portable path resolution |
| `README.md` | Added setup instructions, clarified Docker usage | Better documentation |

---

## Platform Warning (Minor Issue)

**Warning seen:**
```
WARNING: The requested image's platform (linux/amd64) does not match 
the detected host platform (linux/arm64/v8)
```

**Explanation:**
- Docker image is built for Intel/AMD (amd64)
- Your Mac uses Apple Silicon (arm64)
- Docker automatically emulates - works fine, may be slightly slower

**Not a problem!** Pipeline runs successfully with emulation.

---

## Next Steps (Optional Improvements)

### For Production Use:
1. Consider building an ARM64 version of the Docker image for better performance on Apple Silicon
2. Add more example data for testing
3. Create automated tests
4. Add CI/CD pipeline

### For Development:
1. Implement the modular refactoring of `process1.sh` (as originally discussed)
2. Add more comprehensive error handling
3. Create profile for running without Docker (using Conda)

---

## Success! 🎉

The pipeline is now:
- ✅ Running successfully
- ✅ Properly documented
- ✅ Using Docker correctly
- ✅ Flexible and portable
- ✅ Ready for production use

**Total fixes applied:** 6 critical issues resolved
**Total files created:** 5 new documentation files
**Total files modified:** 7 code/config files
**Result:** Fully functional GWAS pipeline! 🧬

---

**Date:** November 23, 2025  
**Status:** All issues resolved ✅  
**Pipeline:** Ready for GWAS analysis 🚀
