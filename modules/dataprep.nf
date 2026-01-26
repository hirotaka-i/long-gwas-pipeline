/*
 * Consolidated Data Preparation Module
 * Contains all data preparation processes:
 * - MAKEANALYSISSETS: Extract study arms and filter samples (outliers, kinship)
 * - COMPUTE_PCA: Compute principal components for each study arm
 * - MERGE_PCA: Merge PCA results with sample data
 * - GALLOPCOX_INPUT: Prepare input chunks for GALLOP/CPH analysis
 * - RAWFILE_EXPORT: Export raw files for longitudinal/survival analysis
 * - EXPORT_PLINK: Export PLINK format for GLM analysis
 */

process MAKEANALYSISSETS {
  scratch true
  label 'two_cpu_large_mem'
  cache 'deep'
  publishDir "${ANALYSES_DIR}/${params.genetic_cache_key}/${params.analysis_name}/prepared_data", mode: 'copy', overwrite: true

  input:
    path samplelist
    path covarfile, stageAs: 'covariates.tsv'
  output:
    path "${params.ancestry}_*_filtered.tsv", emit: study_arm_files
    path "${params.ancestry}_all.tsv", emit: analytical_set

  script:
    """
    make_analysis_sets.py "${samplelist}" covariates.tsv "${params.ancestry}" "${params.study_arm_col}" "${params.kinship}"
    """
}

process COMPUTE_PCA {
  scratch true
  label 'large'
  publishDir "${ANALYSES_DIR}/${params.genetic_cache_key}/${params.analysis_name}/prepared_data/pca", mode: 'copy', overwrite: true, pattern: "*.eigenvec"
  publishDir "${ANALYSES_DIR}/${params.genetic_cache_key}/${params.analysis_name}/prepared_data/logs", mode: 'copy', overwrite: true, pattern: "*.log"

  input:
    each path(samplelist)
    path "*"
    
  output:
    tuple path(samplelist), path("${study_arm_prefix}.pca.eigenvec"), emit: eigenvec

  script:
    def m = []
    def study_arm = ""
    study_arm = samplelist.getName()
    m = study_arm =~ /(.*)_filtered.tsv/
    study_arm = m[0][1]
    study_arm_prefix = "${study_arm}"
    
    """
    plink2 \
          --indep-pairwise 50 .2 \
          --maf ${params.minor_allele_freq} \
          --pfile "allchr_merged" \
          --out ${study_arm}.ld

    plink2 \
          --keep ${samplelist} \
          --out ${study_arm}.pca \
          --extract ${study_arm}.ld.prune.in \
          --pca 10 \
          --threads ${task.cpus} \
          --memory ${task.memory.toMega()} \
          --pfile "allchr_merged"
    """
}

process MERGE_PCA {
  scratch true
  label 'small'
  publishDir "${ANALYSES_DIR}/${params.genetic_cache_key}/${params.analysis_name}/prepared_data", mode: 'copy', overwrite: true
  
  input:
    tuple path(samplelist), path(study_arm_pca)
  
  output:
    path "${params.ancestry}_*_filtered.pca.tsv"
  
  script:
    """
     #!/usr/bin/env python3
     import pandas as pd
     import time   
     import os
     
     print(os.listdir())
     sample_fn = "${samplelist.getName()}"
     study_arm = sample_fn[:-(len('_filtered.tsv'))]
     pc_fn = study_arm + '.pca.eigenvec'

     print(pc_fn, study_arm)
     pc_df = pd.read_csv(pc_fn, sep="\\t")
     samples_df = pd.read_csv(sample_fn, sep="\\t")
     pc_df.rename(columns={"#IID": "IID"}, inplace=True)
     samples_df = samples_df.merge(pc_df, on="IID")
     
     samples_df.to_csv(study_arm + '_filtered.pca.tsv', sep="\\t", index=False)
     time.sleep(5)
     """
}

