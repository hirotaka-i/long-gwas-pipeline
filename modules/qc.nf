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
  publishDir "${GENOTYPES_DIR}/${params.genetic_cache_key}", mode: 'copy', overwrite: true, pattern: "references_ready.txt"
  
  output:
    path "references_ready.txt", emit: references_flag
  
  script:
  // Check if RESOURCE_DIR is a GCS path
  def isGCS = RESOURCE_DIR.startsWith('gs://')
  def checkCmd = isGCS ? 'gsutil -q stat' : 'test -f'
  def successCheck = isGCS ? '&& echo "exists"' : ''
  
  """
  echo "Checking reference genomes for assembly: ${params.assembly}" > references_ready.txt
  echo "Reference directory: ${RESOURCE_DIR}" >> references_ready.txt
  echo "" >> references_ready.txt
  
  # Verify critical files exist
  if ! ${checkCmd} "${RESOURCE_DIR}/Genome/hg38.fa.gz" ${successCheck} 2>/dev/null; then
    echo "ERROR: hg38 reference genome not found at: ${RESOURCE_DIR}/Genome/hg38.fa.gz" | tee -a references_ready.txt
    echo "" | tee -a references_ready.txt
    echo "Please download references before running the pipeline:" | tee -a references_ready.txt
    echo "  bash bin/download_references.sh ${params.assembly} ${params.reference_dir}" | tee -a references_ready.txt
    exit 1
  fi
  
  if ! ${checkCmd} "${RESOURCE_DIR}/Genome/hg38.fa.gz.fai" ${successCheck} 2>/dev/null; then
    echo "ERROR: hg38 reference index not found at: ${RESOURCE_DIR}/Genome/hg38.fa.gz.fai" | tee -a references_ready.txt
    echo "" | tee -a references_ready.txt
    echo "Please download references before running the pipeline:" | tee -a references_ready.txt
    echo "  bash bin/download_references.sh ${params.assembly} ${params.reference_dir}" | tee -a references_ready.txt
    exit 1
  fi
  
  echo "✓ hg38.fa.gz found" >> references_ready.txt
  echo "✓ hg38.fa.gz.fai found" >> references_ready.txt
  
  if [ "${params.assembly}" != "hg38" ]; then
    if ! ${checkCmd} "${RESOURCE_DIR}/Genome/${params.assembly}.fa.gz" ${successCheck} 2>/dev/null; then
      echo "ERROR: ${params.assembly} reference genome not found at: ${RESOURCE_DIR}/Genome/${params.assembly}.fa.gz" | tee -a references_ready.txt
      echo "" | tee -a references_ready.txt
      echo "Please download references before running the pipeline:" | tee -a references_ready.txt
      echo "  bash bin/download_references.sh ${params.assembly} ${params.reference_dir}" | tee -a references_ready.txt
      exit 1
    fi
    
    if ! ${checkCmd} "${RESOURCE_DIR}/Genome/${params.assembly}.fa.gz.fai" ${successCheck} 2>/dev/null; then
      echo "ERROR: ${params.assembly} reference index not found at: ${RESOURCE_DIR}/Genome/${params.assembly}.fa.gz.fai" | tee -a references_ready.txt
      echo "" | tee -a references_ready.txt
      echo "Please download references before running the pipeline:" | tee -a references_ready.txt
      echo "  bash bin/download_references.sh ${params.assembly} ${params.reference_dir}" | tee -a references_ready.txt
      exit 1
    fi
    
    if ! ${checkCmd} "${RESOURCE_DIR}/liftOver/${params.assembly}ToHg38.over.chain.gz" ${successCheck} 2>/dev/null; then
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

/* Process 0b - Split VCF into chunks (runs on cloud for better performance) */
process SPLIT_VCF {
  label 'small'
  scratch true
  
  input: 
    tuple val(fileTag), path(vcf)
  
  output: 
    tuple val(fileTag), path(vcf), path("${fileTag}.chunk_*.vcf.gz"), emit: vcf_chunks
  
  script:
  def split_chunk_size = params.chunk_size * 1
  """
  echo "=== SPLIT_VCF ==="
  echo "Original VCF: ${vcf}"
  echo ""
  
  echo "Extracting header..."
  bcftools view -h ${vcf} > header.vcf
  
  echo "Splitting into chunks..."
  bcftools view -H ${vcf} \
    | split -l ${split_chunk_size} -d -a 6 \
        --filter="bash -c 'cat header.vcf - | bgzip -@ ${task.cpus} > ${fileTag}.chunk_\\\$FILE.vcf.gz'" \
        -
  
  # Clean up
  rm -f header.vcf
  
  echo ""
  echo "Created \$(ls -1 ${fileTag}.chunk_*.vcf.gz | wc -l) chunks"
  """
}

/* Process 1a - Variant Standardization for VCF (chunked) */
process GENETICQC {
  scratch true
  label 'medium'
  errorStrategy { task.exitStatus in [137, 143] ? 'retry' : 'ignore' }
  maxRetries 2

  input:
    tuple val(fileTag), path(fOrig), path(fChunk)
    path(ref_files)
  output:
    path("${chunkId}.*"), optional: true, emit: snpchunks_merge
    tuple val(fileTag), val(chunkId), optional: true, emit: snpchunks_names
    tuple val(fileTag), val(chunkId), path("${chunkId}.status.txt"), emit: chunk_status

  script:
  def fileName = fChunk.getName()
  def prefix = fileName.replaceAll(/\.(vcf|bcf)(\.gz)?$/, '')
  chunkId = "${prefix}_p1out"

  """
  # Create local References directory structure
  mkdir -p References/Genome References/liftOver
  
  # Symlink reference files to expected locations
  for ref_file in ${ref_files}; do
    filename=\$(basename "\$ref_file")
    if [[ "\$filename" == *.chain.gz ]]; then
      ln -sf "\$(readlink -f "\$ref_file")" "References/liftOver/\$filename"
    else
      ln -sf "\$(readlink -f "\$ref_file")" "References/Genome/\$filename"
    fi
  done
  
  # Set RESOURCE_DIR to local References directory
  export RESOURCE_DIR="\$PWD/References"
  
  echo "=== GENETICQC Debug Info ==="
  echo "fileTag: ${fileTag}"
  echo "fOrig: ${fOrig}"
  echo "fChunk: ${fChunk}"
  echo "fileName: ${fileName}"
  echo "prefix: ${prefix}"
  echo "chunkId: ${chunkId}"
  echo "Assigned cpus: ${task.cpus}"
  echo "Assigned memory: ${task.memory}"
  echo "RESOURCE_DIR: \$RESOURCE_DIR"
  echo ""
  
  START_TIME=\$(date '+%Y-%m-%d %H:%M:%S')

  # Check if chunk already has header (first chunk with splitText keepHeader:false still has header)
  if [[ ${fChunk} == *.gz ]]; then
    CHUNK_HEADER_LINES=\$(gunzip -c ${fChunk} | grep -c "^#" 2>/dev/null || echo 0 | tr -d '\n')
  else
    CHUNK_HEADER_LINES=\$(grep -c "^#" ${fChunk} 2>/dev/null || echo 0 | tr -d '\n')
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
  
  # Check for OOM error first (exit codes 137=SIGKILL, 143=SIGTERM)
  if [ -f "${prefix}_error_type.txt" ] && grep -q "OOM_ERROR" "${prefix}_error_type.txt"; then
    VARIANT_COUNT=0
    STATUS="OOM_ERROR"
    echo "ERROR: Process was killed due to out of memory (OOM)" >&2
    echo -e "${fileTag}\t${chunkId}\t${fChunk}\t\${START_TIME}\t\${END_TIME}\t\${EXIT_CODE}\tOOM_ERROR\t\${VARIANT_COUNT}" > ${chunkId}.status.txt
    exit \${EXIT_CODE}
  elif [ \$EXIT_CODE -eq 137 ] || [ \$EXIT_CODE -eq 143 ]; then
    # Caught by exit code but no error file created
    VARIANT_COUNT=0
    STATUS="OOM_ERROR"
    echo "ERROR: Process was killed (likely OOM). Exit code: \${EXIT_CODE}" >&2
    echo -e "${fileTag}\t${chunkId}\t${fChunk}\t\${START_TIME}\t\${END_TIME}\t\${EXIT_CODE}\tOOM_ERROR\t\${VARIANT_COUNT}" > ${chunkId}.status.txt
    exit \${EXIT_CODE}
  elif [ -f "${chunkId}.pgen" ] && [ -f "${chunkId}.pvar" ] && [ -f "${chunkId}.psam" ]; then
    VARIANT_COUNT=\$(grep -vc "^#" ${chunkId}.pvar || echo 0)
    STATUS="SUCCESS"
    echo "✓ Successfully processed chunk with \${VARIANT_COUNT} variants"
    echo -e "${fileTag}\t${chunkId}\t${fChunk}\t\${START_TIME}\t\${END_TIME}\t\${EXIT_CODE}\t\${STATUS}\t\${VARIANT_COUNT}" > ${chunkId}.status.txt
  else
    # No output files but process exited normally - legitimate filtering result
    VARIANT_COUNT=0
    STATUS="EMPTY_OUTPUT"
    echo "⚠ Warning: Chunk produced no variants after filtering (this is OK)" >&2
    echo -e "${fileTag}\t${chunkId}\t${fChunk}\t\${START_TIME}\t\${END_TIME}\t\${EXIT_CODE}\t\${STATUS}\t\${VARIANT_COUNT}" > ${chunkId}.status.txt
    # Don't create output files - this will prevent this chunk from being included in merge
    rm -f ${chunkId}.pgen ${chunkId}.pvar ${chunkId}.psam ${chunkId}.log 2>/dev/null || true
  fi
  
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
    path(ref_files)
  output:
    tuple path("${fileTag}.psam"), path("${fileTag}.pgen"), path("${fileTag}.pvar"), path("${fileTag}.log"), emit: plink_qc_cached
    tuple val(fileTag), path("${fileTag}.status.txt"), emit: chunk_status

  script:
  def outputPrefix = "${fileTag}_processed"

  """
  # Create local References directory structure
  mkdir -p References/Genome References/liftOver
  
  # Symlink reference files to expected locations
  for ref_file in ${ref_files}; do
    filename=\$(basename "\$ref_file")
    if [[ "\$filename" == *.chain.gz ]]; then
      ln -sf "\$(readlink -f "\$ref_file")" "References/liftOver/\$filename"
    else
      ln -sf "\$(readlink -f "\$ref_file")" "References/Genome/\$filename"
    fi
  done
  
  # Set RESOURCE_DIR to local References directory
  export RESOURCE_DIR="\$PWD/References"
  
  echo "Processing PLINK file: ${chr_pfiles}"
  echo "Input prefix: ${fileTag}"
  echo "Output prefix: ${outputPrefix}"
  echo "Assigned cpus: ${task.cpus}"
  echo "Assigned memory: ${task.memory}"
  echo "RESOURCE_DIR: \$RESOURCE_DIR"
  
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
  label 'large'
  publishDir "${GENOTYPES_DIR}/${params.genetic_cache_key}/chromosomes/${mergelist.getSimpleName()}", mode: 'copy', overwrite: true

  input:
    path mergelist
    path "*"
  output:
    tuple file("${fileTag}.psam"), file("${fileTag}.pgen"), file("${fileTag}.pvar"), file("${fileTag}.log"), emit: snpchunks_qc_merged

  script:
    fileTag = mergelist.getSimpleName()
    if (params.chunk_flag) {
      """
      set +x
      
      echo "=== MERGER_CHUNKS Debug Info ==="
      echo "Working directory: \$PWD"
      echo "Mergelist file: ${mergelist}"
      echo "Original mergelist contents:"
      cat ${mergelist}
      echo ""
      
      # Filter mergelist to only include chunks with all three files present
      > filtered_mergelist.txt
      while IFS= read -r fname; do
        if [ -f "\${fname}.psam" ] && [ -f "\${fname}.pgen" ] && [ -f "\${fname}.pvar" ]; then
          echo "\$fname" >> filtered_mergelist.txt
        else
          echo "  ⚠ Skipping \$fname (missing files)" >&2
        fi
      done < ${mergelist}
      
      echo ""
      echo "Filtered mergelist (only valid chunks):"
      cat filtered_mergelist.txt
      echo ""
      
      # Check if we have any valid chunks
      CHUNK_COUNT=\$(wc -l < filtered_mergelist.txt | tr -d ' ')
      if [ "\$CHUNK_COUNT" -eq 0 ]; then
        echo "ERROR: No valid chunks found to merge!" >&2
        exit 1
      fi
      
      echo "Merging \$CHUNK_COUNT chunks"
      echo ""
      
      plink2 --pmerge-list filtered_mergelist.txt \
        --make-pgen \
        --sort-vars \
        --threads ${task.cpus} \
        --out ${fileTag}
      """
    } else {
      """
      set +x
      
      echo "=== MERGER_CHUNKS Debug Info (no chunking) ==="
      echo "Working directory: \$PWD"
      echo "Looking for: ${fileTag}.1_p1out"
      echo "Files in current directory:"
      ls -lh
      echo ""
      
      plink2 --pfile ${fileTag}.1_p1out \
        --make-pgen \
        --sort-vars \
        --threads ${task.cpus} \
        --out ${fileTag}
      """
    }
}

process MERGER_CHRS {
  cache 'deep'
  publishDir "${ANALYSES_DIR}/${params.genetic_cache_key}/genetic_qc/merged_genotypes", mode: 'copy', overwrite: true, pattern: "*.{pgen,pvar,psam}"
  publishDir "${ANALYSES_DIR}/${params.genetic_cache_key}/genetic_qc/logs/merge_all", mode: 'copy', overwrite: true, pattern: "*.log"
  label 'large'

  input:
    path mergelist
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
        --make-pgen \
        --sort-vars \
        --out "allchr_merged"
    else
      # Multiple chromosomes - merge them
      plink2 --memory ${task.memory.toMega()} \
        --threads ${task.cpus} \
        --pmerge-list "tmp_mergefile.txt" \
        --make-pgen \
        --sort-vars \
        --out "allchr_merged"
    fi
    """
}

/* LD Prune per chromosome (for skip population splitting mode) */
process LD_PRUNE_CHR {
  cache 'deep'
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
  label 'medium'
  
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
