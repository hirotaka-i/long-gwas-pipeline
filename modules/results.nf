// ==============================================================================
// Results Management Module
// ==============================================================================
// Consolidated module containing GWAS results output processes:
// - SAVEGWAS: Collect and merge GWAS results, publish to output directory
// - MANHATTAN: Generate Manhattan plots from GWAS results
// ==============================================================================

process SAVEGWAS {
  scratch true
  label 'two_cpu_large_mem'
  publishDir "${ANALYSES_DIR}/${params.genetic_cache_key}/${params.analysis_name}/gwas_results/${model}/split", mode: 'copy', overwrite: true, pattern: "*.{results,gallop,coxph}"
  publishDir "${ANALYSES_DIR}/${params.genetic_cache_key}/${params.analysis_name}/gwas_results/${model}", mode: 'copy', overwrite: true, pattern: "*_allresults.tsv"

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
  label 'medium'

  publishDir "${ANALYSES_DIR}/${params.genetic_cache_key}/${params.analysis_name}/gwas_results/${model}/plots", mode: 'copy', overwrite: true

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
