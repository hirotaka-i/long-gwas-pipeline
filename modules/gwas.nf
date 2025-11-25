// ==============================================================================
// GWAS Execution Module
// ==============================================================================
// Consolidated module containing GWAS analysis processes:
// - GWASGLM: Generalized Linear Model analysis (cross-sectional)
// - GWASGALLOP: Longitudinal analysis using GALLOP
// - GWASCPH: Survival analysis using Cox Proportional Hazards
// ==============================================================================

process GWASGLM {
  scratch true
  label 'medium'

  input:
    tuple val(fSimple), path(plog), path(pgen), path(psam), path(pvar)
    each samplelist
    each phenoname

  output:
    tuple env(KEY), path("*.results")

  script:
    def covariates = "${params.covariates}".replaceAll(/ /, ",")
    def m = []
    def cohort = samplelist.getName()
    m = cohort =~ /(.*)_analyzed.tsv/
    cohort = m[0][1]
    def outfile = "${cohort}_${fSimple}.${params.out}"

    """
    set -x
    KEY="${cohort}_${phenoname}"

    glm_phenocovar.py \
        --pheno_covar ${samplelist} \
        --phenname ${phenoname} \
        --covname "${params.covariates}"

    plink2 --pfile ${fSimple} \
            --glm hide-covar omit-ref cols=+beta,+a1freq \
            --pheno "pheno.tsv" \
            --pheno-name ${phenoname} \
            --covar "covar.tsv" \
            --covar-name ${covariates} \
            --covar-variance-standardize \
            --keep "pheno.tsv" \
            --output-chr chrM \
            --mac ${params.minor_allele_ct} \
            --hwe 1e-6 \
            --threads ${task.cpus} \
            --memory ${task.memory.toMega()} \
            --out ${outfile}

    if [ -f ${outfile}.${phenoname}.glm.logistic.hybrid ]; then
        mv ${outfile}.${phenoname}.glm.logistic.hybrid ${outfile}.${phenoname}.results
    fi
    
    if [ -f ${outfile}.${phenoname}.glm.linear ]; then
        mv ${outfile}.${phenoname}.glm.linear ${outfile}.${phenoname}.results
    fi
    """
}

process GWASGALLOP {
  scratch true
  label 'medium'

  input:
    tuple val(fSimple), path(samplelist), path(rawfile)
    path x, stageAs: 'phenotypes.tsv'
    each phenoname

  output:
    tuple env(KEY), path("*.gallop")

  script:
    def m = []
    def outfile = rawfile.getName()
    m = outfile =~ /(.*).raw/
    outfile = "${m[0][1]}.${params.out}"

    def getkey = []
    def pop_pheno = samplelist.getName()
    getkey = pop_pheno =~ /(.*)_filtered.pca.tsv/
    pop_pheno = getkey[0][1]

    def model = ""
    if (params.model != '') {
      model = "--model '${params.model}'"
    }

    """
    set -x
    KEY="${pop_pheno}_${phenoname}"

    gallop --gallop \
           --rawfile ${rawfile} \
           --pheno "phenotypes.tsv" \
           --pheno-name "${phenoname}" \
           --covar ${samplelist} \
           --covar-name ${params.covariates} \
           --time-name ${params.time_col} \
           --out "${outfile}"
    """
}

process GWASCPH {
  scratch true
  label 'medium'

  input:
    tuple val(fSimple), path(samplelist), path(rawfile)
    path x, stageAs: 'phenotypes.tsv'
    each phenoname

  output:
    tuple env(KEY), path("*.coxph")
  
  script:
    def m = []
    def outfile = rawfile.getName()
    m = outfile =~ /(.*).raw/
    outfile = "${m[0][1]}.${params.out}.coxph"

    def getkey = []
    def pop_pheno = samplelist.getName()
    getkey = pop_pheno =~ /(.*)_filtered.pca.tsv/
    pop_pheno = getkey[0][1]

    """
    set -x
    KEY="${pop_pheno}_${phenoname}"
    
    survival.R --rawfile ${rawfile} \
               --pheno "phenotypes.tsv" \
               --covar ${samplelist} \
               --covar-name "${params.covariates}" \
               --pheno-name "${phenoname}" \
               --out ${outfile}
    """
}
