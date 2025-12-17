/* 
 * Consolidated QC Module
 * Contains all quality control processes:
 * - CHECK_REFERENCES: Verify reference genomes exist (process 0 - runs once)
 * - GENETICQC: Genotype preprocessing and filtering
 * - MERGER_CHUNKS: Merge chromosome chunks
 * - MERGER_CHRS: Merge all chromosomes
 * - GWASQC: GWAS-level QC (ancestry, kinship, outliers)
 */

/* Process 0 - Check Reference Genomes (runs once before all other processes) */
process CHECK_REFERENCES {
  label 'small'
  cache 'lenient'
  
  output:
    path "references_ready.txt", emit: references_flag
  
  script:
  """
  echo "Checking reference genomes for assembly: ${params.assembly}" > references_ready.txt
  echo "Reference directory: ${RESOURCE_DIR}" >> references_ready.txt
  echo "" >> references_ready.txt
  
  # Verify critical files exist
  if [ ! -f "${RESOURCE_DIR}/Genome/hg38.fa.gz" ]; then
    echo "ERROR: hg38 reference genome not found at: ${RESOURCE_DIR}/Genome/hg38.fa.gz" | tee -a references_ready.txt
    echo "" | tee -a references_ready.txt
    echo "Please download references before running the pipeline:" | tee -a references_ready.txt
    echo "  bash bin/download_references.sh ${params.assembly} ${params.reference_dir}" | tee -a references_ready.txt
    exit 1
  fi
  
  if [ ! -f "${RESOURCE_DIR}/Genome/hg38.fa.gz.fai" ]; then
    echo "ERROR: hg38 reference index not found at: ${RESOURCE_DIR}/Genome/hg38.fa.gz.fai" | tee -a references_ready.txt
    echo "" | tee -a references_ready.txt
    echo "Please download references before running the pipeline:" | tee -a references_ready.txt
    echo "  bash bin/download_references.sh ${params.assembly} ${params.reference_dir}" | tee -a references_ready.txt
    exit 1
  fi
  
  echo "✓ hg38.fa.gz found" >> references_ready.txt
  echo "✓ hg38.fa.gz.fai found" >> references_ready.txt
  
  if [ "${params.assembly}" != "hg38" ]; then
    if [ ! -f "${RESOURCE_DIR}/Genome/${params.assembly}.fa.gz" ]; then
      echo "ERROR: ${params.assembly} reference genome not found at: ${RESOURCE_DIR}/Genome/${params.assembly}.fa.gz" | tee -a references_ready.txt
      echo "" | tee -a references_ready.txt
      echo "Please download references before running the pipeline:" | tee -a references_ready.txt
      echo "  bash bin/download_references.sh ${params.assembly} ${params.reference_dir}" | tee -a references_ready.txt
      exit 1
    fi
    
    if [ ! -f "${RESOURCE_DIR}/Genome/${params.assembly}.fa.gz.fai" ]; then
      echo "ERROR: ${params.assembly} reference index not found at: ${RESOURCE_DIR}/Genome/${params.assembly}.fa.gz.fai" | tee -a references_ready.txt
      echo "" | tee -a references_ready.txt
      echo "Please download references before running the pipeline:" | tee -a references_ready.txt
      echo "  bash bin/download_references.sh ${params.assembly} ${params.reference_dir}" | tee -a references_ready.txt
      exit 1
    fi
    
    if [ ! -f "${RESOURCE_DIR}/liftOver/${params.assembly}ToHg38.over.chain.gz" ]; then
      echo "ERROR: Liftover chain file not found at: ${RESOURCE_DIR}/liftOver/${params.assembly}ToHg38.over.chain.gz" | tee -a references_ready.txt
      echo "" | tee -a references_ready.txt
      echo "Please download references before running the pipeline:" | tee -a references_ready.txt
      echo "  bash bin/download_references.sh ${params.assembly} ${params.reference_dir}" | tee -a references_ready.txt
      exit 1
    fi
    
    echo "✓ ${params.assembly}.fa.gz found" >> references_ready.txt
    echo "✓ ${params.assembly}.fa.gz.fai found" >> references_ready.txt
    echo "✓ ${params.assembly}ToHg38.over.chain.gz found" >> references_ready.txt
  fi
  
  echo "" >> references_ready.txt
  echo "All required reference files verified successfully!" >> references_ready.txt
  date >> references_ready.txt
  """
}

/* Process 1 Run - Variant Standardization */
process GENETICQC {
  scratch true
  label 'medium'
  errorStrategy 'ignore'

  input:
    tuple val(fileTag), path(fChunk)
  output:
    tuple file("${chunkId}.bed"), file("${chunkId}.bim"), file("${chunkId}.fam"), optional: true, emit: snpchunks_merge
    tuple val(fileTag), val(chunkId), optional: true, emit: snpchunks_names
    tuple val(fileTag), val(chunkId), path("${chunkId}.status.txt"), emit: chunk_status

  script:
  // Use chunk left of vcf as prefix  chr22.1.vcf.gz -> chr20.1.vcf
  def chunkBase = fChunk.getName()
  def prefix = chunkBase.replaceFirst(/\.vcf(\.gz)?$/, '')
  chunkId = "${prefix}_p1out"

  """
  set +e  # Don't exit on error
  
  echo "Processing chunk: ${fChunk}"
  echo "Output prefix: ${prefix}"
  echo "Assigned cpus: ${task.cpus}"
  echo "Assigned memory: ${task.memory}"
  
  START_TIME=\$(date '+%Y-%m-%d %H:%M:%S')

  process1.sh \
    ${task.cpus} \
    ${fChunk} \
    ${params.r2thres} \
    ${params.assembly} \
    ${prefix}
  
  EXIT_CODE=\$?
  END_TIME=\$(date '+%Y-%m-%d %H:%M:%S')
  
  # Check if output files were created
  if [ -f "${chunkId}.bed" ] && [ -f "${chunkId}.bim" ] && [ -f "${chunkId}.fam" ]; then
    VARIANT_COUNT=\$(wc -l < ${chunkId}.bim)
    STATUS="SUCCESS"
    echo "✓ Successfully processed chunk with \${VARIANT_COUNT} variants"
  else
    VARIANT_COUNT=0
    STATUS="FAILED"
    echo "⚠ Warning: Chunk produced no variants after filtering (likely too small or low quality)" >&2
  fi
  
  # Write status as tab-separated single line
  echo -e "${fileTag}\t${chunkId}\t${fChunk}\t\${START_TIME}\t\${END_TIME}\t\${EXIT_CODE}\t\${STATUS}\t\${VARIANT_COUNT}" > ${chunkId}.status.txt
  
  exit 0  # Always exit successfully to allow workflow continuation
  """
}

process MERGER_CHUNKS {
  scratch true
  storeDir "${STORE_DIR}/${params.genetic_cache_key}/p1_run_cache"
  publishDir "${OUTPUT_DIR}/${params.dataset}/LOGS/MERGER_CHUNKS_${params.datetime}/", mode: 'copy', overwrite: true, pattern: "*.log"
  label 'large_mem'

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
  storeDir "${STORE_DIR}/${params.genetic_cache_key}/p2_merged_cache"
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
  storeDir "${STORE_DIR}/${params.genetic_cache_key}/p2_ldprune_cache"
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
  storeDir "${STORE_DIR}/${params.genetic_cache_key}/p2_qc_pipeline_cache"
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
  storeDir "${STORE_DIR}/${params.genetic_cache_key}/p2_qc_pipeline_cache"
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
