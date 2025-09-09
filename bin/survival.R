#!/usr/bin/env Rscript

library('survival')
library('optparse')

option_list <- list(
  make_option( c("--covar"), type="character", default=NULL,
                 help="cross-sectional covariates"),
  make_option( c("--pheno"), type="character", default=NULL,
                 help="phenotype or outcome"),
  make_option( c("--rawfile"), type="character", default=NULL,
                 help="rawfile"),
  make_option( c("--covar-name"), type="character", default=NULL,
                 help="space delimited covariate list"),
  make_option( c("--pheno-name"), type="character", default="y",
                 help="phenotype / outcome column name"),
  make_option( c("--out"), type="character", 
                 default="survival.tbl",
                 help="output file")
) 

# the following are requirements for survival analysis
# tstart - time start for period, always 0 for cross-sectional analysis
# tend - time end for period


parser <- OptionParser(option_list=option_list)
arguments <- parse_args( parser, positional_arguments=TRUE )
opt <- arguments$options
args <- arguments$args

input.covariates <- strsplit(opt[['covar-name']], ' ')

print(input.covariates)


data.pheno = read.table(opt$pheno, header=TRUE, comment.char='')
data.covar = read.table(opt$covar, header=TRUE, comment.char='')

# function never completes on large rawfile
#data.geno = read.table(opt$rawfile, header=TRUE, comment.char='')
lines <- readLines(opt$rawfile)
input.genodata <- sapply(lines, function(x) unlist(strsplit(x, '\t')))
rm(lines)
gc()

n_cols = dim(input.genodata)[1]
n_rows = dim(input.genodata)[2]
offset_col = 7 # offset for rawfile format

print('finished loading data')
data.merged = merge(data.covar, data.pheno)
                         
SNPs = input.genodata[
  grepl("^chr[0-9]", input.genodata[,1]),1]
n_snps <- length(SNPs)
                         
                         
# ----- Create SumStats Table ----
print( paste("Found", as.character(n_snps), "SNPs") )

tmp.split <- sapply(SNPs,
         function(x) strsplit(x, ':'))
                    
# initialize matrix
snp_data <- matrix(NA, n_rows-1, n_snps)
iids <- matrix('', n_rows-1, 1)
stats <- matrix(NA, n_snps, 4)
                    
options(warn=-1)
                    
for (i in 2:n_rows) {
  snp_data[i-1,] <- as.numeric(
    input.genodata[offset_col:n_cols,i])
  iids[i-1,] <- input.genodata[2,i]
}

rm(input.genodata)
gc()
      
# initialize geno dataframe for model
data.geno <- data.frame(
  cbind(iids, snp_data[,1]))
colnames(data.geno) <- c('IID', 'SNP')
                    
basemod <- paste0("Surv(tstart,tend,", opt[['pheno-name']], ")~")
basemod <- paste0(basemod, paste(unlist(input.covariates), collapse="+"))
mod_cols = c('coef', 'exp(coef)', 'se(coef)', 'Pr(>|z|)')
print( paste("Base survival model", basemod) )

# ------ Fit CoxPH model ----

test_data <- matrix('', n_snps, 10)

for (i in 1:n_snps) {
  parts <- unlist(tmp.split[[i]]) # expecting (chr, pos, ref, alt_a1)
  ref <- parts[3]
  alt_a1 <- strsplit(parts[4], '_', fixed=TRUE)[[1]]
  alt <- alt_a1[1]
  counted_raw  <- if (length(alt_a1) > 1) alt_a1[2] else ref # plink2 default counts ref
  counted = sub("\\(.*$", "", counted_raw) # reformat in case 1:234356:A:T_A/(C)
  
  marker.id <- paste(parts[1],parts[2], ref, alt, sep=":")

  # recode to ALT dosage so β is per ALT (A1) allele
  alt_counts <- if (counted == ref) 2 - snp_data[, i] else snp_data[, i]

  obs_ct <- sum(!is.na(alt_counts))
  alt_freq <- sum(alt_counts, na.rm=TRUE) / (obs_ct * 2)
  miss_freq <- 1 - obs_ct / length(alt_counts)
  
  test_data[i,] <- c(parts[1:2], 
                     marker.id,
                     ref, alt, alt, # ref, alt, a1 (tested) 
                     alt_freq, 
                     miss_freq, 
                     obs_ct, 
                     'CoxPH')
  
  # test SNP
  data.geno$SNP <- alt_counts
  data.mtx = merge( data.merged, data.geno, by='IID' )
  eq = paste0(basemod, "+", 'SNP')
  mdl = coxph(as.formula(eq), data=data.mtx)
  res = summary(mdl)
  stats[i,] = res$coefficients['SNP',][mod_cols]
}
                    
                    
stats = as.data.frame(stats)
colnames(stats) = c('BETA', 'exp(BETA)', 'SE', 'P')
test_data <- as.data.frame(test_data)
colnames(test_data) = c('#CHROM', 'POS', 'ID', 'REF', 'ALT', 'A1', 
                        'A1_FREQ', 'MISS_FREQ', 'OBS_CT', 'TEST')

stats = cbind(test_data, stats)
write.table(stats, file=opt$out, sep="\t", row.names=FALSE, quote=FALSE)
