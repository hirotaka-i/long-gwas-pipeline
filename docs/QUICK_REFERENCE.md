# Long-GWAS Pipeline - Quick Reference

**For:** Developers wanting to understand the pipeline at a glance

---

## 30-Second Overview

```
INPUT: VCF files + Phenotypes + Covariates
  ↓
PROCESS: QC → Data Prep → GWAS → Results
  ↓
OUTPUT: Association statistics + Plots
```

**Supports:** GLM (cross-sectional), GALLOP (longitudinal), CPH (survival)

---

## File Tree (Simplified)

```
long-gwas-pipeline/
├── main.nf                    ← START HERE (entry point)
├── workflows/gwas.nf          ← Main coordinator
├── subworkflows/              ← 4 workflow stages
│   ├── fullqc.nf             ← Stage 1: QC
│   ├── gwasinputs.nf         ← Stage 2: Prep
│   ├── rungwas.nf            ← Stage 3: Analysis
│   └── saveresults.nf        ← Stage 4: Output
├── modules/                   ← Individual tasks
└── bin/process1.sh           ← ⚠️ MAIN REFACTORING TARGET
```

---

## Pipeline Stages

### Stage 1: QC (DOQC)
```
VCF → Chunk → process1.sh → Merge → GWASQC
```
**Output:** Clean, QC'd genetic data

### Stage 2: Data Prep (GWASDATA_PREP)
```
Phenotypes → Outlier removal
Covariates → PCA → Merge
```
**Output:** Analysis-ready data matrices

### Stage 3: GWAS (GWAS_RUN)
```
If longitudinal → GALLOP
If survival     → CPH
Else           → GLM
```
**Output:** Association results per variant

### Stage 4: Save (SAVE_RESULTS)
```
Results → Merge → Export → Plots
```
**Output:** Final files

---

## Key Parameters

### Input
```
--input         Glob pattern for VCF files
--phenofile     TSV with phenotypes
--covarfile     TSV with covariates
```

### Analysis Type (pick ONE)
```
--longitudinal_flag true   # LMM with GALLOP
--survival_flag true       # Cox PH
--linear_flag true         # GLM (default)
```

### QC Settings
```
--r2thres              -9 for genotyped, 0.3-0.8 for imputed
--minor_allele_freq    Default: 0.05
--kinship              Default: 0.177
--assembly             hg18, hg19, or hg38
```

---

## process1.sh - The Workhorse

**What it does:** 8 QC steps in one monolithic script

```
1. PASS filter (± R² for imputed)
   ↓
2. Split multi-allelic
   ↓
3. LiftOver to hg38 (if needed)
   ↓
4. Left-normalize
   ↓
5. Filter SNPs (ACGT, MAC≥2)
   ↓
6. Align REF/ALT
   ↓
7. Rename (chr:pos:ref:alt)
   ↓
8. Remove duplicates & geno filter
```

**Tools:** bcftools, liftOver, plink2

**⚠️ Refactoring Target:**
- Too complex (8 steps in 103 lines)
- Hard to debug
- Can't test individual steps

---

## Channel Flow Example

```groovy
// workflows/gwas.nf
Channel.fromPath(params.input)           // chr*.vcf
  .map{ f -> tuple(f.getSimpleName(), f) } // [chr1, chr1.vcf]
  ↓
// subworkflows/fullqc.nf
  .splitText(by: 30000)                  // Chunk into 30k variants
  ↓
// modules/geneticqc/qc.nf
  → GENETICQC process (calls process1.sh)
  ↓
  .groupTuple()                           // Group chunks
  ↓
  → MERGER_SPLITS (merge chunks)
  → MERGER_CHRS (merge chromosomes)
  ↓
// Back to gwas.nf → next stage
```

---

## Data Type Decision Tree

```
Is data imputed?
├─ YES → Use --r2thres 0.3 (or higher)
│        Import dosage (DS field)
│
└─ NO  → Use --r2thres -9
         Hard-called genotypes only

Is analysis cross-sectional?
├─ YES → GLM
│        Format: PLINK files
│
└─ NO  → Time-varying?
         ├─ Repeated measures → GALLOP (LMM)
         └─ Time-to-event    → CPH (survival)
         Format: Special raw files
```

