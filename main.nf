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
 covariates                               : ${params.covariates}
 analysis                                 : ${MODEL}
 project directory                        : ${params.project_dir}
 dataset                                  : ${params.dataset}
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
include { CHECK_REFERENCES; GENETICQC; MERGER_CHUNKS; LD_PRUNE_CHR; MERGER_CHRS; SIMPLE_QC; GWASQC } from './modules/qc.nf'
include { MAKEANALYSISSETS; COMPUTE_PCA; MERGE_PCA; GALLOPCOX_INPUT; RAWFILE_EXPORT; EXPORT_PLINK } from './modules/dataprep.nf'
include { GWASGLM; GWASGALLOP; GWASCPH } from './modules/gwas.nf'
include { SAVEGWAS; MANHATTAN } from './modules/results.nf'

/* 
 * Get the cache and the input check channels
 */
Channel
  .fromPath("${params.project_dir}/${params.dataset}/p1_run_cache/*", checkIfExists: false)
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
    
    // ==================================================================================
    // QUALITY CONTROL (QC) PHASE
    // ==================================================================================
    input_check_ch
        .join(cache, remainder: true)
        .filter{ fileTag, fOrig, fCache -> fCache == null }
        .map{ fileTag, fOrig, fCache -> tuple(fileTag, fOrig) }
        .set{ chrvcf }

    // Efficient chunking: tag chunks by original input filename
    // splitText preserves tuple elements before the file, so we need fileTag first
    chrvcf
    .map{ fileTag, fOrig -> fOrig }
    .splitText(by: params.chunk_size, file: true, compress: true, keepHeader: true)
    .map{ fChunk -> tuple(fChunk.getSimpleName(), fChunk) }
    // fChunk = chr20.1.vcf.gz, 
    .combine(CHECK_REFERENCES.out.references_flag)
    .map{ fileTag, fChunk, references_flag -> tuple(fileTag, fChunk) }
    .set{ input_p1_run_ch }

    // Run genetic QC (depends on CHECK_REFERENCES completing)
    GENETICQC(input_p1_run_ch)
    
    // Collect chunk processing status for tracking (tab-separated table format)
    GENETICQC.out.chunk_status
        .map{ fileTag, chunkId, statusFile -> statusFile.text }
        .collectFile(name: "geneticqc_chunk_status_${params.datetime}.tsv", 
                     storeDir: "${OUTPUT_DIR}/${params.dataset}/LOGS/GENETICQC_STATUS/",
                     seed: "fileTag\tchunkId\tinput\tstart_time\tend_time\texit_code\tstatus\tvariants\n",
                     newLine: false)

    GENETICQC.out.snpchunks_names
        .collectFile(newLine: true) 
                        { fileTag, chunkId -> ["${fileTag}.mergelist.txt", chunkId] }
        .set{ chunknames }

    // Merge chunks
    MERGER_CHUNKS(chunknames, GENETICQC.out.snpchunks_merge.collect())
    
    MERGER_CHUNKS.out
        .collect()
        .flatten()
        .map{ fn -> tuple(fn.getSimpleName(), fn) }
        .concat(cache)
        .set{ chrsqced }

    // Branch based on skip_pop_split mode
    if (params.skip_pop_split) {
        // Skip population splitting mode: LD prune per chromosome before merging
        LD_PRUNE_CHR(chrsqced.groupTuple(by: 0).map{ vSimple, files -> files })
        
        LD_PRUNE_CHR.out
            .flatten()
            .map{ fn -> tuple(fn.getSimpleName(), fn) }
            .set{ chrsqced_pruned }
        
        // For GWAS: use unpruned chromosome-level data
        chrsqced
            .groupTuple(by: 0)
            .set{ gallop_plink_input }

        chrsqced
            .groupTuple(by: 0)
            .map{ chrName, files -> 
                def pvarFile = files.find{ it.name.endsWith('.pvar') }
                tuple(chrName, pvarFile)
            }
            .set{ gallopcph_chunks }

        // For QC/PCA: merge pruned chromosomes
        chrsqced_pruned
            .collectFile() { vSimple, f ->
                ["allchr.mergelist.txt", f.getBaseName() + '\n'] }
            .set{ list_files_merge }
        chrsqced_pruned
            .map{ vSimple, f -> file(f) }
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

        chrsqced
            .groupTuple(by: 0)
            .map{ chrName, files -> 
                def pvarFile = files.find{ it.name.endsWith('.pvar') }
                tuple(chrName, pvarFile)
            }
            .set{ gallopcph_chunks }

        // Merge all chromosomes
        chrsqced
            .collectFile() { vSimple, f ->
                ["allchr.mergelist.txt", f.getBaseName() + '\n'] }
            .set{ list_files_merge }
        chrsqced
            .map{ vSimple, f -> file(f) }
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
        GALLOPCOX_INPUT(gallopcph_chunks)

        // Use combine with 'by' to safely pair each chromosome's PLINK files with its input chunks
        gallop_plink_input
            .map{ chrName, plinkFiles -> tuple(chrName, plinkFiles) }
            .combine(GALLOPCOX_INPUT.out.splitText(file: true), by: 0)
            .map{ chrName, plinkFiles, lineFile ->
                tuple(chrName, plinkFiles[0], plinkFiles[1], plinkFiles[2], plinkFiles[3], lineFile)
            }
            .set{ GALLOPCPHCHUNKS }

        RAWFILE_EXPORT(GALLOPCPHCHUNKS, MERGE_PCA.out)
        CHUNKS = RAWFILE_EXPORT.out.gwas_rawfile
        PLINK_SAMPLE_LIST = Channel.empty()

    } else {
        EXPORT_PLINK(MERGE_PCA.out.flatten(), params.phenofile)
        PLINK_SAMPLE_LIST = EXPORT_PLINK.out
        CHUNKS = gallop_plink_input
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
        GWASGLM(CHUNKS, PLINK_SAMPLE_LIST, phenonames)
        GWASRES = GWASGLM.out
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