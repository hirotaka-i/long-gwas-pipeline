/*
 * Consolidated Data Preparation Module
 * Contains all data preparation processes:
 * - GETPHENOS: Extract unique cohorts from covariates
 * - REMOVEOUTLIERS: Remove outliers and kinship-related samples
 * - COMPUTE_PCA: Compute principal components for each cohort
 * - MERGE_PCA: Merge PCA results with sample data
 * - GALLOPCOX_INPUT: Prepare input chunks for GALLOP/CPH analysis
 * - RAWFILE_EXPORT: Export raw files for longitudinal/survival analysis
 * - EXPORT_PLINK: Export PLINK format for GLM analysis
 */

process GETPHENOS {
  scratch true
  label 'small'
  
  input:
    path covarfile, stageAs: 'covariates.tsv'
  output:
    path "phenos_list.txt", emit: allphenos
  
  script:
    """
    echo "=== GETPHENOS Debug Info ===" >&2
    echo "PWD: \$PWD" >&2
    echo "Files in current directory:" >&2
    ls -lah >&2
    echo "Covariate file exists: \$(test -f covariates.tsv && echo 'YES' || echo 'NO')" >&2
    echo "Covariate file size: \$(wc -l covariates.tsv 2>&1)" >&2
    echo "Python version: \$(python --version 2>&1)" >&2
    echo "get_phenos.py location: \$(which get_phenos.py 2>&1)" >&2
    echo "Running: get_phenos.py covariates.tsv ${params.study_col}" >&2
    echo "===========================" >&2
    
    set -x
    get_phenos.py covariates.tsv "${params.study_col}"
    set +x
    
    echo "=== GETPHENOS Completed ===" >&2
    echo "Output file created: \$(test -f phenos_list.txt && echo 'YES' || echo 'NO')" >&2
    test -f phenos_list.txt && echo "Output contents:" >&2 && cat phenos_list.txt >&2
    """
}

process REMOVEOUTLIERS {
  scratch true
  label 'medium'
  storeDir "${STORE_DIR}/${params.dataset}/p3_COVARIATES_QC/${params.out}"

  input:
    path samplelist
    path covarfile, stageAs: 'covariates.tsv'
    each cohort
  output:
    path "${params.ancestry}_${cohort}_filtered.tsv"

  script:
    """
    remove_outliers.py "${samplelist}" covariates.tsv "${cohort}" "${params.ancestry}" "${params.study_col}" "${params.kinship}"
    """
}

process COMPUTE_PCA {
  scratch true
  label 'large_mem'
  storeDir "${STORE_DIR}/${params.dataset}/p3_PCA_QC/"
  publishDir "${OUTPUT_DIR}/${params.dataset}/LOGS/COMPUTE_PCA_${params.datetime}/", mode: 'copy', overwrite: true, pattern: "*.log"

  input:
    each path(samplelist)
    path "*"
    
  output:
    tuple path(samplelist), path("${cohort_prefix}.pca.eigenvec"), emit: eigenvec

  script:
    def m = []
    def cohort = ""
    cohort = samplelist.getName()
    m = cohort =~ /(.*)_filtered.tsv/
    cohort = m[0][1]
    cohort_prefix = "${cohort}"
    
    """
    plink2 \
          --indep-pairwise 50 .2 \
          --maf ${params.minor_allele_freq} \
          --pfile "allchr_${params.dataset}_p2in" \
          --out ${cohort}.ld

    plink2 \
          --keep ${samplelist} \
          --out ${cohort}.pca \
          --extract ${cohort}.ld.prune.in \
          --pca 10 \
          --threads ${task.cpus} \
          --memory ${task.memory.toMega()} \
          --pfile "allchr_${params.dataset}_p2in"
    """
}

process MERGE_PCA {
  scratch true
  label 'small'
  
  input:
    tuple path(samplelist), path(cohort_pca)
  
  output:
    path "${params.ancestry}_*_filtered.pca.tsv"
  
  script:
    """
     #!/usr/bin/env python3
     import pandas as pd
     import time   
     import os
     
     print(os.listdir())
     sample_fn = "${samplelist.getName()}"
     cohort = sample_fn[:-(len('_filtered.tsv'))]
     pc_fn = cohort + '.pca.eigenvec'

     print(pc_fn, cohort)
     pc_df = pd.read_csv(pc_fn, sep="\\t")
     samples_df = pd.read_csv(sample_fn, sep="\\t")
     pc_df.rename(columns={"#IID": "IID"}, inplace=True)
     samples_df = samples_df.merge(pc_df, on="IID")
     
     samples_df.to_csv(cohort + '_filtered.pca.tsv', sep="\\t", index=False)
     time.sleep(5)
     """
}