---

## Common Commands

### Run Pipeline
```bash
# With params file
nextflow run main.nf -params-file params.yml

# With inline params
nextflow run main.nf \
  --input "data/chr*.vcf" \
  --phenofile phenotype.tsv \
  --covarfile covariates.tsv \
  --linear_flag true

# Resume failed run
nextflow run main.nf -resume -params-file params.yml
```

### Test Individual Script
```bash
# Test process1.sh directly
bin/process1.sh \
  2 \                    # threads
  input.vcf.gz \         # input VCF
  -9 \                   # R2 threshold
  hg19 \                 # assembly
  21 \                   # chromosome
  output_prefix          # output name
```

---

## Output Files

### Cache (Intermediate)
```
files/longGWAS_pipeline/results/cache/{dataset}/
├── p1_run_cache/              ← Cached QC chunks
├── merged_splits/             ← Merged chunks
└── merged_chrs/               ← Final merged data
```

### Results (Final)
```
results/
├── gwas_results_{pheno}.tsv   ← Association results
├── manhattan_{pheno}.png      ← Plots (if enabled)
└── qc_summary.txt             ← QC metrics
```

---

## Module Quick Ref

| Module | Purpose | Key Script |
|--------|---------|------------|
| `geneticqc/qc.nf` | Genetic QC | `process1.sh` |
| `geneticqc/merge.nf` | Merge chunks/chrs | PLINK merge |
| `gwasqc/main.nf` | Kinship/ancestry | `addi_qc_pipeline.py` |
| `gwasprep/covars.nf` | Compute PCA | PLINK PCA |
| `gwasprep/outliers_exclude.nf` | Remove outliers | Python |
| `gwasrun/glm.nf` | GLM analysis | PLINK2 GLM |
| `gwasrun/gallop.nf` | LMM analysis | GALLOP |
| `gwasrun/cph.nf` | Survival analysis | `survival.R` |

---

## Troubleshooting Quick Hits

### Pipeline won't start
```bash
# Check Nextflow version
nextflow -version

# Check config
cat nextflow.config

# Validate params
cat params.yml
```

### Process fails
```bash
# Check work directory
ls -lh work/

# View logs
cat .nextflow.log

# Check specific task
cat work/ab/cd1234.../.command.log
```

### Out of memory
```groovy
// In nextflow.config
process {
  memory = '16 GB'  // Increase
}
```

### Cache issues
```bash
# Clear cache
rm -rf files/longGWAS_pipeline/results/cache/

# Or disable cache in config
```

---

## Refactoring Checklist

Before you start:
- [ ] Understand overall pipeline flow
- [ ] Read `REPOSITORY_GUIDE.md`
- [ ] Trace one example end-to-end
- [ ] Test current pipeline with example data
- [ ] Identify specific pain points

During refactoring:
- [ ] Keep interfaces stable (inputs/outputs)
- [ ] Maintain caching mechanism
- [ ] Test each module individually
- [ ] Compare outputs with original
- [ ] Document changes

After refactoring:
- [ ] Full integration test
- [ ] Performance comparison
- [ ] Update documentation
- [ ] Get code review

---

## Important Notes

⚠️ **Don't break these:**
- Caching mechanism (resume capability)
- File naming conventions (cache lookup)
- Channel structure (parallel processing)

✅ **Safe to change:**
- Internal logic of `process1.sh`
- Script organization
- Error messages
- Logging

🎯 **Focus areas:**
1. `process1.sh` modularization
2. Error handling improvements
3. Better logging
4. Unit test coverage

---

## Resources

- Full docs: `REPOSITORY_GUIDE.md`
- Nextflow docs: https://www.nextflow.io/docs/latest/
- PLINK2 docs: https://www.cog-genomics.org/plink/2.0/
- bcftools docs: http://samtools.github.io/bcftools/

---

**Last Updated:** November 23, 2025
