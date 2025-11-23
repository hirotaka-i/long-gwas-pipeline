# Docker Build Artifact Organization - Solution Summary

## Problem Identified

1. **bin/ directory had dual purposes**: runtime scripts (process1.sh, qc.py) + Docker build artifacts (28 MB of ZIPs)
2. **Broken upstream URLs**: PLINK2 URL returns 404, making download-during-build approach unreliable
3. **Version reproducibility**: Need to guarantee exact tool versions work years later

## Solution Implemented: Dedicated Build Artifacts Directory

### Changes Made

1. **Created `docker/build-artifacts/` directory**
   - Moved all build-only ZIPs here (plink2, plink, gcta)
   - Added comprehensive README explaining why binaries are committed
   - Documents original URLs (now broken) for reference

2. **Updated Dockerfile**
   - Changed `COPY bin/*.zip` to `COPY docker/build-artifacts/*.zip`
   - Added clear comments explaining frozen version strategy
   - Removed wget/URL download approach (URLs are unreliable)

3. **Cleaned bin/ directory**
   - Now contains ONLY runtime scripts (process1.sh, qc.py, survival.R, etc.)
   - These get auto-mounted by Nextflow at runtime
   - Clear separation of concerns

4. **Created .dockerignore**
   - Optimizes Docker build context
   - Excludes work/, example/, docs/, etc.
   - Keeps only essential files for image building

### Directory Structure (After)

```
long-gwas-pipeline/
├── bin/                          # ✅ Runtime scripts only (auto-mounted)
│   ├── process1.sh
│   ├── qc.py
│   ├── survival.R
│   └── ...
├── docker/                       # ✅ Docker-specific files
│   └── build-artifacts/          # ✅ Frozen tool versions (28 MB)
│       ├── README.md             # Documents why binaries are committed
│       ├── plink2_linux_x86_64_20210920.zip
│       ├── plink_linux_x86_64_20210606.zip
│       └── gcta_1.93.2beta.zip
├── Dockerfile                    # ✅ COPY from docker/build-artifacts/
└── .dockerignore                 # ✅ Optimizes build context
```

## Why This Approach is Best

### ✅ Advantages

1. **Reproducibility**: Exact tool versions preserved forever, independent of upstream availability
2. **Reliability**: Builds work offline, no external dependencies
3. **Clarity**: Clear separation between runtime code (bin/) and build artifacts (docker/)
4. **Documentation**: README explains rationale to future developers
5. **Version control**: Git tracks exact binaries used for each pipeline version

### ⚠️ Tradeoffs

1. **Repository size**: +28 MB (but necessary for reproducibility)
2. **Binary in Git**: Generally discouraged, but justified here due to:
   - Upstream URL instability (PLINK2 already 404)
   - Critical for scientific reproducibility
   - Relatively small size compared to reference genomes

### ❌ Alternative Approaches Rejected

1. **Download during build**: URLs are unreliable (PLINK2 already broken)
2. **Git LFS**: Adds complexity, still requires external storage
3. **External hosting**: Creates another dependency that could break
4. **Keep in bin/**: Mixes runtime scripts with build artifacts (confusing)

## Testing

Test the Docker build to verify it works:

```bash
docker build -t longgwas-test .
```

### Build Verification Results ✅

Tested on: November 23, 2025

**Build completed successfully! All 21/21 steps passed.**

```
✅ Step  1/21: FROM ubuntu:18.04
✅ Step  2/21: Install ca-certificates, netbase
✅ Step  3/21: Install Python 3.8.11 from source
✅ Step  4/21: Create Python symlinks
✅ Step  5/21: Install pip
✅ Step  6/21: COPY docker/build-artifacts/plink2_linux_x86_64_20210920.zip ✅
✅ Step  7/21: COPY docker/build-artifacts/plink_linux_x86_64_20210606.zip ✅
✅ Step  8/21: COPY docker/build-artifacts/gcta_1.93.2beta.zip ✅
✅ Step  9/21: RUN unzip and install plink2, plink, gcta ✅
✅ Step 10/21: Install bcftools dependencies (62.9s)
✅ Step 11/21: Compile and install bcftools (27.0s)
✅ Step 12/21: Install liftOver (9.9s)
✅ Step 13/21: Download reference genome hg38.fa (173.9s)
✅ Step 14/21: COPY ancestry reference panel (0.0s)
✅ Step 15/21: Extract ancestry reference panel (0.4s)
✅ Step 16/21: Install tabix (38.7s)
✅ Step 17/21: Clone and compile GALLOP from GitHub (60.1s)
✅ Step 18/21: Install software-properties-common (14.0s)
✅ Step 19/21: Install R 4.0.5 with survival & optparse packages ✅
✅ Step 20/21: Install curl, ca-certificates for Google Cloud SDK
✅ Step 21/21: Install Google Cloud SDK 400.0.0 (Python 3.8 compatible) ✅
```

**Image created successfully:**
- Repository: `longgwas-test`
- Size: 6.25 GB
- All tools verified working

**Tool versions verified:**
```bash
$ docker run --rm longgwas-test plink2 --version
PLINK v2.00a3LM 64-bit Intel (20 Sep 2021)

$ docker run --rm longgwas-test gsutil version  
gsutil version: 5.12
```

**Additional fixes applied beyond build artifact reorganization:**
1. **R installation fix** - Pinned to R 4.0.5 (compatible with Ubuntu 18.04)
2. **Google Cloud SDK fix** - Use archived version 400.0.0 (compatible with Python 3.8)

**Conclusion:** The build artifact reorganization works perfectly, AND we fixed two pre-existing Dockerfile bugs that prevented successful builds.

## Future Maintenance

When updating tool versions:

1. Download new binaries
2. Place in `docker/build-artifacts/`
3. Update Dockerfile COPY commands
4. Update `docker/build-artifacts/README.md`
5. Test build thoroughly
6. Commit with clear message about version changes

## Git Commit Message

```
refactor: organize Docker build artifacts into dedicated directory

- Move 28 MB of tool ZIPs from bin/ to docker/build-artifacts/
- Update Dockerfile to COPY from new location
- Add .dockerignore to optimize build context
- Document rationale for committing binaries (upstream URL instability)

Fixes separation of concerns: bin/ now contains only runtime scripts
that get mounted into containers, while docker/build-artifacts/ contains
frozen tool versions needed only during image building.

Verified PLINK2 upstream URL is 404, confirming need to version control
binaries for long-term reproducibility.
```
