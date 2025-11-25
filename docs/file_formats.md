# Input File Formats

Complete specification for all input files required by the longitudinal GWAS pipeline.

---

## 1. Genotype Files (VCF)

### Format

**File types accepted:**
- Uncompressed VCF (`.vcf`)
- Compressed VCF (`.vcf.gz`)

**File organization:**
- Files must be split by chromosome
- Each file should contain chromosome identifier with 'chr' prefix (case insensitive)

**Example filenames:**
```
chr1.vcf.gz
chr2.vcf.gz
...
chr22.vcf.gz
```

Or:
```
dataset_chr1_filtered.vcf
dataset_chr2_filtered.vcf
```

### Genotyped vs Imputed Data

**Genotyped data:**
- Hard-called genotypes (0/0, 0/1, 1/1)
- Set `--r2thres -9` to disable imputation quality filtering

**Imputed data:**
- Must include R² (imputation quality) in INFO field
- Set `--r2thres` to filter low-quality variants (e.g., 0.3, 0.8)
- Can include dosage (DS) field for probabilistic genotypes

### VCF Requirements

**Mandatory fields:**
```
#CHROM  POS     ID      REF     ALT     QUAL    FILTER  INFO    FORMAT  sample1 sample2 ...
chr1    100000  .       A       G       .       PASS    .       GT      0/0     0/1     ...
```

**Required INFO fields for imputed data:**
- `R2=` or `INFO=` field with imputation quality score

**Example VCF header:**
```
##fileformat=VCFv4.2
##FILTER=<ID=PASS,Description="All filters passed">
##INFO=<ID=R2,Number=1,Type=Float,Description="Imputation quality">
##FORMAT=<ID=GT,Number=1,Type=String,Description="Genotype">
##FORMAT=<ID=DS,Number=1,Type=Float,Description="Dosage">
#CHROM  POS     ID      REF     ALT     QUAL    FILTER  INFO            FORMAT  sample1 sample2
chr1    100000  .       A       G       .       PASS    R2=0.95         GT:DS   0/0:0   0/1:1.02
chr1    200000  rs123   C       T       .       PASS    R2=0.87         GT:DS   0/1:0.98 1/1:2.0
```

---

## 2. Covariate File (TSV)

### Format

Tab-delimited file with header row.

**Required columns:**
- `#FID`: Family ID (can be 0 for unrelated samples)
- `IID`: Individual/Sample ID (must match VCF sample IDs)
- `PHENO`: Phenotype placeholder (can be 0, not used in analysis)

**Additional covariate columns:**
- Any columns you want to include as covariates
- Common examples: `SEX`, `age_at_baseline`, `study_arm`, `batch`, etc.

### Example

```tsv
#FID	IID	SEX	PHENO	study_arm	apoe4	levodopa_usage	age_at_baseline	education_years
0	sid-1	1	0	control	0	0	35	16
0	sid-2	1	0	control	0	0	40	12
0	sid-3	0	0	control	1	0	32	18
0	sid-4	0	0	PD	0	1	45	14
0	sid-5	1	0	PD	1	0	55	16
0	sid-6	0	0	PD	0	1	66	12
0	sid-7	1	0	PD	0	0	58	20
```

### Column Specifications

| Column | Type | Values | Description |
|--------|------|--------|-------------|
| `#FID` | Integer | Any | Family ID (0 for unrelated) |
| `IID` | String | Match VCF | Individual ID |
| `SEX` | Integer | 0=female, 1=male | Biological sex |
| `PHENO` | Integer | 0 | Placeholder (not used) |
| Custom | Numeric/Binary | Any | Your covariates |

**Notes:**
- PCA components (PC1-PC10) are computed automatically from genetic data
- Specify covariates to use via `--covariates` parameter
- Example: `--covariates "SEX age_at_baseline PC1 PC2 PC3"`

---

## 3. Phenotype Files (TSV)

The phenotype file format varies by analysis type.

### 3.1 Cross-Sectional Analysis

**Required columns:**
- `IID`: Individual ID (must match VCF and covariate file)
- `y`: Outcome variable (or custom column specified by `--pheno_name`)

**Example:**
```tsv
IID	y
sid-1	23.5
sid-2	25.1
sid-3	22.8
sid-4	24.3
sid-5	26.7
sid-6	23.9
sid-7	25.4
```

