/* 
 * Consolidated QC Module
 * Contains all quality control processes:
 * - CHECK_REFERENCES: Verify reference genomes exist (process 0 - runs once)
 * - ADD_HEADER_TO_CHUNKS: Add VCF header to chunks that lack it
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

/* Process 1a - Variant Standardization for VCF (chunked) */
process GENETICQC {
  scratch true
  label 'medium'
  errorStrategy 'ignore'

  input:
    tuple val(fileTag), path(fOrig), path(fChunk)
  output:
    path("${chunkId}.*"), optional: true, emit: snpchunks_merge
    tuple val(fileTag), val(chunkId), optional: true, emit: snpchunks_names
    tuple val(fileTag), val(chunkId), path("${chunkId}.status.txt"), emit: chunk_status

  script:
  def fileName = fChunk.getName()
  def prefix = fileName.replaceAll(/\.(vcf|bcf)(\.gz)?$/, '')
  chunkId = "${prefix}_p1out"

  """
  set +e
  
  echo "=== GENETICQC Debug Info ==="
  echo "fileTag: ${fileTag}"
  echo "fOrig: ${fOrig}"
  echo "fChunk: ${fChunk}"
  echo "fileName: ${fileName}"
  echo "prefix: ${prefix}"
  echo "chunkId: ${chunkId}"
  echo "Assigned cpus: ${task.cpus}"
  echo "Assigned memory: ${task.memory}"
  echo ""
  
  START_TIME=\$(date '+%Y-%m-%d %H:%M:%S')

  # Check if chunk already has header (first chunk with splitText keepHeader:false still has header)
  if [[ ${fChunk} == *.gz ]]; then
    CHUNK_HEADER_LINES=\$(gunzip -c ${fChunk} | grep -c "^#" || echo 0)
  else
    CHUNK_HEADER_LINES=\$(grep -c "^#" ${fChunk} || echo 0)
  fi
  
  echo "Chunk header lines: \${CHUNK_HEADER_LINES}"
  
  if [ "\${CHUNK_HEADER_LINES}" -gt 0 ]; then
    echo "Chunk already has header, using as-is"
    cp ${fChunk} ${prefix}_with_header.vcf.gz
  else
    echo "Chunk missing header, extracting from original file"
    # Extract header from original VCF using bcftools
    bcftools view -h ${fOrig} > header.txt
    HEADER_LINES=\$(wc -l < header.txt)
    echo "Extracted \${HEADER_LINES} header lines from original file"
    
    # Combine header with chunk data
    if [[ ${fChunk} == *.gz ]]; then
      cat header.txt <(gunzip -c ${fChunk}) | bgzip > ${prefix}_with_header.vcf.gz
    else
      cat header.txt ${fChunk} | bgzip > ${prefix}_with_header.vcf.gz
    fi
  fi
  
  echo "Created ${prefix}_with_header.vcf.gz"
  ls -lh ${prefix}_with_header.vcf.gz

  process1.sh \
    ${task.cpus} \
    ${prefix}_with_header.vcf.gz \
    ${params.r2thres} \
    ${params.assembly} \
    ${prefix}
  
  EXIT_CODE=\$?
  END_TIME=\$(date '+%Y-%m-%d %H:%M:%S')
  
  if [ -f "${chunkId}.bed" ] && [ -f "${chunkId}.bim" ] && [ -f "${chunkId}.fam" ]; then
    VARIANT_COUNT=\$(wc -l < ${chunkId}.bim)
    STATUS="SUCCESS"
    echo "✓ Successfully processed chunk with \${VARIANT_COUNT} variants"
  else
    VARIANT_COUNT=0
    STATUS="FAILED"
    echo "⚠ Warning: Chunk produced no variants after filtering" >&2
  fi
  
  echo -e "${fileTag}\t${chunkId}\t${fChunk}\t\${START_TIME}\t\${END_TIME}\t\${EXIT_CODE}\t\${STATUS}\t\${VARIANT_COUNT}" > ${chunkId}.status.txt
  
  exit 0
  """
}

