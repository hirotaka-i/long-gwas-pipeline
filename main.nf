#!/usr/bin/env nextflow

/*
 * Enables modules
 */
nextflow.enable.dsl = 2

/* 
 * Import consolidated modules
 */
include { CHECK_REFERENCES; SPLIT_VCF; GENETICQC; GENETICQCPLINK; MERGER_CHUNKS; LD_PRUNE_CHR; MERGER_CHRS; SIMPLE_QC; GWASQC } from './modules/qc.nf'
include { MAKEANALYSISSETS; COMPUTE_PCA; MERGE_PCA; HARMONIZE_CATEGORICAL_COVARS; RAWFILE_EXPORT; EXPORT_PLINK } from './modules/dataprep.nf'
include { GWASGLM; GWASGALLOP; GWASCPH } from './modules/gwas.nf'
include { SAVEGWAS; MANHATTAN; TABLEONE } from './modules/results.nf'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
workflow {
    def model

    if (params.longitudinal_flag) {
        model = "lmm_gallop"
    }
    else if (params.survival_flag) {
        model = "cph"
    }
    else {
        model = "glm"
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
 analysis                                 : ${model}
 project directory                        : ${params.project_dir}
 analysis name                            : ${params.analysis_name}
 genetic cache key                        : ${params.genetic_cache_key}
 """

    def datetime = new java.util.Date()
    params.datetime = new java.text.SimpleDateFormat("YYYY-MM-dd'T'HHMMSS").format(datetime)

        def cache = Channel
      .fromPath("${params.project_dir}/genotypes/${params.genetic_cache_key}/chromosomes/*/*.{pgen,pvar,psam,log}", checkIfExists: false)
      .map{ f -> tuple(f.getSimpleName(), f) }

        def input_check_ch = Channel
       .fromPath(params.input)
       .map{ f -> tuple(f.getSimpleName(), f) }

        def phenonames = Channel
        .of(params.pheno_name)
        .splitCsv(header: false)
        .collect()

    // ==================================================================================
    // PROCESS 0: CHECK REFERENCE GENOMES (runs once)
    // ==================================================================================
    CHECK_REFERENCES()
    
    // Prepare reference files channel
    def refDir = params.reference_dir
    def reference_files = Channel.fromPath([
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
    def chrvcf = input_check_ch
        .join(cache, remainder: true)
        .filter{ fileTag, fOrig, fCache -> fCache == null }
        .map{ fileTag, fOrig, fCache -> tuple(fileTag, fOrig) }

    // Determine input format from params.input pattern
    def isPlink = params.input =~ /\.(bed|pgen)$/
    
    def chrsqced

    if (isPlink) {
        // ============================================================
        // PLINK INPUT PATHWAY: Direct cache, no chunking
        // ============================================================
        
        // Gather all companion files (.pgen, .pvar, .psam or .bed, .bim, .fam)
        def plink_input_ch = chrvcf
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

        // Process PLINK files directly to cache
        GENETICQCPLINK(plink_input_ch, reference_files)
        
        // Collect processing status for tracking
        GENETICQCPLINK.out.chunk_status
            .map{ fileTag, statusFile -> statusFile.text }
            .collectFile(name: "geneticqc_chunk_status_${params.datetime}.tsv", 
                         storeDir: "${params.project_dir}/analyses/${params.genetic_cache_key}/genetic_qc/logs/",
                         seed: "fileTag\tchunkId\tinput\tstart_time\tend_time\texit_code\tstatus\tvariants\n",
                         newLine: false)
        
        // PLINK output goes directly to chrsqced (already in pgen format, no merge needed)
        chrsqced = GENETICQCPLINK.out.plink_qc_cached
            .collect()
            .flatten()
            .map{ fn -> tuple(fn.getSimpleName(), fn) }
            .concat(cache)
            
    } else {
        // ============================================================
        // VCF INPUT PATHWAY: Chunk, process, merge
        // ============================================================
        
        // Split VCF files into chunks using a process (faster on cloud)
        SPLIT_VCF(chrvcf)
        
        // Flatten chunks: [fileTag, fOrig, [chunk1, chunk2, ...]] → multiple [fileTag, fOrig, chunk]
        def vcf_chunks_ch = SPLIT_VCF.out.vcf_chunks
        .transpose()
        .map{ fileTag, fOrig, fChunk -> tuple(fileTag, fOrig, fChunk) }
        .combine(CHECK_REFERENCES.out.references_flag)
        .map{ fileTag, fOrig, fChunk, references_flag -> tuple(fileTag, fOrig, fChunk) }

        // Process VCF chunks (adds headers internally)
        GENETICQC(vcf_chunks_ch, reference_files)
        
        // Collect processing status for tracking
        GENETICQC.out.chunk_status
            .map{ fileTag, chunkId, statusFile -> statusFile.text }
            .collectFile(name: "geneticqc_chunk_status_${params.datetime}.tsv", 
                         storeDir: "${params.project_dir}/analyses/${params.genetic_cache_key}/genetic_qc/logs/",
                         seed: "fileTag\tchunkId\tinput\tstart_time\tend_time\texit_code\tstatus\tvariants\n",
                         newLine: false)

        // Merge VCF chunks per chromosome
        def chunknames = GENETICQC.out.snpchunks_names
            .collectFile(newLine: true) 
                            { fileTag, chunkId -> ["${fileTag}.mergelist.txt", chunkId] }

        MERGER_CHUNKS(chunknames, GENETICQC.out.snpchunks_merge.collect())
        
        // VCF merged output goes to chrsqced
        chrsqced = MERGER_CHUNKS.out
            .collect()
            .flatten()
            .map{ fn -> tuple(fn.getSimpleName(), fn) }
            .concat(cache)
    }

    // Branch based on skip_pop_split mode
    def qc_h5_file
    def gallop_plink_input
    def list_files_merge
    def chrfiles
    def input_compute_pca

    if (params.skip_pop_split) {
        // Skip population splitting mode: LD prune per chromosome before merging
        LD_PRUNE_CHR(chrsqced.groupTuple(by: 0).map{ fileTag, files -> files })
        
        def chrsqced_pruned = LD_PRUNE_CHR.out
            .flatten()
            .map{ fn -> tuple(fn.getSimpleName(), fn) }
        
        // For GWAS: use unpruned chromosome-level data
        gallop_plink_input = chrsqced
            .groupTuple(by: 0)

        // For QC/PCA: merge pruned chromosomes
        list_files_merge = chrsqced_pruned
            .map{ fileTag, f -> fileTag }
            // f contains .log, .pgen, .pvar, .psam for each fileTag. Reduce to one per fileTag.
            .unique()
            .collectFile() { fileTag ->
                ["allchr.mergelist.txt", fileTag + '\n'] }
        chrfiles = chrsqced_pruned
            .map{ fileTag, f -> file(f) }

        MERGER_CHRS(list_files_merge, chrfiles.collect())
        input_compute_pca = MERGER_CHRS.out
            .flatten()
            .filter{ fName -> ["pgen", "pvar", "psam"].contains(fName.getExtension()) }
            .collect()

        // Run simplified QC (no ancestry inference)
        SIMPLE_QC(MERGER_CHRS.out)
        qc_h5_file = SIMPLE_QC.out.simpleqc_h5_file

    } else {
        // Standard mode: merge first, then full QC with ancestry inference
        
        // Prepare channels for downstream analysis
        gallop_plink_input = chrsqced
            .groupTuple(by: 0)

        // Merge all chromosomes
        list_files_merge = chrsqced
            .map{ fileTag, f -> fileTag }
            .unique()
            .collectFile() { fileTag ->
                ["allchr.mergelist.txt", fileTag + '\n'] }
        chrfiles = chrsqced
            .map{ fileTag, f -> file(f) }

        MERGER_CHRS(list_files_merge, chrfiles.collect())
        input_compute_pca = MERGER_CHRS.out
            .flatten()
            .filter{ fName -> ["pgen", "pvar", "psam"].contains(fName.getExtension()) }
            .collect()

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
    HARMONIZE_CATEGORICAL_COVARS(MERGE_PCA.out.flatten())

    // Branch based on analysis type
    def CHUNKS
    def PLINK_SAMPLE_LIST
    if (params.longitudinal_flag | params.survival_flag) {
        // For longitudinal/survival: chunk variants and export to raw format
        // RAWFILE_EXPORT now handles both chunking and export internally
        RAWFILE_EXPORT(gallop_plink_input, HARMONIZE_CATEGORICAL_COVARS.out)
        
        // Flatten to process each raw file individually
        CHUNKS = RAWFILE_EXPORT.out.gwas_rawfile
            .transpose()
        
        PLINK_SAMPLE_LIST = Channel.empty()

    } else {
        // For cross-sectional: use PLINK binary directly (no chunking, no raw export)
        EXPORT_PLINK(HARMONIZE_CATEGORICAL_COVARS.out.flatten(), params.phenofile)
        
        // Collect outputs from EXPORT_PLINK: pheno.tsv, covar_names.txt, n_covar.txt
        // Log files (output[3]) are published automatically via publishDir
        PLINK_SAMPLE_LIST = EXPORT_PLINK.out[0]
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
        
        // For GLM: use gallop_plink_input (already grouped per chromosome)
        // Unpack PLINK files: convert from [fileTag, [files]] to [fileTag, log, pgen, psam, pvar]
        // Files are selected by extension for robustness (not positional indexing)
        // Then combine each chunk with PLINK_SAMPLE_LIST (1 sample list applies to all 22 chromosomes)
        CHUNKS = gallop_plink_input
            .map{ fileTag, plinkFiles ->
                tuple(
                    fileTag,
                    plinkFiles.find { it.extension == 'log' },
                    plinkFiles.find { it.extension == 'pgen' },
                    plinkFiles.find { it.extension == 'psam' },
                    plinkFiles.find { it.extension == 'pvar' }
                )
            }
            .combine(PLINK_SAMPLE_LIST)
    }

    // ==================================================================================
    // GWAS ANALYSIS PHASE
    // ==================================================================================
    def GWASRES
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
        def manifest_ch = GWASGLM.out[1]
            .splitCsv(header: true, sep: '\t')
            .map{ row -> tuple(row.filename, row.key) }
        
        // Flatten result files and map to tuple(filename, file)
        def results_ch = GWASGLM.out[0]
            .flatten()
            .map{ file -> tuple(file.name, file) }
        
        // Join by filename, then remap to (key, file)
        GWASRES = manifest_ch
            .join(results_ch)
            .map{ filename, key, file -> tuple(key, file) }
    }

    def GROUP_RESULTS = GWASRES
        .groupTuple(sort: true)

    // ==================================================================================
    // RESULTS MANAGEMENT PHASE
    // ==================================================================================
    SAVEGWAS(GROUP_RESULTS, model)
    if (params.mh_plot) {
        MANHATTAN(SAVEGWAS.out.res_all.collect(), model)
    }
    
    // ==================================================================================
    // TABLE 1 AND DESCRIPTIVE STATISTICS
    // ==================================================================================
    // Create a temporary YAML config file with all analysis parameters for make_tableone.py
    // This runs after GWAS to ensure filtered analysis sets are available
    def yaml_config_ch = Channel
        .fromPath("${launchDir}/*.yml", checkIfExists: false)
        .filter{ it.name.contains(params.analysis_name) || 
                 it.text.contains("analysis_name: \"${params.analysis_name}\"") ||
                 it.text.contains("analysis_name: ${params.analysis_name}") }
        .mix(
            Channel.fromPath("${launchDir}/*.yml", checkIfExists: false)
                .filter{ it.name.contains(params.analysis_name) || 
                         it.text.contains("analysis_name: \"${params.analysis_name}\"") ||
                         it.text.contains("analysis_name: ${params.analysis_name}") }
                .count()
                .filter{ it == 0 }
                .map{ 
                    // If no matching YAML found, create one from params
                    def f = file("${launchDir}/temp_config_${params.analysis_name}.yml")
                    f.text = """STORE_ROOT: ${params.STORE_ROOT}
PROJECT_NAME: ${params.PROJECT_NAME}
analysis_name: ${params.analysis_name}
input: ${params.input}
covarfile: ${params.covarfile}
phenofile: ${params.phenofile}
pheno_name: ${params.pheno_name}
study_arm_col: ${params.study_arm_col}
covar_numeric: ${params.covar_numeric}
covar_categorical: ${params.covar_categorical}
time_col: ${params.time_col}
longitudinal_flag: ${params.longitudinal_flag}
survival_flag: ${params.survival_flag}
ancestry: ${params.ancestry}
assembly: ${params.assembly}
minor_allele_freq: ${params.minor_allele_freq}
kinship: ${params.kinship}
skip_pop_split: ${params.skip_pop_split}
"""
                    return f
                }
        )
        .first()
    
    TABLEONE(yaml_config_ch, MAKEANALYSISSETS.out.analytical_set)
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
