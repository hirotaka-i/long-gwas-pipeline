process MANHATTAN {
  scratch true
  label 'medium'

  publishDir "${OUTPUT_DIR}/${params.dataset}/RESULTS/${model}_MANHATTAN_${params.datetime}", mode: 'copy', overwrite: true

  input:
    each x
    val(model)
  output:
    path "*.png"

  script:
  """
  manhattan.py --input ${x} --model ${model} --suffix ${params.out}
  """
}