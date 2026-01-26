#!/usr/bin/env nextflow

/*
 * Enables modules
 */
nextflow.enable.dsl = 2

/*
 * Main workflow log
 */
if (params.longitudinal_flag) {
    MODEL = "lmm_gallop"
} 
else if (params.survival_flag) {
    MODEL = "cph"
}
else {
    MODEL = "glm"
}

log.info """\
 LONG-GWAS - GWAS P I P E L I N E
 ======================================
 Chunk size for genetic processing        : ${params.chunk_size}
 Kinship matrix threshold                 : ${params.kinship}
 R2 threshold                             : ${params.r2thres}
 MAF threshold                            : ${params.minor_allele_freq}
 data ancestry                            : ${params.ancestry}
 genetic data assemble                    : ${params.assembly}
 phenotype name                           : ${params.pheno_name}
 numeric covariates                       : ${params.covar_numeric}
 categorical covariates                   : ${params.covar_categorical}
 interaction covariate                    : ${params.covar_interact}
 analysis                                 : ${MODEL}
 project directory                        : ${params.project_dir}
 analysis name                            : ${params.analysis_name}
 genetic cache key                        : ${params.genetic_cache_key}
 """

/*
 * Datetime
 */
datetime = new java.util.Date()
params.datetime = new java.text.SimpleDateFormat("YYYY-MM-dd'T'HHMMSS").format(datetime)

/* 
 * Import consolidated modules
 */
include { CHECK_REFERENCES; SPLIT_VCF; GENETICQC; GENETICQCPLINK; MERGER_CHUNKS; LD_PRUNE_CHR; MERGER_CHRS; SIMPLE_QC; GWASQC } from './modules/qc.nf'
include { MAKEANALYSISSETS; COMPUTE_PCA; MERGE_PCA; RAWFILE_EXPORT; EXPORT_PLINK } from './modules/dataprep.nf'
include { GWASGLM; GWASGALLOP; GWASCPH } from './modules/gwas.nf'
include { SAVEGWAS; MANHATTAN } from './modules/results.nf'

/* 
 * Get the cache and the input check channels
 */
Channel
  .fromPath("${params.project_dir}/genotypes/${params.genetic_cache_key}/chromosomes/*/*.{pgen,pvar,psam,log}", checkIfExists: false)
  .map{ f -> tuple(f.getSimpleName(), f) }
  .set{ cache }

Channel
   .fromPath(params.input)
   .map{ f -> tuple(f.getSimpleName(), f) }
   .set{ input_check_ch }

/* 
 * Get the phenotypes arg on a channel
 */
