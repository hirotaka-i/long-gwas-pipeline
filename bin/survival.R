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
  make_option( c("--covar-categorical"), type="character", default="",
                 help="space delimited categorical covariate list"),
  make_option( c("--covar-interact"), type="character", default="",
                 help="covariate to test for interaction with SNP (must be numeric)"),
  make_option( c("--pheno-name"), type="character", default="y",
                 help="phenotype / outcome column name"),
  make_option( c("--time-col"), type="character", default="study_days",
                 help="time column name for generating tstart/tend if not provided"),
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

input.covariates <- unlist(strsplit(opt[['covar-name']], ' '))

print(input.covariates)



# Parse categorical covariates
input.categorical <- c()
if (opt[['covar-categorical']] != "" && !is.null(opt[['covar-categorical']])) {
  input.categorical <- unlist(strsplit(opt[['covar-categorical']], ' '))
  print(paste("Categorical covariates:", paste(input.categorical, collapse=", ")))
}

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

# Generate tstart and tend from time_col if they don't exist
if (!('tstart' %in% colnames(data.merged)) && !('tend' %in% colnames(data.merged))) {
  time_col <- opt[['time-col']]
  if (!(time_col %in% colnames(data.merged))) {
    stop(paste("Error: time column '", time_col, "' not found in phenotype data. ",
               "Either provide tstart/tend columns or ensure '", time_col, "' exists.", sep=""))
  }
  print(paste("Generating tstart=0 and tend from time column:", time_col))
  data.merged$tstart <- 0
  data.merged$tend <- data.merged[[time_col]]
} else if (!('tstart' %in% colnames(data.merged)) || !('tend' %in% colnames(data.merged))) {
  stop("Error: Both tstart and tend columns must be present, or neither (to auto-generate from time_col)")
} else {
  print("Using existing tstart and tend columns from phenotype data")
}

# Convert categorical covariates to factors
if (length(input.categorical) > 0) {
  for (cat_cov in input.categorical) {
    if (cat_cov %in% colnames(data.merged)) {
      data.merged[[cat_cov]] <- as.factor(data.merged[[cat_cov]])
      print(paste("Converted", cat_cov, "to factor with", 
                  length(levels(data.merged[[cat_cov]])), "levels"))
    } else {
      warning(paste("Categorical covariate", cat_cov, "not found in merged data"))
    }
  }
}
all.covariates <- unlist(c(input.covariates, input.categorical))
# Check for and remove constant covariates
valid.covariates <- c()
for (cov in unlist(all.covariates)) {
  if (length(unique(data.merged[[cov]])) <= 1) {
    warning(paste("Covariate", cov, "has only one unique value and will be dropped from the model"))
  } else {
    valid.covariates <- c(valid.covariates, cov)
  }
}
input.covariates <- intersect(input.covariates, valid.covariates)
input.categorical <- intersect(input.categorical, valid.covariates)

if (length(valid.covariates) == 0) {
  stop("No valid covariates remaining after filtering constant covariates")
}

# Validate interaction covariate
use_interaction <- FALSE
interact_covar <- ""
if (opt[['covar-interact']] != "" && !is.null(opt[['covar-interact']])) {
  interact_covar <- opt[['covar-interact']]
  
  # Check if interaction covariate is in covariates list
  if (!(interact_covar %in% unlist(input.covariates))) {
    warning(paste("Interaction covariate", interact_covar, "not found in covariates list. Skipping interaction analysis."))
  } else if (!(interact_covar %in% valid.covariates)) {
    warning(paste("Interaction covariate", interact_covar, "is not valid (constant or missing). Skipping interaction analysis."))
  } else if (interact_covar %in% input.categorical) {
    warning(paste("Interaction covariate", interact_covar, "is categorical. Interaction requires numeric covariate. Skipping interaction analysis."))
  } else {
    # Check if it's numeric
    if (!is.numeric(data.merged[[interact_covar]])) {
      warning(paste("Interaction covariate", interact_covar, "is not numeric. Skipping interaction analysis."))
    } else {
      use_interaction <- TRUE
      print(paste("Testing interaction between SNPs and", interact_covar))
    }
  }
}
                         
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
# Adjust stats matrix size based on whether interaction is used
stats <- matrix(NA, n_snps, if (use_interaction) 8 else 4)
                    
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
print( paste("Base survival model (+SNP + SNP:interaction if specified)", basemod) )

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
  
  if (use_interaction) {
    # Test SNP with interaction term
    eq = paste0(basemod, "+", 'SNP+SNP:', interact_covar)
    mdl = coxph(as.formula(eq), data=data.mtx)
    res = summary(mdl)
    
    # Extract main SNP effect
    snp_stats = res$coefficients['SNP',][mod_cols]
    
    # Extract interaction effect (could be SNP:covar or covar:SNP based on alphabetical order)
    interact_term1 <- paste0('SNP:', interact_covar)
    interact_term2 <- paste0(interact_covar, ':SNP')
    interact_term <- if (interact_term1 %in% rownames(res$coefficients)) interact_term1 else interact_term2
    interact_stats = res$coefficients[interact_term,][mod_cols]
    
    # Combine: main effect + interaction effect
    stats[i,] = c(snp_stats, interact_stats)
  } else {
    # Ordinary analysis without interaction
    eq = paste0(basemod, "+", 'SNP')
    mdl = coxph(as.formula(eq), data=data.mtx)
    res = summary(mdl)
    stats[i,] = res$coefficients['SNP',][mod_cols]
  }
}
                    
                    
stats = as.data.frame(stats)
if (use_interaction) {
  colnames(stats) = c('BETA', 'exp(BETA)', 'SE', 'P', 'BETAi', 'exp(BETAi)', 'SEi', 'Pi')
} else {
  colnames(stats) = c('BETA', 'exp(BETA)', 'SE', 'P')
}

test_data <- as.data.frame(test_data)
colnames(test_data) = c('#CHROM', 'POS', 'ID', 'REF', 'ALT', 'A1', 
                        'A1_FREQ', 'MISS_FREQ', 'OBS_CT', 'TEST')

stats = cbind(test_data, stats)
write.table(stats, file=opt$out, sep="\t", row.names=FALSE, quote=FALSE)
