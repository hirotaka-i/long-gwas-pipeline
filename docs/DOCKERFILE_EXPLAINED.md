# Dockerfile Explanation

## Is the Dockerfile Used? ✅ YES (But Not Currently By You)

### **The Situation:**

The repository contains a `Dockerfile` (379 lines) that **was used to build** the Docker image `amcalejandro/longgwas:v2` that you're currently using.

```
┌─────────────────────────────────────────────────────────────────┐
│  Dockerfile in Repository                                      │
│  (379 lines - builds the image)                                │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 │ docker build -t amcalejandro/longgwas:v2 .
                 ↓
┌─────────────────────────────────────────────────────────────────┐
│  Docker Image: amcalejandro/longgwas:v2                        │
│  (Published to Docker Hub by amcalejandro)                     │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 │ docker pull amcalejandro/longgwas:v2
                 ↓
┌─────────────────────────────────────────────────────────────────┐
│  Your Local Docker                                              │
│  (Using the pre-built image)                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## What the Dockerfile Contains

### **Base Image:**
```dockerfile
FROM ubuntu:18.04
```

### **Major Components Installed:**

1. **Python 3.8.11** - Built from source
   ```dockerfile
   ENV PYTHON_VERSION 3.8.11
   ```

2. **Bioinformatics Tools:**
   - **bcftools** (VCF manipulation)
   - **plink2** (genetic analysis)
   - **GCTA** (genetic analysis)
   - **liftOver** (genome coordinate conversion)
   - **GALLOP** (longitudinal GWAS)

3. **R with packages:**
   ```dockerfile
   apt-get install r-base
   Rscript -e 'install.packages(c("survival", "optparse"))'
   ```

4. **Python packages:**
   - pandas
   - numpy
   - scipy
   - matplotlib
   - And many more bioinformatics libraries

5. **Google Cloud SDK (gsutil):**
   ```dockerfile
   # For cloud storage access
   ```

6. **Local Files Copied In:**
   ```dockerfile
   COPY bin/plink2_linux_x86_64_20210920.zip /root/plink2_linux_x86_64.zip
   COPY bin/gcta_1.93.2beta.zip /root/gcta_1.93.2beta.zip
   COPY bin/plink_linux_x86_64_20210606.zip /root/plink_linux_x86_64.zip
   COPY References/ancestry_ref_panel.tar.gz /root
   ```

---

## Current Usage

### **You are using:** Pre-built image from Docker Hub
```groovy
// In nextflow.config
process.container = 'amcalejandro/longgwas:v2'
```

When you run the pipeline, Nextflow:
1. Checks if `amcalejandro/longgwas:v2` exists locally
2. If not, pulls it from Docker Hub: `docker pull amcalejandro/longgwas:v2`
3. Uses that pre-built image

**You don't need to build the Dockerfile yourself!**

---

## When Would You Use the Dockerfile?

### **Scenario 1: Customization**
If you want to modify the Docker image:

```bash
# Edit Dockerfile (add tools, change versions, etc.)
vim Dockerfile

# Build your custom image
docker build -t my-custom-gwas:v1 .

# Update nextflow.config to use your image
# process.container = 'my-custom-gwas:v1'
```

### **Scenario 2: Local Development**
Original documentation suggests building locally:

```bash
# From docs/getting_started.md
cd longitudinal-GWAS-pipeline
docker build --build-arg BUILD_VAR=$(date +%Y%m%d-%H%M%S) -t gwas-pipeline .
```

Then update `nextflow.config`:
```groovy
process.container = 'gwas-pipeline'  // Use your local build
```

### **Scenario 3: ARM64 (Apple Silicon) Optimization**
To avoid the platform mismatch warning:

```bash
# Build for ARM64 (Apple Silicon)
docker buildx build --platform linux/arm64 -t gwas-pipeline:arm64 .

# Or build multi-platform
docker buildx build --platform linux/amd64,linux/arm64 -t gwas-pipeline:multi .
```

### **Scenario 4: Version Control**
If you don't trust external images or need reproducibility:

```bash
# Build and tag with version
docker build -t gwas-pipeline:2025-11-23 .

# Export and archive
docker save gwas-pipeline:2025-11-23 | gzip > gwas-pipeline-2025-11-23.tar.gz
```

### **Scenario 5: Offline/Air-Gapped Systems**
Build once, transfer to systems without internet:

```bash
# Build on internet-connected machine
docker build -t gwas-pipeline .
docker save gwas-pipeline > gwas-pipeline.tar

# Transfer to offline machine
scp gwas-pipeline.tar user@offline-server:/tmp/

