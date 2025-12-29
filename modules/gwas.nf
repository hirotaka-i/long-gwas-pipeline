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
    tuple val(fileTag), path(plog), path(pgen), path(psam), path(pvar)
    each path(samplelist)
    each phenoname

  output:
    tuple env(KEY), path("*.results")

  script:
    def m = []
    def study_arm = samplelist.getName()
    m = study_arm =~ /(.*)_filtered\.pca\.pheno\.tsv/
    study_arm = m[0][1]
    def outfile = "${study_arm}_${fileTag}"

    """
    set -x
    KEY="${study_arm}_${phenoname}"

    # Extract all covariate column names from the analyzed file (excluding #FID, IID, and phenotype)
    awk 'NR==1 {first=1; for(i=1;i<=NF;i++){if(\$i!="#FID" && \$i!="IID" && \$i!="${phenoname}") {if(!first) printf ","; printf "%s", \$i; first=0}}} END {print ""}' ${samplelist} > covar_names.txt
    COVAR_NAMES=\$(cat covar_names.txt)

    # If interaction term is specified, reorder covariates to put interaction covariate first
    if [ -n "${params.covar_interact}" ]; then
        # Extract interaction covariate and remaining covariates
        INTERACT_COVAR="${params.covar_interact}"
        OTHER_COVARS=\$(echo "\${COVAR_NAMES}" | tr ',' '\n' | grep -v "^\${INTERACT_COVAR}\$" | paste -sd ',' -)
        COVAR_NAMES="\${INTERACT_COVAR},\${OTHER_COVARS}"
        
        # Count total number of covariates
        N_COVAR=\$(echo "\${COVAR_NAMES}" | tr ',' '\n' | wc -l | tr -d ' ')
        echo "Interaction analysis: \${INTERACT_COVAR} as first covariate"
        echo "Total covariates: \${N_COVAR}"
    fi

    glm_phenocovar.py \
        --pheno_covar ${samplelist} \
        --phenname ${phenoname} \
        --covname "\${COVAR_NAMES//,/ }"

    # Build plink2 command with optional interaction parameters
    if [ -n "${params.covar_interact}" ]; then
        # With interaction: test SNP main effect and SNP*covariate interaction
        INTERACTION_IDX=\$((N_COVAR + 2))
        plink2 --pfile ${fileTag} \
                --glm interaction omit-ref cols=+beta,+a1freq \
                --pheno "pheno.tsv" \
                --pheno-name ${phenoname} \
                --covar "covar.tsv" \
                --covar-name \${COVAR_NAMES} \
                --covar-variance-standardize \
                --keep "pheno.tsv" \
                --output-chr chrM \
                --mac ${params.minor_allele_ct} \
                --hwe 1e-6 \
                --parameters 1-\${INTERACTION_IDX} \
                --tests 1,\${INTERACTION_IDX} \
                --threads ${task.cpus} \
                --memory ${task.memory.toMega()} \
                --out ${outfile}_all_vars
        
        # Reorganize results: ADD as base, join interaction and 2DF columns
        # Use awk to dynamically find columns and reshape data
        INTERACT_TEST="ADDx${params.covar_interact}"
        for glm_file in ${outfile}_all_vars.${phenoname}.glm.{linear,logistic.hybrid}; do
            if [ -f "\${glm_file}" ]; then
                output_file=\${glm_file/_all_vars/}
                awk -v interact_test="\${INTERACT_TEST}" 'BEGIN{FS="\t"; OFS="\t"} 
                     NR==1 {
                         # Find column indices
                         for(i=1;i<=NF;i++) {
                             if(\$i=="ID") idcol=i;
                             if(\$i=="TEST") testcol=i;
                             if(\$i=="BETA") betacol=i;
                             if(\$i=="SE") secol=i;
                             if(\$i=="P") pcol=i;
                         }
                         # Print base header plus interaction columns
                         print \$0, "BETAi", "SEi", "Pi", "P_2DF";
                         next;
                     }
                     {
                         id = \$idcol;
                         test = \$testcol;
                         
                         if(test == "ADD") {
                             # Store base ADD row
                             add[id] = \$0;
                         } else if(test == interact_test) {
                             # Store interaction columns for specific interaction term
                             interact_beta[id] = \$betacol;
                             interact_se[id] = \$secol;
                             interact_p[id] = \$pcol;
                         } else if(test == "USER_2DF") {
                             # Store 2DF p-value
                             twodf_p[id] = \$pcol;
                         }
                     }
                     END {
                         # Output combined rows
                         for(id in add) {
                             beta_i = (id in interact_beta) ? interact_beta[id] : "NA";
                             se_i = (id in interact_se) ? interact_se[id] : "NA";
                             p_i = (id in interact_p) ? interact_p[id] : "NA";
                             p_2df = (id in twodf_p) ? twodf_p[id] : "NA";
                             print add[id], beta_i, se_i, p_i, p_2df;
                         }
                     }' "\${glm_file}" > "\${output_file}"
            fi
        done
        
    else
        # Standard analysis without interaction
        plink2 --pfile ${fileTag} \
                --glm hide-covar omit-ref cols=+beta,+a1freq \
                --pheno "pheno.tsv" \
                --pheno-name ${phenoname} \
                --covar "covar.tsv" \
                --covar-name \${COVAR_NAMES} \
                --covar-variance-standardize \
                --keep "pheno.tsv" \
                --output-chr chrM \
                --mac ${params.minor_allele_ct} \
                --hwe 1e-6 \
                --threads ${task.cpus} \
                --memory ${task.memory.toMega()} \
                --out ${outfile}
    fi

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
    tuple val(fileTag), path(samplelist), path(rawfile)
    path x, stageAs: 'phenotypes.tsv'
    each phenoname

  output:
    tuple env(KEY), path("*.gallop")

  script:
    def m = []
    def outfile = rawfile.getName()
    m = outfile =~ /(.*).raw/
    outfile = "${m[0][1]}"

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

    gallop.py --gallop \
           --rawfile ${rawfile} \
           --pheno "phenotypes.tsv" \
           --pheno-name "${phenoname}" \
           --covar ${samplelist} \
           --covar-name ${params.covariates} \
           ${params.covar_categorical ? "--covar-cat-name ${params.covar_categorical}" : ""} \
           --time-name ${params.time_col} \
           --out "${outfile}"
    """
}

process GWASCPH {
  scratch true
  label 'medium'

  input:
    tuple val(fileTag), path(samplelist), path(rawfile)
    path x, stageAs: 'phenotypes.tsv'
    each phenoname

  output:
    tuple env(KEY), path("*.coxph")
  
  script:
    def m = []
    def outfile = rawfile.getName()
    m = outfile =~ /(.*).raw/
    outfile = "${m[0][1]}.coxph"

    def getkey = []
    def pop_pheno = samplelist.getName()
    getkey = pop_pheno =~ /(.*)_filtered.pca.tsv/
    pop_pheno = getkey[0][1]

    """
    set -x
    KEY="${pop_pheno}_${phenoname}"
    
    echo "Processing: ${rawfile.name}"
    echo "Available files:"
    ls -la *.raw *.tsv 2>/dev/null || echo "No files found"
    
    survival.R --rawfile ${rawfile} \
               --pheno "phenotypes.tsv" \
               --covar ${samplelist} \
               --covar-name "${params.covariates}" \
               --covar-categorical "${params.covar_categorical}" \
               ${params.covar_interact ? "--covar-interact \"${params.covar_interact}\"" : ""} \
               --pheno-name "${phenoname}" \
               --out ${outfile}
    """
}