process GALLOPCOX_INPUT {
  scratch true
  label 'small'
  
  input:
    tuple val(chrname), path(plink_input)
  output:
    tuple val(chrname), path("allchr_${params.dataset}_p2in.txt")
  
  script:
    """
    #!/usr/bin/env python3
    fn = "${plink_input}"
    out_fn = "allchr_${params.dataset}_p2in.txt"
    count = 0
    id_pairs = []
    start, end =  None,None
    with open(fn, 'r') as f:
      for l in iter(f.readline, ''):
        if l[0] == '#':
          continue
        data = l.strip().split('\\t')
        vid = data[2]
        count += 1
        if start is None:
          start = vid

        if count >= ${params.chunk_size}:
          end = vid
          id_pairs.append( (start, end) )
          start = None
          end = None
          count = 0

    if count > 0:
      end = vid
      id_pairs.append( (start, end) )

    with open(out_fn, 'w') as f:
      for start,end in id_pairs:
        f.write( '\\t'.join([start,end]) + '\\n' )
    """
}

process RAWFILE_EXPORT {
  scratch true
  label 'small'
  publishDir "${OUTPUT_DIR}/${params.dataset}/LOGS/RAWFILE_EXPORT_${params.datetime}/", mode: 'copy', overwrite: true, pattern: "*.log"

  input:
    tuple val(fSimple), path(plog), path(pgen), path(psam), path(pvar), path(plink_chunk)
    each path(samplelist)

  output:
    tuple val(fSimple), path(samplelist), path('*.raw'), emit: gwas_rawfile
    path "*.log", emit: gwas_rawfile_log

  when:
    params.longitudinal_flag || params.survival_flag

  script:
    def cohort = ""
    cohort = samplelist.getName()
    m = cohort =~ /(.*)_filtered.pca.tsv/
    cohort = m[0][1]

    def outfile = "${cohort}_${fSimple}"

    """
    set -x
    from=\$(cat $plink_chunk | cut -f 1)
    to=\$(cat $plink_chunk | cut -f 2)
    echo \${from}
    echo \${to}
    nameout="${outfile}_\${from}_\${to}"

    plink2 --pfile ${fSimple} \
           --keep ${samplelist} \
           --export A \
           --from \${from} \
           --to \${to} \
           --mac ${params.minor_allele_ct} \
           --update-sex ${samplelist} \
           --pheno ${samplelist} \
           --pheno-col-nums 4 \
           --hwe 1e-6 \
           --out "\${nameout}"  \
           --threads ${task.cpus} \
           --memory ${task.memory.toMega()}
    """
}

process EXPORT_PLINK {
  debug true
  scratch true
  label 'small'

  input:
    path samplelist
    path x, stageAs: 'phenotypes.tsv'
  output:
    path "*_analyzed.tsv", optional: true

  script:
    def m = []
    def cohort = ""
    cohort = samplelist.getName()
    m = cohort =~ /(.*)_filtered.pca.tsv/
    outfile = "${m[0][1]}"

    def pheno_name = "y"
    if (params.pheno_name != '') {
      pheno_name = "${params.pheno_name}"
    }

    """
    #!/usr/bin/env python3
    import pandas as pd
    import time
    import sys

    all_phenos = "${pheno_name}".split(',') if ',' in "${pheno_name}" else ["${pheno_name}"]
    covars = "${params.covariates}".split(' ')
    d_pheno = pd.read_csv("phenotypes.tsv", sep="\\t", engine='c')
    d_sample = pd.read_csv("${samplelist}", sep="\\t", engine='c')

    d_result = pd.merge(d_pheno, d_sample, on='IID', how='inner')

    if d_result.shape[0] > 0:
      d_set = d_result.loc[:, ["#FID", "IID"] + all_phenos + covars].copy()
      d_set.to_csv("${outfile}_analyzed.tsv", sep="\\t", index=False)

    time.sleep(10)
    """
}
