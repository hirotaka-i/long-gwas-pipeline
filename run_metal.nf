#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

/*
 * Minimal METAL workflow for GWAS summary statistics.
 *
 * Required:
 *   --metal_input    Glob pattern or comma-separated list of input files
 *   long gwas output with the folloiwng columns (header names are case-sensitive):
 *  #CHROM	POS	ID	REF	ALT	A1	A1_FREQ	MISS_FREQ	OBS_CT	TEST	BETA	exp(BETA)	SE	P
 *  This pipeline adds A2 column based on A1 and REF/ALT
 *
 * Optional:
 *   --metal_outdir   Output directory (default: "${launchDir}/metal_results")
 *   --metal_prefix   Output prefix (default: "SURV_META")
 */

process RUN_METAL {
    label 'medium'
    publishDir "${params.metal_outdir}", mode: 'copy', overwrite: true

    input:
    path sumstats_files

    output:
    path "${params.metal_prefix}_metal_script.txt", emit: script
    path "prepared/*.metal.tsv.gz", emit: prepared
    path "${params.metal_prefix}_command.log", emit: log, optional: true
    path "${params.metal_prefix}*", emit: results

    script:
    """
    set -euo pipefail

    mkdir -p prepared

    cat > ${params.metal_prefix}_metal_script.txt << 'METAL_EOF'
SCHEME STDERR
GENOMICCONTROL OFF
AVERAGEFREQ ON
MINMAXFREQ ON
CUSTOMVARIABLE TotalSampleSize
LABEL TotalSampleSize AS OBS_CT
MARKER ID
FREQ A1_FREQ
ALLELE A1 A2
EFFECT BETA
STDERR SE
PVAL P
WEIGHT OBS_CT
METAL_EOF

    total_ref=0
    total_alt=0

    for f in ${sumstats_files}; do
      base=\$(basename "\$f")
      out="prepared/\${base%.gz}.metal.tsv"

      ( [[ "\$f" == *.gz ]] && zcat "\$f" || cat "\$f" ) | awk -v count_file="\${out}.counts" 'BEGIN{FS=OFS="\\t"; c_ref=0; c_alt=0}
        NR==1 {
          for (i=1; i<=NF; i++) {
            if (\$i == "REF") ref_col=i
            else if (\$i == "ALT") alt_col=i
            else if (\$i == "A1") a1_col=i
          }
          print \$0, "A2";
          next
        }
        {
          a2="."
          if (\$a1_col == \$ref_col) { a2=\$alt_col; c_ref++ }
          else if (\$a1_col == \$alt_col) { a2=\$ref_col; c_alt++ }
          print \$0, a2
        }
        END { printf("%d\\t%d\\n", c_ref, c_alt) > count_file }' > "\$out"

      a1_eq_ref=\$(cut -f1 "\${out}.counts")
      a1_eq_alt=\$(cut -f2 "\${out}.counts")
      rm -f "\${out}.counts"

      total_ref=\$((total_ref + a1_eq_ref))
      total_alt=\$((total_alt + a1_eq_alt))

      echo "[A2_BUILD] file=\$base A1_EQ_REF=\$a1_eq_ref A1_EQ_ALT=\$a1_eq_alt"
      gzip -f "\$out"
      echo "PROCESS \${out}.gz" >> ${params.metal_prefix}_metal_script.txt
    done
    
    echo "[A2_BUILD] total A1_EQ_REF=\$total_ref A1_EQ_ALT=\$total_alt"

    cat >> ${params.metal_prefix}_metal_script.txt << METAL_EOF
OUTFILE ${params.metal_prefix} .TBL
ANALYZE HETEROGENEITY
QUIT
METAL_EOF

    metal ${params.metal_prefix}_metal_script.txt
    
    cp .command.log ${params.metal_prefix}_command.log || true
    """
}

workflow {
  if (!params.metal_input) {
    error "Missing required parameter: --metal_input"
  }

  def inputPatterns = params.metal_input
    .toString()
    .split(',')
    .collect { it.trim() }
    .findAll { it }

  def metal_input_files_ch = Channel
    .fromPath(inputPatterns, checkIfExists: true)
    .ifEmpty { error "No files matched --metal_input: ${params.metal_input}" }
    .collect()

    RUN_METAL(metal_input_files_ch)
}