**Data types:**
- **Continuous:** Any numeric value (e.g., BMI, height, blood pressure)
- **Binary:** 0/1 for case-control studies
- **Count:** Non-negative integers for count outcomes

### 3.2 Longitudinal Analysis

**Required columns:**
- `IID`: Individual ID
- `y`: Outcome variable
- `study_days`: Time since baseline in days (or custom column via `--time_col`)

**Format:**
- Multiple rows per individual (repeated measures)
- Each row represents one time point

**Example:**
```tsv
IID	y	study_days
sid-1	23.5	0
sid-1	24.1	90
sid-1	24.8	180
sid-1	25.2	365
sid-2	25.1	0
sid-2	24.9	90
sid-2	25.3	180
sid-3	22.8	0
sid-3	23.1	90
sid-3	22.5	180
sid-3	23.0	365
```

**Time variable specifications:**
- Must be numeric (days, weeks, months)
- Baseline measurements should be 0 (or earliest time)
- Unbalanced designs are supported (different visit patterns per subject)

### 3.3 Survival Analysis

**Required columns:**
- `IID`: Individual ID
- `surv_y`: Event indicator (or custom via `--pheno_name`)
  - 0 = censored (no event occurred)
  - 1 = event occurred
- `time_to_event`: Time to event or censoring (or custom via `--time_col`)

**Example:**
```tsv
IID	surv_y	time_to_event	age_at_baseline
sid-1	0	1825	55
sid-2	1	730	60
sid-3	0	2190	52
sid-4	1	365	68
sid-5	0	1095	58
sid-6	1	1460	72
sid-7	0	912	63
```

**Column specifications:**

| Column | Type | Values | Description |
|--------|------|--------|-------------|
| `IID` | String | Match VCF | Individual ID |
| `surv_y` | Binary | 0/1 | Event status (0=censored, 1=event) |
| `time_to_event` | Numeric | Days | Time from baseline to event/censoring |

**Notes:**
- Time can be in days, months, or years (specify units consistently)
- All censored subjects (surv_y=0) represent right-censoring
- Time must be > 0 for all subjects

---

## 4. Output File Formats

### 4.1 GWAS Results (TSV)

**Filename:** `gwas_results_{phenotype}.tsv`

**Columns:**

| Column | Description | Example |
|--------|-------------|---------|
| `CHR` | Chromosome | 1, 2, ..., 22 |
| `POS` | Position (hg38) | 123456 |
| `SNP` | Variant ID (chr:pos:ref:alt) | 1:123456:A:G |
| `REF` | Reference allele | A |
| `ALT` | Alternate allele | G |
| `BETA` | Effect size | 0.0234 |
| `SE` | Standard error | 0.0123 |
| `P_VALUE` | P-value | 0.0567 |

**Additional columns (analysis-specific):**
- GLM: `OBS_CT`, `T_STAT`
- GALLOP: `TIME_EFFECT`, `SNP_TIME_INTERACTION`
- CPH: `HR` (hazard ratio), `Z_SCORE`

**Example:**
```tsv
CHR	POS	SNP	REF	ALT	BETA	SE	P_VALUE
1	123456	1:123456:A:G	A	G	0.0234	0.0123	0.0567
1	234567	1:234567:C:T	C	T	-0.0145	0.0098	0.1234
2	345678	2:345678:G:A	G	A	0.0312	0.0145	0.0312
```

### 4.2 Manhattan Plots (PNG)

**Filename:** `manhattan_{phenotype}.png`

**Content:**
- X-axis: Chromosome and position
- Y-axis: -log10(p-value)
- Horizontal lines: Genome-wide significance thresholds
- Generated when `--mh_plot true`

### 4.3 QC Summary (TXT)

**Filename:** `qc_summary.txt`

**Content:**
- Number of variants before/after QC
- Number of samples before/after QC
- Kinship filtering results
- Ancestry filtering results
- MAF distribution
- Missingness statistics

---

## 5. File Naming Conventions

### Input Files

**Consistent naming helps pipeline auto-detection:**

