#!/usr/bin/env python3
"""
Remove outliers and kinship-related samples from covariate data.
Used by REMOVEOUTLIERS process.
"""
import pandas as pd
import sys
import time

def main():
    if len(sys.argv) < 7:
        print("Usage: remove_outliers.py <samplelist.h5> <covariates.tsv> <cohort> <ancestry> <study_col> <kinship_threshold>")
        sys.exit(1)
    
    samplelist_file = sys.argv[1]
    covariates_file = sys.argv[2]
    cohort = sys.argv[3]
    ancestry = sys.argv[4]
    study_id_colname = sys.argv[5]
    kinship_threshold = float(sys.argv[6])
    
    # Read data files
    ancestry_df = pd.read_hdf(samplelist_file, key="ancestry_keep")
    outlier_df = pd.read_hdf(samplelist_file, key="outliers")
    kin_df = pd.read_hdf(samplelist_file, key="kin")
    data_df = pd.read_csv(covariates_file, sep="\t", engine='c')
    
    # Filter cohorts
    cohorts = data_df[study_id_colname].unique().tolist()
    cohorts = filter(lambda x: x == cohort, cohorts)
    
    # Filter kinship
    kin_df = kin_df[kin_df.KINSHIP >= kinship_threshold]
    
    # Process each cohort
    for cohort in cohorts:
        print(f'---- {cohort} ----')
        
        if not outlier_df.empty:
            samples = data_df[(data_df.IID.isin(ancestry_df.IID)) &
                             (data_df[study_id_colname] == cohort) &
                             ~(data_df.IID.isin(outlier_df.IID))].copy(deep=True)
            print(f'Samples removed (outliers) = {data_df.IID.isin(outlier_df.IID).sum()}')
        else:
            samples = data_df[(data_df.IID.isin(ancestry_df.IID)) &
                             (data_df[study_id_colname] == cohort)].copy(deep=True)
        
        r = kin_df[(kin_df['#IID1'].isin(samples.IID)) & (kin_df.IID2.isin(samples.IID))].copy()
        samples = samples[~samples.IID.isin(r.IID2)].copy()
        samples.to_csv(f"{ancestry}_{cohort}_filtered.tsv", sep="\t", index=False)
        print(f'Samples removed (kinship) = {r.shape[0]}')
        print(f'Samples remaining = {len(samples)}')
        print('')
    
    time.sleep(5)

if __name__ == "__main__":
    main()
