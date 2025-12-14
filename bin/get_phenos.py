#!/usr/bin/env python3
"""
Extract unique study arms from covariates file.
Used by GETSTUDYARMS process.
"""
import pandas as pd
import sys
import time

def main():
    if len(sys.argv) < 3:
        print("Usage: get_phenos.py <covariates_file> <study_arm_col>")
        sys.exit(1)
    
    covariates_file = sys.argv[1]
    study_arm_colname = sys.argv[2]
    
    data_df = pd.read_csv(covariates_file, sep="\t", engine='c')
    study_arms = data_df[study_arm_colname].unique().tolist()
    
    with open("phenos_list.txt", 'w') as f:
        f.write('\n'.join(study_arms))
    
    time.sleep(5)

if __name__ == "__main__":
    main()