/* Process 1b - Variant Standardization for PLINK (per-chromosome, outputs to cache) */
process GENETICQCPLINK {
  scratch true
  storeDir "${GENOTYPES_DIR}/${params.genetic_cache_key}/chromosomes/${fileTag}"
  label 'two_cpu_large_mem'

  input:
    tuple val(fileTag), path(chr_pfiles)
  output:
    tuple path("${fileTag}.psam"), path("${fileTag}.pgen"), path("${fileTag}.pvar"), path("${fileTag}.log"), emit: plink_qc_cached
    tuple val(fileTag), path("${fileTag}.status.txt"), emit: chunk_status

  script:
  def outputPrefix = "${fileTag}_processed"

  """
  echo "Processing PLINK file: ${chr_pfiles}"
  echo "Input prefix: ${fileTag}"
  echo "Output prefix: ${outputPrefix}"
  echo "Assigned cpus: ${task.cpus}"
  echo "Assigned memory: ${task.memory}"
  
  START_TIME=\$(date '+%Y-%m-%d %H:%M:%S')

  process_plink.sh \
    ${task.cpus} \
    ${fileTag} \
    ${params.assembly} \
    ${outputPrefix} \
    ${params.r2thres}
  
  EXIT_CODE=\$?
  END_TIME=\$(date '+%Y-%m-%d %H:%M:%S')
  
  # Check if output files were created successfully
  if [ \$EXIT_CODE -ne 0 ]; then
    echo "ERROR: process_plink.sh failed with exit code \$EXIT_CODE" >&2
    echo -e "${fileTag}\t${fileTag}\t${chr_pfiles}\t\${START_TIME}\t\${END_TIME}\t\${EXIT_CODE}\tFAILED\t0" > ${fileTag}.status.txt
    exit \$EXIT_CODE
  fi
  
  if [ ! -f "${outputPrefix}_p1out.pgen" ] || [ ! -f "${outputPrefix}_p1out.pvar" ] || [ ! -f "${outputPrefix}_p1out.psam" ]; then
    echo "ERROR: Expected output files not created by process_plink.sh" >&2
    echo -e "${fileTag}\t${fileTag}\t${chr_pfiles}\t\${START_TIME}\t\${END_TIME}\t1\tFAILED\t0" > ${fileTag}.status.txt
    exit 1
  fi
  
  # Rename output to match chromosome name (fileTag)
  mv ${outputPrefix}_p1out.pgen ${fileTag}.pgen
  mv ${outputPrefix}_p1out.pvar ${fileTag}.pvar
  mv ${outputPrefix}_p1out.psam ${fileTag}.psam
  mv ${outputPrefix}_p1out.log ${fileTag}.log 2>/dev/null || touch ${fileTag}.log
  
  VARIANT_COUNT=\$(wc -l < ${fileTag}.pvar | awk '{print \$1-1}')
  echo "✓ Successfully processed PLINK file with \${VARIANT_COUNT} variants"
  
  echo -e "${fileTag}\t${fileTag}\t${chr_pfiles}\t\${START_TIME}\t\${END_TIME}\t\${EXIT_CODE}\tSUCCESS\t\${VARIANT_COUNT}" > ${fileTag}.status.txt
  """
}

process MERGER_CHUNKS {
  scratch true
  label 'large'
  storeDir { "${GENOTYPES_DIR}/${params.genetic_cache_key}/chromosomes/${mergelist.getSimpleName()}" }

  input:
    file mergelist
    file "*"
  output:
    tuple file("${fileTag}.psam"), file("${fileTag}.pgen"), file("${fileTag}.pvar"), file("${fileTag}.log"), emit: snpchunks_qc_merged

  script:
    fileTag = mergelist.getSimpleName()
    if (params.chunk_flag) {
      """
      set +x

      plink --merge-list ${mergelist} \
        --keep-allele-order \
        --threads ${task.cpus} \
        --out ${fileTag}
      
      plink2 --bfile ${fileTag} \
        --make-pgen \
        --sort-vars \
        --threads ${task.cpus} \
        --out ${fileTag}
      """
    } else {
      """
      set +x
      
      plink2 -pfile ${fileTag}.1_p1out \
        --make-pgen \
        --sort-vars \
        --threads ${task.cpus} \
        --out ${fileTag}
      """
    }
}