```
Genotypes:
  ✅ chr1.vcf, chr2.vcf, ...
  ✅ dataset_chr1.vcf.gz, dataset_chr2.vcf.gz, ...
  ✅ CHR1.vcf, CHR2.vcf (case insensitive)
  ❌ chromosome1.vcf (missing 'chr' prefix)

Phenotypes:
  ✅ phenotype.cs.tsv (cross-sectional)
  ✅ phenotype.lt.tsv (longitudinal)
  ✅ phenotype.surv.tsv (survival)
  
Covariates:
  ✅ covariates.tsv
  ✅ baseline_covars.tsv
```

### Output Files

Pipeline generates files with consistent naming:

```
files/longGWAS_pipeline/results/
├── gwas_results_y.tsv              # Main results
├── gwas_results_y_adj.tsv          # If --out adj specified
├── manhattan_y.png                 # Manhattan plot
└── qc_summary.txt                  # QC report
```

---

## 6. Sample ID Matching

**Critical requirement:** Sample IDs must match across all files!

### Example of Matching IDs

**VCF header:**
```
#CHROM  POS  ID  REF  ALT  QUAL  FILTER  INFO  FORMAT  sid-1  sid-2  sid-3
```

**Covariate file:**
```
#FID  IID    SEX  ...
0     sid-1  1    ...
0     sid-2  1    ...
0     sid-3  0    ...
```

**Phenotype file:**
```
IID    y
sid-1  23.5
sid-2  25.1
sid-3  22.8
```

### Validation

The pipeline will:
- ✅ Match samples across VCF, covariates, and phenotypes
- ✅ Use only samples present in all files
- ⚠️ Warn about samples missing from any file
- ❌ Error if no samples match across files

---

## 7. Data Type Specifications

### Numeric Formats

**Continuous phenotypes:**
- Decimals allowed: `23.456`
- Scientific notation: `1.23e-5`
- Missing values: `NA`, `.`, or empty

**Binary phenotypes:**
- Use `0` and `1` only
- Missing: `NA` or `-9`

**Counts:**
- Non-negative integers: `0`, `1`, `2`, ...
- Missing: `NA` or `-9`

### Text Encodings

- **File encoding:** UTF-8 (preferred) or ASCII
- **Line endings:** Unix (LF) or Windows (CRLF) - both supported
- **Delimiter:** Tab character (`\t`) for TSV files

---

## 8. Quality Control Recommendations

### Before Running Pipeline

**Check your VCF files:**
```bash
# Verify format
bcftools view -h your_file.vcf.gz | head

# Count samples
bcftools query -l your_file.vcf.gz | wc -l

# Check for required fields
bcftools view -h your_file.vcf.gz | grep "##INFO"
```

**Check your phenotype/covariate files:**
```bash
# View first few lines
head -20 phenotype.tsv

# Count samples
tail -n +2 phenotype.tsv | wc -l

# Check for missing values
grep -c "NA\|^\s*$" phenotype.tsv
```

### Common Issues

| Issue | Solution |
|-------|----------|
| Sample ID mismatch | Ensure IDs are identical across all files |
| Wrong delimiter | Use tabs, not spaces or commas |
| Missing header | First line must be column names |
| Chromosome format | Must include 'chr' prefix (case insensitive) |
| Binary encoding | Save as text files, not Excel format |
| Missing values | Use `NA`, not blank cells |

---

## 9. Example File Templates

### Minimal Cross-Sectional Setup

**phenotype.cs.tsv:**
```tsv
IID	y
sample1	23.5
sample2	25.1
sample3	22.8
```

**covariates.tsv:**
```tsv
#FID	IID	SEX	PHENO
0	sample1	1	0
0	sample2	0	0
0	sample3	1	0
```

### Minimal Longitudinal Setup

**phenotype.lt.tsv:**
```tsv
IID	y	study_days
sample1	23.5	0
sample1	24.1	90
sample2	25.1	0
sample2	24.9	90
```

### Minimal Survival Setup

**phenotype.surv.tsv:**
```tsv
IID	surv_y	time_to_event
sample1	0	1825
sample2	1	730
sample3	0	2190
```

---

## See Also

- **[Parameters](parameters.md)**: Column name specifications via parameters
- **[Examples](examples.md)**: Complete workflow examples
- **[Repository Guide](REPOSITORY_GUIDE.md)**: Quick reference and troubleshooting