process RAWFILE_EXPORT {
  scratch true
  label 'small'
  publishDir "${ANALYSES_DIR}/${params.genetic_cache_key}/${params.analysis_name}/prepared_data/logs", mode: 'copy', overwrite: true, pattern: "*.log"

  input:
    tuple val(fileTag), path(plinkFiles)
    each path(samplelist)

  output:
    tuple val(fileTag), path(samplelist), path('*.raw'), emit: gwas_rawfile
    path "*.log", emit: gwas_rawfile_log

  when:
    params.longitudinal_flag || params.survival_flag

  script:
    def study_arm = ""
    study_arm = samplelist.getName()
    m = study_arm =~ /(.*)_filtered.pca.tsv/
    study_arm = m[0][1]
    def filtered_prefix = "${study_arm}_${fileTag}_filtered"

    """
    set -euo pipefail
    
    # Step 1: Apply all filters once to create filtered plink file
    echo "Filtering ${fileTag} with MAF, HWE, and sample filters..."
    
    plink2 \
        --pfile ${fileTag} \
        --keep ${samplelist} \
        --mac ${params.minor_allele_ct} \
        --hwe 1e-6 \
        --update-sex ${samplelist} \
        --pheno ${samplelist} \
        --pheno-col-nums 4 \
        --make-pgen \
        --threads ${task.cpus} \
        --memory ${task.memory.toMega()} \
        --out ${filtered_prefix}
    
    # Step 2: Generate chunks from filtered pvar file using awk
    echo "Generating chunks from filtered variants..."
    
    awk -v chunk_size=${params.chunk_size} '
        BEGIN { count=0; start=""; }
        !/^#/ {
            vid = \$3;
            count++;
            if (start == "") start = vid;
            
            if (count >= chunk_size) {
                print start "\\t" vid;
                start = "";
                count = 0;
            }
        }
        END { if (count > 0) print start "\\t" vid; }
    ' ${filtered_prefix}.pvar > chunks.txt
    
    NUM_CHUNKS=\$(wc -l < chunks.txt)
    echo "Generated \${NUM_CHUNKS} chunks for ${fileTag} (after filtering)"
    
    # Step 3: Export .raw files from filtered plink file
    while IFS=\$'\\t' read -r from_var to_var; do
        nameout="${study_arm}_${fileTag}_\${from_var}_\${to_var}"
        echo "Exporting chunk: \${from_var} to \${to_var}"
        
        plink2 \
            --pfile ${filtered_prefix} \
            --export A \
            --from \${from_var} \
            --to \${to_var} \
            --out \${nameout} \
            --threads ${task.cpus} \
            --memory ${task.memory.toMega()}
    done < chunks.txt
    """
}

process EXPORT_PLINK {
  debug false
  scratch true
  label 'small'
  
  publishDir "${ANALYSES_DIR}/${params.genetic_cache_key}/${params.analysis_name}/prepared_data", mode: 'copy', overwrite: true, pattern: "*_filtered.pca.pheno.tsv"
  publishDir "${ANALYSES_DIR}/${params.genetic_cache_key}/${params.analysis_name}/prepared_data", mode: 'copy', overwrite: true, pattern: "*_covar_names.txt"
  publishDir "${ANALYSES_DIR}/${params.genetic_cache_key}/${params.analysis_name}/prepared_data", mode: 'copy', overwrite: true, pattern: "*_n_covar.txt"
  publishDir "${ANALYSES_DIR}/${params.genetic_cache_key}/${params.analysis_name}/prepared_data/logs", mode: 'copy', overwrite: true, pattern: "*_preprocessing.log"

  input:
    path samplelist
    path x, stageAs: 'phenotypes.tsv'
  output:
    path "*_filtered.pca.pheno.tsv", optional: true
    path "*_covar_names.txt", optional: true
    path "*_n_covar.txt", optional: true
    path "*_preprocessing.log", optional: true

  script:
    def m = []
    def study_arm = ""
    study_arm = samplelist.getName()
    m = study_arm =~ /(.*)_filtered.pca.tsv/
    outfile = "${m[0][1]}"

    def pheno_name = "y"
    if (params.pheno_name != '') {
      pheno_name = "${params.pheno_name}"
    }

    """
    export_plink_preprocess.py \\
        --samplelist ${samplelist} \\
        --phenofile phenotypes.tsv \\
        --outfile ${outfile} \\
        --pheno-name "${pheno_name}" \\
        --covar-numeric "${params.covar_numeric}" \\
        --covar-categorical "${params.covar_categorical}" \\
        --covar-interact "${params.covar_interact}"
    """
}