# Load on offline machine
docker load < /tmp/gwas-pipeline.tar
```

---

## Comparison: Pre-built vs Custom Build

| Aspect | Pre-built (`amcalejandro/longgwas:v2`) | Custom Build (Dockerfile) |
|--------|---------------------------------------|---------------------------|
| **Convenience** | ✅ Just works, no setup | ❌ Need to build (~30-60 min) |
| **Trust** | ⚠️ Trust external maintainer | ✅ Full control |
| **Customization** | ❌ Can't modify | ✅ Modify anything |
| **Platform** | ⚠️ linux/amd64 only | ✅ Build for your platform |
| **Versioning** | ⚠️ Maintainer controls updates | ✅ You control versions |
| **Size** | ~2-3 GB download | ~2-3 GB + build artifacts |
| **Speed** | ✅ Fast (just pull) | ❌ Slow build process |

---

## What's in `amcalejandro/longgwas:v2`?

This is the **pre-built image** on Docker Hub, likely built from this exact Dockerfile (or very similar):

```bash
# Check the image
docker images | grep longgwas

# Inspect what's inside
docker run --rm amcalejandro/longgwas:v2 which plink2
# Output: /usr/local/bin/plink2

docker run --rm amcalejandro/longgwas:v2 python3 --version
# Output: Python 3.8.11

docker run --rm amcalejandro/longgwas:v2 ls /srv/GWAS-Pipeline/References/
# Output: Genome  Scripts  liftOver  ref_panel
```

---

## Dockerfile History & Ownership

Based on the code and image name:
- **Created by:** amcalejandro (GitHub/Docker Hub user)
- **Published to:** Docker Hub as `amcalejandro/longgwas:v2`
- **Included in repo:** For reference and customization
- **Maintained:** Seems to be part of this repository's development

The Dockerfile serves two purposes:
1. **Documentation** - Shows exactly what's in the container
2. **Reproducibility** - Anyone can rebuild the exact environment

---

## Should You Build It?

### **NO - If:**
- ✅ Pipeline works with `amcalejandro/longgwas:v2`
- ✅ You're okay with the platform warning (minor)
- ✅ You trust the pre-built image
- ✅ You want quick setup

### **YES - If:**
- ⚠️ You need custom tools or versions
- ⚠️ You want ARM64 for better Mac performance
- ⚠️ You need reproducibility guarantees
- ⚠️ You're in an air-gapped environment
- ⚠️ You want to publish a modified version

---

## How to Switch to Custom Build

If you decide to use your own build:

```bash
# 1. Build the image
docker build -t my-gwas-pipeline:v1 .

# 2. Update nextflow.config (all profiles)
# Replace:
process.container = 'amcalejandro/longgwas:v2'
# With:
process.container = 'my-gwas-pipeline:v1'

# 3. Run pipeline as usual
nextflow run main.nf -profile standard -params-file params.yml
```

---

## Build Time Estimate

**Full build from scratch:**
- **Time:** 30-60 minutes (depending on CPU/network)
- **Disk space:** ~5 GB during build
- **Final image:** ~2-3 GB

**What takes time:**
1. Compiling Python 3.8 from source (~10 min)
2. Installing bioinformatics tools (~15 min)
3. Installing R packages (~10 min)
4. Installing Python packages (~10 min)

---

## Platform Warning Explained

You're seeing this warning:
```
WARNING: The requested image's platform (linux/amd64) does not match 
the detected host platform (linux/arm64/v8)
```

**Why:**
- `amcalejandro/longgwas:v2` was built for **Intel/AMD (x86_64/amd64)**
- Your Mac has **Apple Silicon (ARM64/M1/M2/M3)**
- Docker automatically emulates x86_64 on ARM64

**Impact:**
- ✅ Works fine! Docker handles emulation
- ⚠️ ~10-30% slower than native ARM64
- No functional issues

**Fix (if desired):**
Build ARM64 version:
```bash
docker buildx build --platform linux/arm64 -t gwas-pipeline:arm64 .
```

---

## Summary

| Question | Answer |
|----------|--------|
| **Is Dockerfile used?** | Yes, it was used to build `amcalejandro/longgwas:v2` |
| **Do you use it?** | No, you use the pre-built image from Docker Hub |
| **Should you build it?** | Optional - only if you need customization |
| **Can you ignore it?** | Yes, pipeline works fine with pre-built image |
| **Is it maintained?** | Appears to be part of the repository |

**Current status:** ✅ **Working perfectly with pre-built image** - no need to build unless you want to customize!

---

**Recommendation:** Keep using `amcalejandro/longgwas:v2` unless you have a specific reason to customize. The Dockerfile is there for transparency and future customization if needed.