process MERGER_CHRS {
  scratch true
  cache 'deep'
  publishDir "${ANALYSES_DIR}/${params.genetic_cache_key}/genetic_qc/merged_genotypes", mode: 'copy', overwrite: true, pattern: "*.{pgen,pvar,psam}"
  publishDir "${ANALYSES_DIR}/${params.genetic_cache_key}/genetic_qc/logs/merge_all", mode: 'copy', overwrite: true, pattern: "*.log"
  label 'large'

  input:
    file mergelist
    path "*"
  output:
    path ("allchr_merged.{pgen,pvar,psam,log}")

  script:
    """
    set -x
    cat $mergelist | uniq > tmp_mergefile.txt
    
    # Check if there's only one chromosome (single line in mergelist)
    NUM_CHR=\$(wc -l < tmp_mergefile.txt | tr -d ' ')
    
    if [ "\$NUM_CHR" -eq 1 ]; then
      # Only one chromosome - no merge needed, just convert formats
      CHR_NAME=\$(cat tmp_mergefile.txt)
      plink2 --pfile "\${CHR_NAME}" \
        --threads ${task.cpus} \
        --keep-allele-order \
        --make-pgen \
        --sort-vars \
        --out "allchr_merged"
    else
      # Multiple chromosomes - merge them
      plink2 --memory ${task.memory.toMega()} \
        --threads ${task.cpus} \
        --pmerge-list "tmp_mergefile.txt" \
        --keep-allele-order \
        --make-pgen \
        --sort-vars \
        --out "allchr_merged"
    fi
    """
}

/* LD Prune per chromosome (for skip population splitting mode) */
process LD_PRUNE_CHR {
  scratch true
  label 'small'

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
  cache 'deep'
  publishDir "${ANALYSES_DIR}/${params.genetic_cache_key}/genetic_qc/sample_qc", mode: 'copy', overwrite: true, pattern: "*.{h5,txt}"
  publishDir "${ANALYSES_DIR}/${params.genetic_cache_key}/genetic_qc/sample_qc/plots", mode: 'copy', overwrite: true, pattern: "*.png"
  label 'large'
  
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
      "allchr_merged" \
      "${params.kinship}" \
      "${params.ancestry}_samplelist_p2out" \
      ${task.cpus}
    """
}

process GWASQC {
  publishDir "${ANALYSES_DIR}/${params.genetic_cache_key}/genetic_qc/sample_qc", mode: 'copy', overwrite: true, pattern: "*.h5"
  publishDir "${ANALYSES_DIR}/${params.genetic_cache_key}/genetic_qc/sample_qc/plots", mode: 'copy', overwrite: true, pattern: "*.{html,png}"
  label 'large'
  
  input:
    path "*" 
  output:
    path "${params.ancestry}_samplelist_p2out.h5", emit: gwasqc_h5_file 
    path "*.{html,png}", emit: gwasqc_figures
  
  script:
    """
    set +x
    
    addi_qc_pipeline.py \
      --geno "allchr_merged" \
      --ref "/srv/GWAS-Pipeline/References/ref_panel/1kg_ashkj_ref_panel_gp2_pruned_hg38_newids" \
      --ref_labels "/srv/GWAS-Pipeline/References/ref_panel/ancestry_ref_labels.txt" \
      --pop "${params.ancestry}" \
      --out "${params.ancestry}_samplelist_p2out"    
    """
}