Channel
    .of(params.pheno_name)
    .splitCsv(header: false)
    .collect()
    .set{ phenonames }

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
workflow {
    // ==================================================================================
    // PROCESS 0: CHECK REFERENCE GENOMES (runs once)
    // ==================================================================================
    CHECK_REFERENCES()
    
    // Prepare reference files channel
    def refDir = params.reference_dir
    reference_files = Channel.fromPath([
        "${refDir}/Genome/hg38.fa.gz",
        "${refDir}/Genome/hg38.fa.gz.fai",
        "${refDir}/Genome/hg38.fa.gz.gzi"
    ] + (params.assembly != 'hg38' ? [
        "${refDir}/Genome/${params.assembly}.fa.gz",
        "${refDir}/Genome/${params.assembly}.fa.gz.fai",
        "${refDir}/Genome/${params.assembly}.fa.gz.gzi",
        "${refDir}/liftOver/${params.assembly}ToHg38.over.chain.gz"
    ] : []), checkIfExists: true)
    .collect()
    .view{ "Reference files: ${it}" }
    
    // ==================================================================================
    // QUALITY CONTROL (QC) PHASE
    // ==================================================================================
    input_check_ch
        .join(cache, remainder: true)
        .filter{ fileTag, fOrig, fCache -> fCache == null }
        .map{ fileTag, fOrig, fCache -> tuple(fileTag, fOrig) }
        .set{ chrvcf }

    // Determine input format from params.input pattern
    def isPlink = params.input =~ /\.(bed|pgen)$/
    
    if (isPlink) {
        // ============================================================
        // PLINK INPUT PATHWAY: Direct cache, no chunking
        // ============================================================
        
        // Gather all companion files (.pgen, .pvar, .psam or .bed, .bim, .fam)
        chrvcf
        .map{ fileTag, fOrig ->
            // Use toUri() to preserve full path (works for both GCS and local files)
            // For GCS: gs://bucket/path/file.pgen
            // For local: file:///path/to/file.pgen
            def fullPath = fOrig.toUri().toString()
            def basePath = fullPath.replaceFirst(/\.(bed|pgen)$/, '')
            def ext = fOrig.name =~ /\.bed$/ ? ['bed', 'bim', 'fam'] : ['pgen', 'pvar', 'psam']
            def files = ext.collect{ file(basePath + '.' + it) }
            tuple(fileTag, files)
        }
        .combine(CHECK_REFERENCES.out.references_flag)
        .map{ fileTag, chr_pfiles, references_flag -> tuple(fileTag, chr_pfiles) }
        .set{ plink_input_ch }

        // Process PLINK files directly to cache
        GENETICQCPLINK(plink_input_ch, reference_files)
        
        // Collect processing status for tracking
        GENETICQCPLINK.out.chunk_status
            .map{ fileTag, statusFile -> statusFile.text }
            .collectFile(name: "geneticqc_chunk_status_${params.datetime}.tsv", 
                         storeDir: "${ANALYSES_DIR}/${params.genetic_cache_key}/genetic_qc/logs/",
                         seed: "fileTag\tchunkId\tinput\tstart_time\tend_time\texit_code\tstatus\tvariants\n",
                         newLine: false)
        
        // PLINK output goes directly to chrsqced (already in pgen format, no merge needed)
        GENETICQCPLINK.out.plink_qc_cached
            .collect()
            .flatten()
            .map{ fn -> tuple(fn.getSimpleName(), fn) }
            .concat(cache)
            .set{ chrsqced }
            
    } else {
        // ============================================================
        // VCF INPUT PATHWAY: Chunk, process, merge
        // ============================================================
        
        // Split VCF files into chunks using a process (faster on cloud)
        SPLIT_VCF(chrvcf)
        
        // Flatten chunks: [fileTag, fOrig, [chunk1, chunk2, ...]] → multiple [fileTag, fOrig, chunk]
        SPLIT_VCF.out.vcf_chunks
        .transpose()
        .map{ fileTag, fOrig, fChunk -> tuple(fileTag, fOrig, fChunk) }
        .combine(CHECK_REFERENCES.out.references_flag)
        .map{ fileTag, fOrig, fChunk, references_flag -> tuple(fileTag, fOrig, fChunk) }
        .set{ vcf_chunks_ch }

        // Process VCF chunks (adds headers internally)
        GENETICQC(vcf_chunks_ch, reference_files)
        
        // Collect processing status for tracking
        GENETICQC.out.chunk_status
            .map{ fileTag, chunkId, statusFile -> statusFile.text }
            .collectFile(name: "geneticqc_chunk_status_${params.datetime}.tsv", 
                         storeDir: "${ANALYSES_DIR}/${params.genetic_cache_key}/genetic_qc/logs/",
                         seed: "fileTag\tchunkId\tinput\tstart_time\tend_time\texit_code\tstatus\tvariants\n",
                         newLine: false)

        // Merge VCF chunks per chromosome
        GENETICQC.out.snpchunks_names
            .collectFile(newLine: true) 
                            { fileTag, chunkId -> ["${fileTag}.mergelist.txt", chunkId] }
            .set{ chunknames }

        MERGER_CHUNKS(chunknames, GENETICQC.out.snpchunks_merge.collect())
        
        // VCF merged output goes to chrsqced
        MERGER_CHUNKS.out
            .collect()
            .flatten()
            .map{ fn -> tuple(fn.getSimpleName(), fn) }
            .concat(cache)
            .set{ chrsqced }
    }

    // Branch based on skip_pop_split mode
    if (params.skip_pop_split) {
        // Skip population splitting mode: LD prune per chromosome before merging
        LD_PRUNE_CHR(chrsqced.groupTuple(by: 0).map{ fileTag, files -> files })
        
        LD_PRUNE_CHR.out
            .flatten()
            .map{ fn -> tuple(fn.getSimpleName(), fn) }
            .set{ chrsqced_pruned }
        
        // For GWAS: use unpruned chromosome-level data
        chrsqced
            .groupTuple(by: 0)
            .set{ gallop_plink_input }

        // For QC/PCA: merge pruned chromosomes
        chrsqced_pruned
            .map{ fileTag, f -> fileTag }
            // f contains .log, .pgen, .pvar, .psam for each fileTag. Reduce to one per fileTag.
            .unique()
            .collectFile() { fileTag ->
                ["allchr.mergelist.txt", fileTag + '\n'] }
            .set{ list_files_merge }
        chrsqced_pruned
            .map{ fileTag, f -> file(f) }
            .set{ chrfiles }

        MERGER_CHRS(list_files_merge, chrfiles.collect())
        MERGER_CHRS.out
            .flatten()
            .filter{ fName -> ["pgen", "pvar", "psam"].contains(fName.getExtension()) }
            .collect()
            .set{ input_compute_pca }

        // Run simplified QC (no ancestry inference)
        SIMPLE_QC(MERGER_CHRS.out)
        qc_h5_file = SIMPLE_QC.out.simpleqc_h5_file

    } else {
        // Standard mode: merge first, then full QC with ancestry inference
        
        // Prepare channels for downstream analysis
        chrsqced
            .groupTuple(by: 0)
            .set{ gallop_plink_input }

        // Merge all chromosomes
        chrsqced
            .map{ fileTag, f -> fileTag }
            .unique()
            .collectFile() { fileTag ->
                ["allchr.mergelist.txt", fileTag + '\n'] }
            .set{ list_files_merge }
        chrsqced
            .map{ fileTag, f -> file(f) }
            .set{ chrfiles }

        MERGER_CHRS(list_files_merge, chrfiles.collect())
        MERGER_CHRS.out
            .flatten()
            .filter{ fName -> ["pgen", "pvar", "psam"].contains(fName.getExtension()) }
            .collect()
            .set{ input_compute_pca }

        // Run GWAS QC
        GWASQC(MERGER_CHRS.out)
        qc_h5_file = GWASQC.out.gwasqc_h5_file
    }

    // ==================================================================================
    // DATA PREPARATION PHASE
    // ==================================================================================
    MAKEANALYSISSETS(qc_h5_file, params.covarfile)
    COMPUTE_PCA(MAKEANALYSISSETS.out.study_arm_files.flatten(), input_compute_pca)
    MERGE_PCA(COMPUTE_PCA.out.eigenvec)

    // Branch based on analysis type
    if (params.longitudinal_flag | params.survival_flag) {
        // For longitudinal/survival: chunk variants and export to raw format
        // RAWFILE_EXPORT now handles both chunking and export internally
        RAWFILE_EXPORT(gallop_plink_input, MERGE_PCA.out)
        
        // Flatten to process each raw file individually
        RAWFILE_EXPORT.out.gwas_rawfile
            .transpose()
            .set{ CHUNKS }
        
        PLINK_SAMPLE_LIST = Channel.empty()

    } else {
        // For cross-sectional: use PLINK binary directly (no chunking, no raw export)
        EXPORT_PLINK(MERGE_PCA.out.flatten(), params.phenofile)
        
        // Collect outputs from EXPORT_PLINK: pheno.tsv, covar_names.txt, n_covar.txt
        // Log files (output[3]) are published automatically via publishDir
        EXPORT_PLINK.out[0]
            .mix(EXPORT_PLINK.out[1], EXPORT_PLINK.out[2])
            .flatten()
            .filter{ it != null }
            .map{ file ->
                // Extract study arm from filename
                def matcher = file.name =~ /(.+)_filtered\.pca\.pheno\.tsv/
                if (matcher.find()) {
                    return [matcher[0][1], file, 'pheno']
                }
                matcher = file.name =~ /(.+)_covar_names\.txt/
                if (matcher.find()) {
                    return [matcher[0][1], file, 'covar_names']
                }
                matcher = file.name =~ /(.+)_n_covar\.txt/
                if (matcher.find()) {
                    return [matcher[0][1], file, 'n_covar']
                }
                return null
            }
            .filter{ it != null }
            .groupTuple(by: 0)
            .map{ study_arm, files, types ->
                // Return all three files grouped by study arm
                def pheno_file = files[types.indexOf('pheno')]
                def covar_names = files[types.indexOf('covar_names')]
                def n_covar = files[types.indexOf('n_covar')]
                return tuple(study_arm, pheno_file, covar_names, n_covar)
            }
            .set{ PLINK_SAMPLE_LIST }
        
        // For GLM: use gallop_plink_input (already grouped per chromosome)
        // Unpack PLINK files: convert from [fileTag, [files]] to [fileTag, log, pgen, pvar, psam]
        // Then combine each chunk with PLINK_SAMPLE_LIST (1 sample list applies to all 22 chromosomes)
        gallop_plink_input
            .map{ fileTag, plinkFiles -> 
                tuple(fileTag, plinkFiles[0], plinkFiles[1], plinkFiles[2], plinkFiles[3])
            }
            .combine(PLINK_SAMPLE_LIST)
            .set{ CHUNKS }
    }

    // ==================================================================================
    // GWAS ANALYSIS PHASE
    // ==================================================================================
    if (params.longitudinal_flag) {
        GWASGALLOP(CHUNKS, params.phenofile, phenonames)
        GWASRES = GWASGALLOP.out
    }
    else if (params.survival_flag) {
        GWASCPH(CHUNKS, params.phenofile, phenonames)
        GWASRES = GWASCPH.out
    } else {
        GWASGLM(CHUNKS, phenonames)
        
        // Use manifest to create proper tuples
        // GWASGLM.out[0] = result files, GWASGLM.out[1] = manifest files
        
        // Parse manifest: tuple(filename, key)
        GWASGLM.out[1]
            .splitCsv(header: true, sep: '\t')
            .map{ row -> tuple(row.filename, row.key) }
            .set{ manifest_ch }
        
        // Flatten result files and map to tuple(filename, file)
        GWASGLM.out[0]
            .flatten()
            .map{ file -> tuple(file.name, file) }
            .set{ results_ch }
        
        // Join by filename, then remap to (key, file)
        manifest_ch
            .join(results_ch)
            .map{ filename, key, file -> tuple(key, file) }
            .set{ GWASRES }
    }

    GWASRES
        .groupTuple(sort: true)
        .set{ GROUP_RESULTS }

    // ==================================================================================
    // RESULTS MANAGEMENT PHASE
    // ==================================================================================
    SAVEGWAS(GROUP_RESULTS, MODEL)
    if (params.mh_plot) {
        MANHATTAN(SAVEGWAS.out.res_all.collect(), MODEL)
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/