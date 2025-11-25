# Examples

This page provides practical examples for running the longitudinal GWAS pipeline with different analysis types.

## Prerequisites

First, extract the example dataset:

```bash
cd long-gwas-pipeline
tar -xzf example/genotype/example.vcf.tar.gz
```

---

## Example 1: Cross-Sectional Analysis (GLM)

### Using params.yml (Recommended)

Create a parameter file `params_example_cs.yml`:

```yaml
input: "example/genotype/*.vcf"
phenofile: example/phenotype.cs.tsv
covarfile: example/covariates.tsv

pheno_name: y
covariates: "SEX age_at_baseline"

linear_flag: true
longitudinal_flag: false
survival_flag: false

assembly: hg19
dataset: example_cs
r2thres: -9
minor_allele_freq: "0.05"
kinship: "0.177"
ancestry: "EUR"

mh_plot: true
```

Run the pipeline:

```bash
nextflow run main.nf -profile standard -params-file params_example_cs.yml
```

### Using Command Line

```bash
nextflow run main.nf -profile standard \
  --input "example/genotype/*.vcf" \
  --phenofile example/phenotype.cs.tsv \
  --covarfile example/covariates.tsv \
  --linear_flag true \
  --assembly hg19 \
  --dataset example_cs
```

---

## Example 2: Longitudinal Analysis (GALLOP/LMM)

### Using params.yml (Recommended)

Create a parameter file `params_example_lt.yml`:

```yaml
input: "example/genotype/*.vcf"
phenofile: example/phenotype.lt.tsv
covarfile: example/covariates.tsv

pheno_name: y
covariates: "SEX age_at_baseline"
time_col: study_days

linear_flag: false
longitudinal_flag: true
survival_flag: false

assembly: hg19
dataset: example_lt
r2thres: -9
minor_allele_freq: "0.05"
kinship: "0.177"
ancestry: "EUR"

mh_plot: true
```

Run the pipeline:

```bash
nextflow run main.nf -profile standard -params-file params_example_lt.yml
```

### Using Command Line

```bash
nextflow run main.nf -profile standard \
  --input "example/genotype/*.vcf" \
  --phenofile example/phenotype.lt.tsv \
  --covarfile example/covariates.tsv \
  --longitudinal_flag true \
  --time_col study_days \
  --assembly hg19 \
  --dataset example_lt
```

---

## Example 3: Survival Analysis (Cox Proportional Hazards)

### Using params.yml (Recommended)

Create a parameter file `params_example_surv.yml`:

```yaml
input: "example/genotype/*.vcf"
phenofile: example/phenotype.surv.tsv
covarfile: example/covariates.tsv

pheno_name: surv_y
covariates: "SEX age_at_baseline"
time_col: time_to_event

linear_flag: false
longitudinal_flag: false
survival_flag: true

assembly: hg19
dataset: example_surv
r2thres: -9
minor_allele_freq: "0.05"
kinship: "0.177"
ancestry: "EUR"

mh_plot: true
```

Run the pipeline:

```bash
nextflow run main.nf -profile standard -params-file params_example_surv.yml
```

### Using Command Line

```bash
nextflow run main.nf -profile standard \
  --input "example/genotype/*.vcf" \
  --phenofile example/phenotype.surv.tsv \
  --covarfile example/covariates.tsv \
  --survival_flag true \
  --pheno_name surv_y \
  --time_col time_to_event \
  --assembly hg19 \
  --dataset example_surv
```

---

## Example 4: Using Different Profiles

### Local Testing with Custom Docker Image

```bash
# Build local Docker image first
docker build --platform linux/amd64 -f Dockerfile.ubuntu22 -t longgwas-local-test .

# Run with localtest profile
nextflow run main.nf -profile localtest -params-file params_example_cs.yml
```

### NIH Biowulf HPC with Singularity

```bash
nextflow run main.nf -profile biowulf -params-file params_example_cs.yml
```

### Google Cloud Life Sciences

```bash
nextflow run main.nf -profile gls -params-file params_example_cs.yml
```

---

## Example 5: Resume Failed Run

If a pipeline run fails or is interrupted, you can resume from the last successful step:

```bash
nextflow run main.nf -profile standard -params-file params_example_cs.yml -resume
```

---

## Example 6: Custom QC Parameters

### Imputed Data with R² Filtering

For imputed genotype data, set R² threshold to filter low-quality variants:

```yaml
input: "data/imputed_chr*.vcf.gz"
phenofile: phenotype.tsv
covarfile: covariates.tsv

r2thres: 0.3              # Filter variants with R² < 0.3
minor_allele_freq: "0.01" # Lower MAF for larger sample size
kinship: "0.0884"         # Filter 2nd degree relatives
assembly: hg38            # Already in hg38 (no liftover needed)

linear_flag: true
dataset: my_imputed_gwas
```

### Strict QC Parameters

```yaml
r2thres: 0.8              # Very strict imputation quality
minor_allele_freq: "0.05" # Standard MAF threshold
kinship: "0.177"          # Filter 1st degree relatives only
```

---

## Expected Outputs

After successful completion, results will be in:

```
files/longGWAS_pipeline/results/
├── gwas_results_{phenotype}.tsv    # Association statistics
├── manhattan_{phenotype}.png        # Manhattan plot (if mh_plot: true)
└── qc_summary.txt                   # QC metrics
```

### Result File Format

The `gwas_results_{phenotype}.tsv` contains:

```
CHR  POS       SNP              REF ALT BETA      SE        P_VALUE
1    123456    1:123456:A:G     A   G   0.0234    0.0123    0.0567
1    234567    1:234567:C:T     C   T   -0.0145   0.0098    0.1234
...
```

---

## Troubleshooting Examples

### Check Pipeline Progress

```bash
# View Nextflow log
tail -f .nextflow.log

# Check specific process output
cat work/ab/cd1234.../.command.log
```

### Clean Work Directory

If you need to start completely fresh:

```bash
# Remove work directory and cache
rm -rf work/ .nextflow/ .nextflow.log
rm -rf files/longGWAS_pipeline/results/cache/

# Run pipeline from scratch
nextflow run main.nf -profile standard -params-file params.yml
```

---

## Additional Resources

- **[Parameters Reference](parameters.md)**: Complete list of all parameters
- **[File Formats](file_formats.md)**: Input file specifications
- **[Profiles Explained](PROFILES_EXPLAINED.md)**: Detailed profile configurations
- **[Repository Guide](REPOSITORY_GUIDE.md)**: Quick reference and troubleshooting

