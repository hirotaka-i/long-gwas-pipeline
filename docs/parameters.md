# Pipeline Parameters Reference

Complete reference for all parameters supported by the longitudinal GWAS pipeline.

---

## Input Files

### `--input`

**Type:** String (glob pattern)  
**Required:** Yes  
**Description:** Path pattern for input VCF files. Supports uncompressed (*.vcf) or compressed (*.vcf.gz) files.

**Requirements:**
- Files should be split by chromosome
- Each file should contain chromosome number prefixed with 'chr' (case insensitive)
- Wildcards require quotes

**Examples:**
```bash
--input "data/chr*.vcf"
--input "data/dataset_chr*_suffix.vcf.gz"
--input "/path/to/genotypes/chr[1-22].vcf.gz"
```

**Note:** Old parameter name `--input_vcf` is deprecated. Use `--input` instead.

---

### `--phenofile`

**Type:** String (file path)  
**Required:** Yes  
**Description:** Path to phenotype/outcome file in TSV format.

**Format requirements:**
- **Cross-sectional:** Minimum columns: `IID`, `y`
- **Longitudinal:** Minimum columns: `IID`, `y`, `study_days`
- **Survival:** Minimum columns: `IID`, `surv_y`, `time_to_event`

**Example files:**
- `phenotype.cs.tsv` - Cross-sectional
- `phenotype.lt.tsv` - Longitudinal
- `phenotype.surv.tsv` - Survival

See [File Formats](file_formats.md) for detailed specifications.

---

### `--covarfile`

**Type:** String (file path)  
**Required:** Yes  
**Description:** Path to covariates file in TSV format. Each subject must have corresponding covariates.

**Format requirements:**
- Required columns: `#FID`, `IID`, covariates
- Common covariates: `SEX`, `age_at_baseline`
- PCA components added automatically by pipeline

**Example:**
```bash
--covarfile "data/covariates.tsv"
```

---

## Phenotype/Covariate Configuration

### `--pheno_name`

**Type:** String  
**Default:** `'y'`  
**Description:** Column name in phenotype file containing the outcome variable.

**Examples:**
```bash
--pheno_name y              # Default for cross-sectional
--pheno_name surv_y         # For survival analysis
--pheno_name bmi            # Custom phenotype name
```

---

### `--covariates`

**Type:** String (space-delimited)  
**Default:** `"SEX PC1 PC2 PC3"`  
**Description:** Covariates to include in the model from covariate file and computed PCA components.

**Examples:**
```bash
--covariates "SEX age_at_baseline PC1 PC2 PC3 PC4 PC5"
--covariates "SEX age age_squared PC1 PC2 PC3"
```

**Note:** PC components (PC1-PC10) are automatically computed from genetic data.

---

### `--time_col`

**Type:** String  
**Default:** `'study_days'`  
**Description:** Column name for time variable in longitudinal or survival analysis.

**Usage:**
- **Longitudinal:** Time since baseline (in days) for repeated measures
- **Survival:** Time to event or censoring

**Examples:**
```bash
--time_col study_days       # Longitudinal analysis
--time_col time_to_event    # Survival analysis
```

---

## Analysis Type Flags

### `--linear_flag`

**Type:** Boolean  
**Default:** `true`  
**Description:** Perform cross-sectional GWAS using Generalized Linear Models (GLM).

**Usage:**
```bash
--linear_flag true          # Cross-sectional analysis
```

**Mutually exclusive with:** `--longitudinal_flag`, `--survival_flag`

---

### `--longitudinal_flag`

**Type:** Boolean  
**Default:** `false`  
**Description:** Perform longitudinal GWAS using Linear Mixed Models (GALLOP algorithm).

**Requirements:**
- Phenotype file must include `study_days` column (or column specified by `--time_col`)
- Repeated measurements per subject

**Usage:**
```bash
--longitudinal_flag true
--time_col study_days
```

**Mutually exclusive with:** `--linear_flag`, `--survival_flag`

---

### `--survival_flag`

**Type:** Boolean  
**Default:** `false`  
**Description:** Perform survival analysis using Cox Proportional Hazards models.

**Requirements:**
- Phenotype file must include time-to-event column
- Phenotype variable indicates event occurrence (0/1)

**Usage:**
```bash
--survival_flag true
--pheno_name surv_y
--time_col time_to_event
```

**Mutually exclusive with:** `--linear_flag`, `--longitudinal_flag`

---

## Genome Assembly & QC

### `--assembly`

**Type:** String  
**Default:** `'hg38'`  
**Allowed values:** `'hg18'`, `'hg19'`, `'hg38'`  
**Description:** Genome assembly of input VCF files. Pipeline outputs are always in hg38.

**Behavior:**
- If `hg18` or `hg19`: Variants are lifted over to hg38
- If `hg38`: No coordinate conversion needed

**Examples:**
```bash
--assembly hg19             # Lift hg19 to hg38
--assembly hg38             # Already in hg38
```

---

### `--r2thres`

**Type:** Float  
**Default:** `-9`  
**Description:** Imputation quality (R²) threshold for filtering variants.

**Usage:**
- `-9`: No R² filtering (for genotyped data)
- `0.3` - `0.8`: Filter imputed variants (typical range)

