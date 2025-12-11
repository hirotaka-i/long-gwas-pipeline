#!/bin/bash
# Take the vcf file (genotyped or imputed)
# Return: pass(&R2)-filtered, lifted to hg38 (if needed), split, left-normalized, autosomal-par, hg38-ref-alt-aligned SNPs with mac >=2. geno < 0.05

# Parameters
N=$1 # Threads to use
VFILE=$2
R2THRES=$3 # If imputed, give a number for R2 threshold (usually 0.3 - 0.8) -9 otherwise
ASSEMBLY=$4 # [hg18, hg19, hg38]. Define if the liftover is required or not
CHRNUM=$5 # [1..22] Needed for lift over. 
FILE=$6 # Base file name. can be anything as long as unique
## e.g. process1.sh 2 '/data/CARD/PD/imputed_data/CORIELL/chr21.dose.vcf.gz' 0.3 hg19 21 chr21_cor

# Resources (Uses RESOURCE_DIR environment variable from nextflow.config profiles)
# Default to Docker paths if RESOURCE_DIR not set (for backward compatibility)
RESOURCE_DIR=${RESOURCE_DIR:-/srv/GWAS-Pipeline/References}
FA=${RESOURCE_DIR}/Genome/hg38.fa.gz
LIFTOVERCHAIN=${RESOURCE_DIR}/liftOver/${ASSEMBLY}ToHg38.over.chain.gz


######## start processing ###############################
# Step 1: Filter PASS (&R2 if imputed) and add "chr" prefix if missing
## Different pipeline for imputed and genotyped (R2THRES>0....imputed)
if [[ $R2THRES > 0 ]]
then 
    bcftools view -f '.,PASS' \
                  -i "INFO/R2>${R2THRES}" ${VFILE} \
                  -Oz -o ${FILE}_filtered_temp.vcf.gz --threads ${N} # get PASS(or .) variant and R2>R2THRES
else
    bcftools view -f '.,PASS' ${VFILE} \
                  -Oz -o ${FILE}_filtered_temp.vcf.gz --threads ${N}
fi

# Check if chromosomes need "chr" prefix and add if missing
FIRST_CHR=$(bcftools view -H ${FILE}_filtered_temp.vcf.gz | head -1 | cut -f1)
if [[ ! "$FIRST_CHR" =~ ^chr ]]; then
    echo "Adding 'chr' prefix to chromosome names..."
    bcftools annotate --rename-chrs <(bcftools view -h ${FILE}_filtered_temp.vcf.gz | \
        grep "^##contig" | sed 's/.*ID=\([^,]*\).*/\1/' | \
        awk '{if ($1 !~ /^chr/ && $1 ~ /^[0-9XYM]/) print $1"\tchr"$1; else print $1"\t"$1}') \
        ${FILE}_filtered_temp.vcf.gz -Oz -o ${FILE}_filtered.vcf.gz --threads ${N}
    rm ${FILE}_filtered_temp.vcf.gz
else
    echo "Chromosome names already have 'chr' prefix"
    mv ${FILE}_filtered_temp.vcf.gz ${FILE}_filtered.vcf.gz
fi

# Step 2: Liftover to hg38 if needed (IN VCF FORMAT, BEFORE splitting)
if [[ $ASSEMBLY = hg38 ]]
then
    # Already hg38, just copy
    cp ${FILE}_filtered.vcf.gz ${FILE}_hg38.vcf.gz
else
    # Liftover using bcftools +liftover plugin
    # Note: bcftools +liftover requires both source and destination reference genomes
    ASSEMBLY_FA=${RESOURCE_DIR}/Genome/${ASSEMBLY}.fa.gz
    
    bcftools +liftover ${FILE}_filtered.vcf.gz \
             --threads ${N} \
             -Oz -o ${FILE}_hg38.vcf.gz \
             -- \
             -s ${ASSEMBLY_FA} \
             -f ${FA} \
             -c ${LIFTOVERCHAIN} \
             --reject ${FILE}_rejected.vcf.gz \
             --reject-type z
fi

# Step 3: Split multiallelic variants
bcftools norm -m-both ${FILE}_hg38.vcf.gz \
          -Oz -o ${FILE}_split.vcf.gz --threads ${N}

# Step 4: Convert to plink format (after liftover and split)
if [[ $R2THRES > 0 ]]
then
    plink2 --threads ${N} \
           --vcf ${FILE}_split.vcf.gz dosage=DS \
           --make-pgen --allow-extra-chr --autosome-par --out ${FILE}_split
else
    plink2 --threads ${N} \
           --vcf ${FILE}_split.vcf.gz --make-pgen --allow-extra-chr --autosome-par --out ${FILE}_split
fi

# Step 5: Left-normalize using fasta file (hg38)
plink2 --threads ${N} \
       --pfile ${FILE}_split --make-pgen --fa $FA --normalize --sort-vars --out ${FILE}_split_hg38_normalized

# select relevant snps with more than sigleton (For small cohorts, this process reduces a lot of variants)
plink2 --threads ${N} --pfile ${FILE}_split_hg38_normalized --make-pgen --snps-only just-acgt --mac 2 --out ${FILE}_split_hg38_normalized_snps
# align ref alt (This will return provisional variants sometime)
plink2 --threads ${N} --pfile ${FILE}_split_hg38_normalized_snps --make-pgen --ref-from-fa force --fa $FA --out ${FILE}_split_hg38_normalized_snps_temp_aligned
# remove the "Provisional variants" because provisional variants prevents loading on plink2
grep 'PR$' ${FILE}_split_hg38_normalized_snps_temp_aligned.pvar | cut -f3 > ${FILE}_split_hg38_normalized_snps_temp_aligned_provisional.txt
plink2 --threads ${N} --pfile ${FILE}_split_hg38_normalized_snps --make-pgen --ref-from-fa force --fa $FA --exclude ${FILE}_split_hg38_normalized_snps_temp_aligned_provisional.txt --out ${FILE}_split_hg38_normalized_snps_aligned
# remame ID for standard chr:pos:ref:alt
plink2 --threads ${N} --pfile ${FILE}_split_hg38_normalized_snps_aligned --make-pgen --set-all-var-ids 'chr@:#:$r:$a' --out ${FILE}_split_hg38_normalized_snps_aligned_renamed
# remove dup
plink2 --threads ${N} --pfile ${FILE}_split_hg38_normalized_snps_aligned_renamed --make-pgen --rm-dup exclude-all --out ${FILE}_split_hg38_normalized_snps_aligned_renamed_uniq
# geno 0.05
plink2 --threads ${N} --pfile ${FILE}_split_hg38_normalized_snps_aligned_renamed_uniq --make-pgen --geno 0.05 dosage --out ${FILE}_p1out
