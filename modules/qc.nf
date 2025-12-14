/* 
 * Consolidated QC Module
 * Contains all quality control processes:
 * - GENETICQC: Genotype preprocessing and filtering
 * - MERGER_CHUNKS: Merge chromosome chunks
 * - MERGER_CHRS: Merge all chromosomes
 * - GWASQC: GWAS-level QC (ancestry, kinship, outliers)
 */

/* Process 1 Run - Variant Standardization */
process GENETICQC {
  scratch true
  label 'medium'

  input:
    tuple val(vSimple), path(fOrig), path(fChunk)
  output:
    tuple file("${output}.bed"), file("${output}.bim"), file("${output}.fam"), emit: snpchunks_merge
    tuple val(vSimple), val("${output}"), emit: snpchunks_names

  script:
  def vPart = ""
  def prefix = ""

  vPart = fChunk.getBaseName()

  def mPart = vPart =~ /(.*)\.([0-9]+)\.(.*)$/
  vPart = mPart[0][2]

  prefix = "${vSimple}.${vPart}"
  output = "${prefix}_p1out"
  ext = fChunk.getExtension()

  """
  echo "Processing - ${fChunk}"
  echo "Assigned cpus: ${task.cpus}"
  echo "Assigned memory: ${task.memory}"
  
  set +x
  if [[ ${vPart} == 1 ]]; then
    cp $fChunk tmp_input.${ext}
  else
    bcftools view -h $fOrig | gzip > tmp_input.${ext}
    cat $fChunk >> tmp_input.${ext}
  fi

  process1.sh \
    ${task.cpus} \
    tmp_input.${ext} \
    ${params.r2thres} \
    ${params.assembly} \
    ${prefix}
  """
}

process MERGER_CHUNKS {
  scratch true
  storeDir "${STORE_DIR}/${params.dataset}/p1_run_cache"
  publishDir "${OUTPUT_DIR}/${params.dataset}/LOGS/MERGER_CHUNKS_${params.datetime}/", mode: 'copy', overwrite: true, pattern: "*.log"
  label 'small'

  input:
    file mergelist
    file "*"
  output:
    tuple file("${vSimple}.psam"), file("${vSimple}.pgen"), file("${vSimple}.pvar"), file("${vSimple}.log"), emit: snpchunks_qc_merged

  script:
    vSimple = mergelist.getSimpleName()
    if (params.chunk_flag) {
      """
      set +x

      plink --merge-list ${mergelist} \
        --keep-allele-order \
        --threads ${task.cpus} \
        --out ${vSimple}
      
      plink2 --bfile ${vSimple} \
        --make-pgen \
        --sort-vars \
        --threads ${task.cpus} \
        --out ${vSimple}
      """
    } else {
      """
      set +x
      
      plink2 -pfile ${vSimple}.1_p1out \
        --make-pgen \
        --sort-vars \
        --threads ${task.cpus} \
        --out ${vSimple}
      """
    }
}

process MERGER_CHRS {
  scratch true
  storeDir "${STORE_DIR}/${params.dataset}/p2_merged_cache"
  publishDir "${OUTPUT_DIR}/${params.dataset}/LOGS/MERGER_CHRS_LOGS_${params.datetime}/logs", mode: 'copy', overwrite: true, pattern: "*.log"
  label 'large_mem'

  input:
    file mergelist
    path "*"
  output:
    path ("allchr_${params.dataset}_p2in.{bed,fam,bim,pgen,pvar,psam,log}")

  script:
    """
    set -x
    cat $mergelist | uniq > tmp_mergefile.txt
    plink2 --memory ${task.memory.toMega()} \
      --threads ${task.cpus} \
      --pmerge-list "tmp_mergefile.txt" \
      --keep-allele-order \
      --make-bed \
      --out "allchr_${params.dataset}_p2in"
    """
}

/* LD Prune per chromosome (for skip population splitting mode) */
process LD_PRUNE_CHR {
  scratch true
  storeDir "${STORE_DIR}/${params.dataset}/p2_ldprune_cache"
  label 'medium'

  input:
    tuple path(psam), path(pgen), path(pvar), path(log)
  output:
    tuple path("${output}.psam"), path("${output}.pgen"), path("${output}.pvar")

  script:
    def base = pgen.getBaseName()
    output = "${base}_pruned"
    """
    set +x
    
    # LD pruning per chromosome
    plink2 --pfile ${base} \
      --maf 0.05 \
      --autosome \
      --indep-pairwise 1000 50 0.05 \
      --threads ${task.cpus} \
      --out ${base}_prune
    
    plink2 --pfile ${base} \
      --extract ${base}_prune.prune.in \
      --make-pgen \
      --threads ${task.cpus} \
      --out ${output}
    """
}

/* Simple QC without ancestry inference (for skip population splitting mode) */
process SIMPLE_QC {
  storeDir "${STORE_DIR}/${params.dataset}/p2_qc_pipeline_cache"
  publishDir "${OUTPUT_DIR}/${params.dataset}/LOGS/SIMPLEQC_${params.datetime}/", mode: 'copy', overwrite: true, pattern: "*.txt"
  publishDir "${OUTPUT_DIR}/${params.dataset}/PLOTS/SIMPLEQC_PLOTS_${params.datetime}/", mode: 'copy', overwrite: true, pattern: "*.png"
  label 'large_mem'
  
  input:
    path "*" 
  output:
    path "${params.ancestry}_samplelist_p2out.h5", emit: simpleqc_h5_file 
    path "*_qc_summary.txt", emit: simpleqc_summary
    path "*_PC*.png", emit: simpleqc_plots
  
  script:
    """
    set +x
    
    simple_qc.sh \
      "allchr_${params.dataset}_p2in" \
      "${params.kinship}" \
      "${params.ancestry}_samplelist_p2out" \
      ${task.cpus}
    """
}

process GWASQC {
  storeDir "${STORE_DIR}/${params.dataset}/p2_qc_pipeline_cache"
  publishDir "${OUTPUT_DIR}/${params.dataset}/PLOTS/GWASQC_PLOTS_${params.datetime}/", mode: 'copy', overwrite: true, pattern: "*.{html,png}"
  label 'large_mem'
  
  input:
    path "*" 
  output:
    path "${params.ancestry}_samplelist_p2out.h5", emit: gwasqc_h5_file 
    path "*.{html,png}", emit: gwasqc_figures
  
  script:
    """
    set +x
    
    addi_qc_pipeline.py \
      --geno "allchr_${params.dataset}_p2in" \
      --ref "/srv/GWAS-Pipeline/References/ref_panel/1kg_ashkj_ref_panel_gp2_pruned_hg38_newids" \
      --ref_labels "/srv/GWAS-Pipeline/References/ref_panel/ancestry_ref_labels.txt" \
      --pop "${params.ancestry}" \
      --out "${params.ancestry}_samplelist_p2out"    
    """
}