**Examples:**
```bash
--r2thres -9                # Genotyped data (no filtering)
--r2thres 0.3               # Keep variants with R² ≥ 0.3
--r2thres 0.8               # Strict filtering for imputed data
```

---

### `--minor_allele_freq`

**Type:** String  
**Default:** `"0.05"`  
**Description:** Minor Allele Frequency (MAF) threshold. Variants below this threshold are excluded.

**Examples:**
```bash
--minor_allele_freq "0.05"  # Standard (5%)
--minor_allele_freq "0.01"  # For larger sample sizes
--minor_allele_freq "0.001" # Rare variant analysis
```

---

### `--kinship`

**Type:** String  
**Default:** `"0.177"`  
**Description:** Kinship coefficient threshold for filtering related individuals.

**Common thresholds:**
- `0.0884`: 2nd degree relatives (half-siblings, grandparent-grandchild)
- `0.177`: 1st degree relatives (parent-child, full siblings)
- `0.354`: Duplicates/identical twins

**Examples:**
```bash
--kinship "0.177"           # Filter 1st degree relatives (default)
--kinship "0.0884"          # Filter 2nd degree relatives
```

---

### `--ancestry`

**Type:** String  
**Default:** `'EUR'`  
**Allowed values:** `'EUR'`, `'SAS'`, `'AFR'`, `'EAS'`, `'AMR'`  
**Description:** Ancestry group for population stratification and QC.

**Examples:**
```bash
--ancestry EUR              # European ancestry
--ancestry SAS              # South Asian ancestry
```

---

## Pipeline Management

### `--dataset`

**Type:** String  
**Default:** `''`  
**Required:** Highly recommended  
**Description:** Unique identifier for caching intermediate results. Enables resume capability across runs.

**Purpose:**
- Cache QC'd genotype data
- Cache PCA results
- Avoid reprocessing unchanged data

**Examples:**
```bash
--dataset my_gwas_2025      # Descriptive identifier
--dataset cohort_eur_v2     # Version tracking
```

**⚠️ Important:** Always set this to avoid cache conflicts between different datasets!

---

### `--out`

**Type:** String  
**Default:** `''`  
**Description:** Output suffix for result files to distinguish multiple runs.

**Examples:**
```bash
--out adj_age               # Results: gwas_results_y_adj_age.tsv
--out maf01                 # Results: gwas_results_y_maf01.tsv
```

---

### `--mh_plot`

**Type:** Boolean  
**Default:** `true`  
**Description:** Generate Manhattan and QQ plots for GWAS results.

**Examples:**
```bash
--mh_plot true              # Generate plots (default)
--mh_plot false             # Skip plot generation
```

---

## Advanced Parameters

### `--model`

**Type:** String  
**Default:** Not set  
**Description:** Custom model specification for longitudinal analysis with higher-order terms.

**Usage:**
```bash
--model "y ~ snp + time + snp*time + age + (1|subject)"
```

**Note:** For cross-sectional analysis, add higher-order terms as columns in covariate file.

---

### `--chunk_size`

**Type:** Integer  
**Default:** `30000`  
**Description:** Number of variants per chunk for parallel processing during QC.

**Tuning:**
- Smaller values: More parallelization, more overhead
- Larger values: Less parallelization, more memory per task

**Examples:**
```bash
--chunk_size 30000          # Default
--chunk_size 50000          # Fewer, larger chunks
--chunk_size 10000          # More, smaller chunks
```

---

## Complete Example

### params.yml (Recommended approach)

```yaml
# Input files
input: "data/chr*.vcf.gz"
phenofile: "phenotypes/bmi_longitudinal.tsv"
covarfile: "covariates/baseline_covars.tsv"

# Phenotype configuration
pheno_name: bmi
covariates: "SEX age_at_baseline PC1 PC2 PC3 PC4 PC5"
time_col: study_days

# Analysis type
linear_flag: false
longitudinal_flag: true
survival_flag: false

# QC parameters
assembly: hg19
r2thres: 0.3
minor_allele_freq: "0.01"
kinship: "0.177"
ancestry: EUR

# Pipeline settings
dataset: bmi_study_2025
out: main_analysis
mh_plot: true
chunk_size: 30000
```

### Command line equivalent

```bash
nextflow run main.nf -profile standard -params-file params.yml
```

---

## Parameter Validation

The pipeline validates parameters before execution:

✅ **Valid:**
```bash
--linear_flag true --longitudinal_flag false --survival_flag false
```

❌ **Invalid (multiple analysis flags):**
```bash
--linear_flag true --longitudinal_flag true
```

❌ **Invalid (missing required time column):**
```bash
--longitudinal_flag true
# Missing --time_col or phenotype file doesn't have study_days
```

---

## Migration from Old Parameters

| Old Parameter | New Parameter | Notes |
|--------------|---------------|-------|
| `--input_vcf` | `--input` | Functionality unchanged |
| N/A | `--time_col` | New parameter for flexibility |
| N/A | `--survival_flag` | New analysis type |

---

## See Also

- **[Examples](examples.md)**: Practical usage examples
- **[File Formats](file_formats.md)**: Input file specifications
- **[Quick Reference](QUICK_REFERENCE.md)**: Fast parameter lookup
- **[Profiles](PROFILES_EXPLAINED.md)**: Execution environment configurations


