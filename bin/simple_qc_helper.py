#!/usr/bin/env python3
"""
Helper script for simple_qc.sh - creates HDF5 file and PCA plots
Used in skip population splitting mode for ancestry-specific data QC
"""
import pandas as pd
import sys
import matplotlib.pyplot as plt

def create_pca_plots(pcs_df, output_prefix):
    """
    Create scatter plots of PC1 vs PC2 and PC1 vs PC3
    
    Args:
        pcs_df: DataFrame with PCA results
        output_prefix: Prefix for output files
    """
    # Set style
    plt.style.use('default')
    
    # Determine IID column name
    iid_col = '#IID' if '#IID' in pcs_df.columns else 'IID'
    
    # PC1 vs PC2
    fig, ax = plt.subplots(figsize=(10, 8))
    ax.scatter(pcs_df['PC1'], pcs_df['PC2'], alpha=0.6, s=30, c='steelblue', edgecolors='black', linewidth=0.5)
    ax.set_xlabel('PC1', fontsize=12, fontweight='bold')
    ax.set_ylabel('PC2', fontsize=12, fontweight='bold')
    ax.set_title('Principal Components: PC1 vs PC2', fontsize=14, fontweight='bold')
    ax.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(f'{output_prefix}_PC1_PC2.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    # PC1 vs PC3
    fig, ax = plt.subplots(figsize=(10, 8))
    ax.scatter(pcs_df['PC1'], pcs_df['PC3'], alpha=0.6, s=30, c='coral', edgecolors='black', linewidth=0.5)
    ax.set_xlabel('PC1', fontsize=12, fontweight='bold')
    ax.set_ylabel('PC3', fontsize=12, fontweight='bold')
    ax.set_title('Principal Components: PC1 vs PC3', fontsize=14, fontweight='bold')
    ax.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(f'{output_prefix}_PC1_PC3.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    print(f'✅ PCA plots saved: {output_prefix}_PC1_PC2.png, {output_prefix}_PC1_PC3.png')


def collect_outliers(geno, has_fid):
    """
    Collect outlier information from QC steps
    
    Args:
        geno: Input genotype prefix
        has_fid: Boolean indicating if FID column exists
    
    Returns:
        DataFrame with outlier information
    """
    outliers_data = []
    
    # Callrate outliers
    try:
        removed_callrate = pd.read_csv(f'{geno}.psam', sep='\t')
        kept_callrate = pd.read_csv(f'{geno}_callrate.psam', sep='\t')
        callrate_removed = removed_callrate[~removed_callrate['#IID'].isin(kept_callrate['#IID'])]
        for _, row in callrate_removed.iterrows():
            fid = row['#FID'] if has_fid else row['#IID']
            outliers_data.append({'FID': fid, 'IID': row['#IID'], 'reason': 'callrate'})
    except Exception as e:
        print(f'Warning: Could not process callrate outliers: {e}', file=sys.stderr)
    
    # Heterozygosity outliers
    try:
        het_keep = pd.read_csv(f'{geno}_het_keep.txt', sep='\s+')
        kept_callrate = pd.read_csv(f'{geno}_callrate.psam', sep='\t')
        het_removed = kept_callrate[~kept_callrate['#IID'].isin(het_keep['#IID'])]
        for _, row in het_removed.iterrows():
            fid = row['#FID'] if has_fid else row['#IID']
            outliers_data.append({'FID': fid, 'IID': row['#IID'], 'reason': 'heterozygosity'})
    except Exception as e:
        print(f'Warning: Could not process heterozygosity outliers: {e}', file=sys.stderr)
    
    # Kinship outliers
    try:
        kept_het = pd.read_csv(f'{geno}_callrate_het.psam', sep='\t')
        kept_king = pd.read_csv(f'{geno}_callrate_het_king.psam', sep='\t')
        king_removed = kept_het[~kept_het['#IID'].isin(kept_king['#IID'])]
        for _, row in king_removed.iterrows():
            fid = row['#FID'] if has_fid else row['#IID']
            outliers_data.append({'FID': fid, 'IID': row['#IID'], 'reason': 'kinship'})
    except Exception as e:
        print(f'Warning: Could not process kinship outliers: {e}', file=sys.stderr)
    
    return pd.DataFrame(outliers_data)


def create_ancestry_keep(pcs_df):
    """
    Create ancestry_keep DataFrame from PCA results
    
    Args:
        pcs_df: DataFrame with PCA results
    
    Returns:
        DataFrame with FID and IID columns
    """
    if '#FID' in pcs_df.columns:
        ancestry_keep = pcs_df[['#FID', 'IID']].copy()
        ancestry_keep.columns = ['FID', 'IID']
    else:
        # Only IID available
        ancestry_keep = pcs_df[['#IID']].copy()
        ancestry_keep.columns = ['IID']
        ancestry_keep['FID'] = ancestry_keep['IID']  # Use IID as FID
    
    return ancestry_keep


def main():
    if len(sys.argv) < 3:
        print("Usage: simple_qc_helper.py <geno_prefix> <output_prefix>")
        sys.exit(1)
    
    geno = sys.argv[1]
    out = sys.argv[2]
    
    print(f'Reading PCA results from {out}_pca.eigenvec...')
    pcs = pd.read_csv(f'{out}_pca.eigenvec', sep='\s+')
    
    print(f'Reading kinship table from {out}_king.kin0...')
    kin = pd.read_csv(f'{out}_king.kin0', sep='\s+')
    
    # Check if FID column exists
    sample_df = pd.read_csv(f'{geno}.psam', sep='\t')
    has_fid = '#FID' in sample_df.columns
    
    print('Collecting outlier information...')
    outliers_df = collect_outliers(geno, has_fid)
    
    print('Creating ancestry_keep dataframe...')
    ancestry_keep = create_ancestry_keep(pcs)
    
    print('Creating PCA plots...')
    create_pca_plots(pcs, out)
    
    print(f'Saving to HDF5: {out}.h5...')
    outliers_df.to_hdf(f'{out}.h5', key='outliers', mode='w')
    pcs.to_hdf(f'{out}.h5', key='pcs')
    kin.to_hdf(f'{out}.h5', key='kin')
    ancestry_keep.to_hdf(f'{out}.h5', key='ancestry_keep')
    
    print(f'✅ HDF5 file created: {out}.h5')
    print(f'✅ Total samples in analysis: {len(ancestry_keep)}')
    print(f'✅ Total outliers removed: {len(outliers_df)}')


if __name__ == "__main__":
    main()
