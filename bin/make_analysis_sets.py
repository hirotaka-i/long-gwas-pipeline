#!/usr/bin/env python3
"""
Create analysis sets by extracting study arms and filtering samples.
Removes outliers and kinship-related samples from covariate data.
Used by MAKEANALYSISSETS process.
"""
import pandas as pd
import sys
import time

def main():
    if len(sys.argv) < 6:
        print("Usage: make_analysis_sets.py <samplelist.h5> <covariates.tsv> <ancestry> <study_arm_col> <kinship_threshold>")
        sys.exit(1)
    
    samplelist_file = sys.argv[1]
    covariates_file = sys.argv[2]
    ancestry = sys.argv[3]
    study_arm_colname = sys.argv[4]
    kinship_threshold = float(sys.argv[5])
    
    # Read data files
    ancestry_df = pd.read_hdf(samplelist_file, key="ancestry_keep")
    outlier_df = pd.read_hdf(samplelist_file, key="outliers")
    kin_df = pd.read_hdf(samplelist_file, key="kin")
    data_df = pd.read_csv(covariates_file, sep="\t", engine='c')
    
    # Extract all unique study arms
    study_arms = data_df[study_arm_colname].unique().tolist()
    print(f'Found {len(study_arms)} study arms: {study_arms}')
    
    # Filter kinship
    kin_df = kin_df[kin_df.KINSHIP >= kinship_threshold]
    
    # Process each study arm
    for study_arm in study_arms:
        print(f'---- {study_arm} ----')
        
        if not outlier_df.empty:
            samples = data_df[(data_df.IID.isin(ancestry_df.IID)) &
                             (data_df[study_arm_colname] == study_arm) &
                             ~(data_df.IID.isin(outlier_df.IID))].copy(deep=True)
            print(f'Samples removed (outliers) = {data_df.IID.isin(outlier_df.IID).sum()}')
        else:
            samples = data_df[(data_df.IID.isin(ancestry_df.IID)) &
                             (data_df[study_arm_colname] == study_arm)].copy(deep=True)
        
        r = kin_df[(kin_df['#IID1'].isin(samples.IID)) & (kin_df.IID2.isin(samples.IID))].copy()
        samples = samples[~samples.IID.isin(r.IID2)].copy()
        samples.to_csv(f"{ancestry}_{study_arm}_filtered.tsv", sep="\t", index=False)
        print(f'Samples removed (kinship) = {r.shape[0]}')
        print(f'Samples remaining = {len(samples)}')
        print('')
    
    time.sleep(5)

if __name__ == "__main__":
    main()
