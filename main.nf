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
 """

/*
 * Datetime
 */
datetime = new java.util.Date()
params.datetime = new java.text.SimpleDateFormat("YYYY-MM-dd'T'HHMMSS").format(datetime)

/* 
 * Import consolidated modules
 */
include { GENETICQC; MERGER_SPLITS; MERGER_CHRS; GWASQC } from './modules/qc.nf'
include { GETPHENOS; REMOVEOUTLIERS; COMPUTE_PCA; MERGE_PCA; GALLOPCOX_INPUT; RAWFILE_EXPORT; EXPORT_PLINK } from './modules/dataprep.nf'
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
    // QUALITY CONTROL (QC) PHASE
    // ==================================================================================
    input_check_ch
        .join(cache, remainder: true)
        .filter{ fSimple, fOrig, fCache -> fCache == null }
        .map{ fSimple, fOrig, fCache -> tuple(fSimple, fOrig) }
        .set{ chrvcf }

    chrvcf
        .count()
        .map{ val -> (1..val) }
        .flatten()
        .set{ input_idx_list }

    input_idx_list
        .merge(chrvcf)
        .branch {
            split_tasks_1: it[0] <= 5 
                            return it
            split_tasks_2: it[0] < 10 && it[0] > 5 
                            return it
            split_tasks_3: it[0] < 14 && it[0] >= 10 
                            return it
            split_tasks_4: it[0] < 18 && it[0] >= 14 
                            return it
            split_tasks_5: true
        }.set{ input_p1 }

    input_p1.split_tasks_1
        .map{ fIdx, fSimple, fOrig -> fOrig }
        .splitText(by: params.chunk_size, file: true, compress: true)
        .map{ fn -> tuple(fn.getSimpleName(), fn) }
        .set{ input_split_ch_1 }

    input_p1.split_tasks_2
          .map{ fIdx, fSimple, fOrig -> fOrig }
          .splitText(by: params.chunk_size, file: true, compress: true)
          .map{ fn -> tuple(fn.getSimpleName(), fn) }
          .set{ input_split_ch_2 }

    input_p1.split_tasks_3
          .map{ fIdx, fSimple, fOrig -> fOrig }
          .splitText(by: params.chunk_size, file: true, compress: true)
          .map{ fn -> tuple(fn.getSimpleName(), fn) }
          .set{ input_split_ch_3 }

    input_p1.split_tasks_4
          .map{ fIdx, fSimple, fOrig -> fOrig }
          .splitText(by: params.chunk_size, file: true, compress: true)
          .map{ fn -> tuple(fn.getSimpleName(), fn) }
          .set{ input_split_ch_4 }

    input_p1.split_tasks_5
          .map{ fIdx, fSimple, fOrig -> fOrig }
          .splitText(by: params.chunk_size, file: true, compress: true)
          .map{ fn -> tuple(fn.getSimpleName(), fn) }
          .set{ input_split_ch_5 }

    input_split_ch_1
        .mix(input_split_ch_2, 
             input_split_ch_3,
             input_split_ch_4,
             input_split_ch_5)
        .set{ input_chunks_ch }
    
    chrvcf
        .cross(input_chunks_ch)
        .flatten()
        .collate(4, false)
        .map{ fSimple1, fOrig, fSimple2, fSplit -> 
            tuple(fSimple1, file(fOrig), fSplit) }
        .set{ input_p1_run_ch }

    // Run genetic QC
    GENETICQC(input_p1_run_ch)

    GENETICQC.out.snpchunks_names
        .collectFile(newLine: true) 
                        { vSimple, prefix -> ["${vSimple}.mergelist.txt", prefix] }
        .set{ chunknames }

    // Merge splits
    MERGER_SPLITS(chunknames, GENETICQC.out.snpchunks_merge.collect())
    
    MERGER_SPLITS.out
        .collect()
        .flatten()
        .map{ fn -> tuple(fn.getSimpleName(), fn) }
        .concat(cache)
        .set{ chrsqced }

    // Prepare channels for downstream analysis
    chrsqced
        .groupTuple(by: 0)
        .flatten()
        .collate(5)
        .set{ gallop_plink_input }

    chrsqced
        .groupTuple(by: 0)
        .flatten()
        .filter(~/.*pvar/)
        .map{ it -> tuple(it.getSimpleName(), it) }
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

    // ==================================================================================
    // DATA PREPARATION PHASE
    // ==================================================================================
    PHENOS_FILE = GETPHENOS(params.covarfile)
    ALLPHENOS = GETPHENOS.out.allphenos.readLines()
    REMOVEOUTLIERS(GWASQC.out.gwasqc_h5_file, params.covarfile, ALLPHENOS)
    COMPUTE_PCA(REMOVEOUTLIERS.out.flatten(), input_compute_pca)
    MERGE_PCA(COMPUTE_PCA.out.eigenvec)

    // Branch based on analysis type
    if (params.longitudinal_flag | params.survival_flag) {
        GALLOPCOX_INPUT(gallopcph_chunks)

        gallop_plink_input
            .cross(GALLOPCOX_INPUT.out.splitText(file: true))
            .flatten()
            .collate(7)
            .map{ it -> tuple(it[0], it[1], it[2], it[3], it[4], it[6]) }
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