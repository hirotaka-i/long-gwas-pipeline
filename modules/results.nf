// ==============================================================================
// Results Management Module
// ==============================================================================
// Consolidated module containing GWAS results output processes:
// - SAVEGWAS: Collect and merge GWAS results, publish to output directory
// - MANHATTAN: Generate Manhattan plots from GWAS results
// - TABLEONE: Generate Table 1 and Kaplan-Meier plots for descriptive statistics
// ==============================================================================

process SAVEGWAS {
  scratch true
  label 'two_cpu_large_mem'
  publishDir "${params.analyses_dir}/${params.genetic_cache_key}/${params.analysis_name}/gwas_results/${model}/split", mode: 'copy', overwrite: true, pattern: "*.{results,gallop,coxph}"
  publishDir "${params.analyses_dir}/${params.genetic_cache_key}/${params.analysis_name}/gwas_results/${model}", mode: 'copy', overwrite: true, pattern: "*_allresults.tsv"

  input:
    tuple val(pop_studyarm_pheno), path(sumstats)
    val(model)

  output:
    path(sumstats), emit: res_split
    path "${pop_studyarm_pheno}_allresults.tsv", emit: res_all

  script:
    """
    echo ${pop_studyarm_pheno}
    COUNTER=0
    for file in ${sumstats}
    do
      COUNTER=\$((COUNTER+1))
      if [[ \$COUNTER -eq 1 ]]
      then
        cat \${file} > "${pop_studyarm_pheno}_allresults.tsv"
      else
        tail -n +2 \${file} >> "${pop_studyarm_pheno}_allresults.tsv"
      fi
    done
    bedtools sort -i "${pop_studyarm_pheno}_allresults.tsv" -header > "${pop_studyarm_pheno}_allresults.tsv.tmp"
    mv "${pop_studyarm_pheno}_allresults.tsv.tmp" "${pop_studyarm_pheno}_allresults.tsv"
    """
}

process MANHATTAN {
  scratch true
  label 'two_cpu_large_mem'

  publishDir "${params.analyses_dir}/${params.genetic_cache_key}/${params.analysis_name}/gwas_results/${model}/plots", mode: 'copy', overwrite: true

  input:
    each path(input_file)
    val(model)

  output:
    path "*.png"

  script:
    """
    manhattan.py --input ${input_file} --model ${model}
    """
}

process TABLEONE {
  scratch true
  label 'small'
  
  publishDir "${params.analyses_dir}/${params.genetic_cache_key}/${params.analysis_name}/prepared_data", mode: 'copy', overwrite: true

  input:
    path(analytical_set)
    path covarfile, stageAs: 'covarfile_input.tsv'
    path phenofile, stageAs: 'phenofile_input.tsv'
    each phenoname

  output:
    path "table1_*.csv", optional: true
    path "*_km_plot.png", optional: true

  script:
    """
    make_tableone.py \\
        ${covarfile} \\
        ${phenofile} \\
        ${analytical_set} \\
        --pheno-name '${phenoname}' \\
        --study-arm-col '${params.study_arm_col}' \\
        --time-col '${params.time_col}' \\
        --ancestry '${params.ancestry}' \\
        --analysis-name '${params.analysis_name}' \\
        ${params.covar_numeric     ? "--covar-numeric ${params.covar_numeric}"         : ''} \\
        ${params.covar_categorical ? "--covar-categorical ${params.covar_categorical}" : ''} \\
        ${params.longitudinal_flag ? '--longitudinal' : ''} \\
        ${params.survival_flag     ? '--survival'     : ''}
    """
}
