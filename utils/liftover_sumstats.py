#!/usr/bin/env python3
"""
Liftover summary statistics between genome builds using bcftools +liftover
"""

import argparse
import gzip
import sys
import subprocess
import tempfile
import os
import pandas as pd
from pathlib import Path
import gc


def open_file(filepath):
    """Open file, handling gzipped files"""
    if filepath.endswith('.gz'):
        return gzip.open(filepath, 'rt')
    return open(filepath, 'r')


def write_file(filepath):
    """Write file, handling gzipped files"""
    if filepath.endswith('.gz'):
        return gzip.open(filepath, 'wt')
    return open(filepath, 'w')


def sumstats_to_vcf(sumstats_file, vcf_file, chr_col, pos_col, ea_col, ref_col, 
                    rsid_col=None, add_chr_prefix=False, source_fasta=None):
    """
    Convert summary statistics to VCF format
    
    Args:
        sumstats_file: Input summary statistics file
        vcf_file: Output VCF file path
        chr_col: Chromosome column name
        pos_col: Position column name
        ea_col: Effect allele column name
        ref_col: Reference allele column name
        rsid_col: RSID column name (optional)
    """
    print(f"Reading summary statistics from {sumstats_file}...", file=sys.stderr)
    
    # Read summary stats
    df = pd.read_csv(sumstats_file, sep='\t', low_memory=False)
    
    # Check required columns
    required_cols = [chr_col, pos_col, ea_col, ref_col]
    missing_cols = [col for col in required_cols if col not in df.columns]
    if missing_cols:
        raise ValueError(f"Missing required columns: {missing_cols}")
    
    print(f"Loaded {len(df)} variants", file=sys.stderr)
    
    # Clean chromosome names - handle numeric chromosomes (may be float like 1.0)
    # Convert to string first to avoid dtype issues
    df[chr_col] = df[chr_col].astype(str).str.strip()
    
    # Try to convert numeric-looking chromosomes (remove .0)
    try:
        numeric_df = pd.to_numeric(df[chr_col], errors='coerce')
        numeric_mask = numeric_df.notna()
        # Convert to int to remove .0, then back to string
        df.loc[numeric_mask, chr_col] = numeric_df[numeric_mask].astype(int).astype(str)
    except:
        pass
    
    # Add chr prefix if requested (to match reference fasta)
    if add_chr_prefix:
        # Only add to numeric chromosomes and X, Y, MT, M
        simple_chroms = [str(i) for i in range(1, 23)] + ['X', 'Y', 'MT', 'M']
        mask = df[chr_col].isin(simple_chroms)
        df.loc[mask, chr_col] = 'chr' + df.loc[mask, chr_col]
        print(f"Added 'chr' prefix to {mask.sum()} chromosomes", file=sys.stderr)
    
    # Debug: show unique chromosome values
    unique_chrs = df[chr_col].unique()[:20]  # First 20 unique values
    print(f"Sample chromosome values after cleaning: {unique_chrs}", file=sys.stderr)
    
    # Filter to valid chromosomes (accept both with and without chr prefix)
    valid_chroms = [str(i) for i in range(1, 23)] + ['X', 'Y', 'MT', 'M']
    valid_chroms_with_chr = ['chr' + c for c in valid_chroms]
    all_valid = valid_chroms + valid_chroms_with_chr
    df = df[df[chr_col].isin(all_valid)].copy()
    print(f"Kept {len(df)} variants on valid chromosomes", file=sys.stderr)
    
    # Sort by chromosome and position (AFTER adding chr prefix)
    df[pos_col] = pd.to_numeric(df[pos_col], errors='coerce')
    df = df.dropna(subset=[pos_col])
    df[pos_col] = df[pos_col].astype(int)
    
    # Create sort key for chromosomes
    # Handle both with and without chr prefix
    def chr_sort_key(chr_str):
        chr_clean = chr_str.replace('chr', '')
        if chr_clean.isdigit():
            return int(chr_clean)
        elif chr_clean == 'X':
            return 23
        elif chr_clean == 'Y':
            return 24
        elif chr_clean in ['MT', 'M']:
            return 25
        else:
            return 99
    
    df['_chr_sort'] = df[chr_col].apply(chr_sort_key)
    df = df.sort_values(['_chr_sort', pos_col]).drop('_chr_sort', axis=1)
    print(f"Sorted {len(df)} variants by chromosome and position", file=sys.stderr)
    
    # Write VCF - write uncompressed first, then compress with bcftools
    print(f"Writing VCF to {vcf_file}...", file=sys.stderr)
    
    # Write to uncompressed file first
    temp_vcf = vcf_file.replace('.vcf.gz', '.vcf')
    with open(temp_vcf, 'w') as f:
        # Write header
        f.write("##fileformat=VCFv4.2\n")
        
        # Add contig definitions ONLY for chromosomes present in data (memory efficient)
        if source_fasta:
            print(f"Adding contig definitions for present chromosomes...", file=sys.stderr)
            try:
                # Get unique chromosomes in our data
                unique_chroms = set(df[chr_col].unique())
                
                # Read fasta index to get contig lengths ONLY for present chromosomes
                fai_file = source_fasta + '.fai'
                if os.path.exists(fai_file):
                    with open(fai_file, 'r') as fai:
                        for line in fai:
                            parts = line.strip().split('\t')
                            if len(parts) >= 2:
                                contig = parts[0]
                                # Only write contigs for chromosomes in our data
                                if contig in unique_chroms:
                                    length = parts[1]
                                    f.write(f"##contig=<ID={contig},length={length}>\n")
            except Exception as e:
                print(f"Warning: could not read contig definitions: {e}", file=sys.stderr)
        
        f.write("##INFO=<ID=RSID,Number=1,Type=String,Description=\"Original RSID\">\n")
        f.write("##INFO=<ID=ORIG_A1,Number=1,Type=String,Description=\"Original effect allele (A1)\">\n")
        f.write("##INFO=<ID=ORIG_A2,Number=1,Type=String,Description=\"Original reference allele (A2)\">\n")
        f.write("##INFO=<ID=PRESWAP,Number=1,Type=Integer,Description=\"Alleles swapped by bcftools norm (1=yes, 0=no)\">\n")
        f.write("#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n")
        
        # Build VCF columns using vectorized pandas operations (much faster than iterrows)
        vcf_df = pd.DataFrame()
        vcf_df['CHROM'] = df[chr_col]
        vcf_df['POS'] = df[pos_col]
        
        # Create variant IDs
        if rsid_col and rsid_col in df.columns:
            vcf_df['ID'] = df[rsid_col].fillna(
                df[chr_col].astype(str) + ':' + df[pos_col].astype(str) + ':' + 
                df[ref_col].astype(str).str.upper() + ':' + df[ea_col].astype(str).str.upper()
            )
        else:
            vcf_df['ID'] = (df[chr_col].astype(str) + ':' + df[pos_col].astype(str) + ':' + 
                           df[ref_col].astype(str).str.upper() + ':' + df[ea_col].astype(str).str.upper())
        
        vcf_df['REF'] = df[ref_col].astype(str).str.upper()
        vcf_df['ALT'] = df[ea_col].astype(str).str.upper()
        vcf_df['QUAL'] = '.'
        vcf_df['FILTER'] = '.'
        
        # Build INFO field (vectorized - avoid empty strings so no strip needed)
        if rsid_col and rsid_col in df.columns:
            # Start with RSID where available, otherwise start with ORIG_A1
            has_rsid = df[rsid_col].notna()
            vcf_df['INFO'] = ('RSID=' + df[rsid_col].astype(str)).where(has_rsid, 'ORIG_A1=' + df[ea_col].astype(str).str.upper())
            # Add ORIG_A1 where we started with RSID
            vcf_df.loc[has_rsid, 'INFO'] = vcf_df.loc[has_rsid, 'INFO'] + ';ORIG_A1=' + df.loc[has_rsid, ea_col].astype(str).str.upper()
            # Add ORIG_A2 to all
            vcf_df['INFO'] = vcf_df['INFO'] + ';ORIG_A2=' + df[ref_col].astype(str).str.upper()
        else:
            # No RSID column - just ORIG_A1 and ORIG_A2
            vcf_df['INFO'] = 'ORIG_A1=' + df[ea_col].astype(str).str.upper() + ';ORIG_A2=' + df[ref_col].astype(str).str.upper()
        
        print(f"Writing {len(vcf_df)} variants...", file=sys.stderr)
        
        # Write all at once (much faster than iterrows)
        vcf_df.to_csv(f, sep='\t', index=False, header=False)
    
    print(f"Wrote {len(df)} variants to VCF", file=sys.stderr)
    
    # Compress with bcftools (creates proper BGZF compression)
    print(f"Compressing with bcftools...", file=sys.stderr)
    subprocess.run(['bcftools', 'view', '-Oz', '-o', vcf_file, temp_vcf], check=True)
    
    print("Note: VCF contig warnings from bcftools can be safely ignored", file=sys.stderr)
    
    # Remove uncompressed file
    os.remove(temp_vcf)
    
    # Normalize VCF against source reference if provided
    if source_fasta:
        print(f"Normalizing REF alleles against source reference...", file=sys.stderr)
        normalized_vcf = vcf_file.replace('.vcf.gz', '.normalized.vcf.gz')
        
        # Use bcftools norm to fix REF alleles
        # -c s: swap REF/ALT when REF doesn't match reference (instead of just warning)
        # -f: reference fasta
        # Note: -c s will auto-fix REF mismatches by swapping alleles
        norm_cmd = ['bcftools', 'norm', '-c', 's', '-f', source_fasta, '-Oz', '-o', normalized_vcf, vcf_file]
        result = subprocess.run(norm_cmd, capture_output=True, text=True)
        
        # Display bcftools norm output (stderr contains statistics)
        if result.stderr:
            print("bcftools norm output:", file=sys.stderr)
            print(result.stderr, file=sys.stderr)
        
        if result.returncode == 0:
            # Detect swaps using bcftools isec (memory efficient)
            print(f"Detecting pre-liftover swaps...", file=sys.stderr)
            
            # Use bcftools annotate to add PRESWAP flag based on comparison
            # We'll use a simple approach: compare ORIG_A1 to REF after norm
            # If ORIG_A1 == REF after norm, then it was swapped (ORIG_A1 was ALT before)
            # Note: we don't actually use bcftools annotate, just stream through normalized VCF
            
            # Now use bcftools query to add PRESWAP based on ORIG_A1 vs REF comparison
            # This is still memory efficient as we stream through the file
            temp_with_preswap = vcf_file.replace('.vcf.gz', '.with_preswap.vcf')
            with open(temp_with_preswap, 'w') as outf:
                # Write header from normalized VCF (keeps PRESWAP definition)
                cmd = ['bcftools', 'view', '-h', normalized_vcf]
                result = subprocess.run(cmd, capture_output=True, text=True, check=True)
                outf.write(result.stdout)
                
                # Stream through variants and add PRESWAP
                cmd = ['bcftools', 'query', '-f', '%CHROM\t%POS\t%ID\t%REF\t%ALT\t%QUAL\t%FILTER\t%INFO/ORIG_A1\t%INFO/ORIG_A2\t%INFO/RSID\n', normalized_vcf]
                proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True)
                
                for line in proc.stdout:
                    if not line.strip():
                        continue
                    parts = line.strip().split('\t')
                    if len(parts) >= 7:
                        chrom, pos, vid, ref, alt, qual, filt = parts[:7]
                        orig_a1 = parts[7] if len(parts) > 7 and parts[7] != '.' else None
                        orig_a2 = parts[8] if len(parts) > 8 and parts[8] != '.' else None
                        rsid = parts[9] if len(parts) > 9 and parts[9] != '.' else None
                        
                        # Determine PRESWAP: if ORIG_A1 (effect allele) is now REF, it was swapped
                        preswap = 1 if (orig_a1 and ref == orig_a1) else 0
                        
                        # Build INFO field (direct concatenation - simpler than list)
                        info = f"RSID={rsid};" if rsid else ""
                        if orig_a1:
                            info += f"ORIG_A1={orig_a1};"
                        if orig_a2:
                            info += f"ORIG_A2={orig_a2};"
                        info += f"PRESWAP={preswap}"
                        
                        outf.write(f"{chrom}\t{pos}\t{vid}\t{ref}\t{alt}\t{qual}\t{filt}\t{info}\n")
                
                proc.wait()
            
            # Compress the final VCF
            final_vcf = vcf_file.replace('.vcf.gz', '.final.vcf.gz')
            subprocess.run(['bcftools', 'view', '-Oz', '-o', final_vcf, temp_with_preswap], check=True)
            os.remove(temp_with_preswap)
            
            # Replace original with final
            os.remove(vcf_file)
            os.remove(normalized_vcf)
            os.rename(final_vcf, vcf_file)
            print(f"Normalized VCF created with PRESWAP annotations", file=sys.stderr)
        else:
            print(f"Warning: normalization had issues, using original VCF", file=sys.stderr)
            if result.stderr:
                print(f"bcftools norm stderr: {result.stderr}", file=sys.stderr)
    
    # Index the VCF file
    print(f"Indexing {vcf_file}...", file=sys.stderr)
    subprocess.run(['bcftools', 'index', '-t', vcf_file], check=True)
    
    return len(df)


def run_liftover(input_vcf, output_vcf, chain_file, source_fasta, target_fasta):
    """
    Run bcftools +liftover
    
    Args:
        input_vcf: Input VCF file
        output_vcf: Output lifted VCF file
        chain_file: Chain file for liftover
        source_fasta: Reference fasta for source build (can be None to skip validation)
        target_fasta: Reference fasta for target build
    """
    print(f"Running bcftools +liftover...", file=sys.stderr)
    
    # Create rejected file path
    rejected_vcf = output_vcf.replace('.vcf', '.rejected.vcf')
    
    cmd = [
        'bcftools', '+liftover',
        '--no-version',
        '-Oz',
        '-o', output_vcf,
        input_vcf,
        '--',
        '-s', source_fasta,
        '-f', target_fasta,
        '-c', chain_file,
        '--reject', rejected_vcf,
        '-O', 'z'
    ]
    
    print(f"Command: {' '.join(cmd)}", file=sys.stderr)
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    # Print stdout and stderr for debugging
    if result.stdout:
        print(f"bcftools stdout: {result.stdout}", file=sys.stderr)
    if result.stderr:
        print(f"bcftools stderr: {result.stderr}", file=sys.stderr)
    
    if result.returncode != 0:
        print(f"Error running bcftools +liftover:", file=sys.stderr)
        raise RuntimeError(f"bcftools +liftover failed with exit code {result.returncode}")
    
    # Check if output file was created
    if not os.path.exists(output_vcf):
        raise RuntimeError(f"bcftools +liftover did not create output file: {output_vcf}")
    
    if os.path.getsize(output_vcf) == 0:
        print(f"Warning: Output VCF file is empty: {output_vcf}", file=sys.stderr)
    
    # Sort the lifted VCF (liftover can produce unsorted output)
    print(f"Sorting {output_vcf}...", file=sys.stderr)
    sorted_vcf = output_vcf + '.sorting.tmp'
    subprocess.run(['bcftools', 'sort', '-Oz', '-o', sorted_vcf, output_vcf], check=True)
    # Atomic rename - overwrites output_vcf safely
    os.rename(sorted_vcf, output_vcf)
    
    # Index the output
    print(f"Indexing {output_vcf}...", file=sys.stderr)
    subprocess.run(['bcftools', 'index', '-t', output_vcf], check=True)
    
    if os.path.exists(rejected_vcf):
        print(f"Indexing {rejected_vcf}...", file=sys.stderr)
        subprocess.run(['bcftools', 'index', '-t', rejected_vcf], check=True)
    
    print("Liftover complete", file=sys.stderr)
    return rejected_vcf


def parse_lifted_vcf(lifted_vcf, rejected_vcf):
    """
    Parse lifted VCF and extract liftover information
    
    Returns:
        dict: Mapping from original variant ID to lifted information
        list: List of rejected variant IDs
    """
    print(f"Parsing lifted VCF...", file=sys.stderr)
    
    lifted_variants = {}
    
    # Parse lifted variants - get SWAP, FLIP, PRESWAP tags, plus original alleles
    cmd = ['bcftools', 'query', '-f', '%ID\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/SWAP\t%INFO/FLIP\t%INFO/PRESWAP\t%INFO/ORIG_A1\t%INFO/ORIG_A2\n', lifted_vcf]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    
    for line in result.stdout.strip().split('\n'):
        if not line:
            continue
        parts = line.split('\t')
        if len(parts) >= 5:
            variant_id = parts[0]
            chrom = parts[1]
            pos = parts[2]
            ref = parts[3]
            alt = parts[4]
            swap = parts[5] if len(parts) > 5 and parts[5] != '.' else '0'
            flip = parts[6] if len(parts) > 6 and parts[6] != '.' else '0'
            preswap = parts[7] if len(parts) > 7 and parts[7] != '.' else '0'
            orig_a1 = parts[8] if len(parts) > 8 and parts[8] != '.' else None
            orig_a2 = parts[9] if len(parts) > 9 and parts[9] != '.' else None
            
            # Determine if effect needs flipping based on PRESWAP and ALLELE_SWAP
            # Flip if exactly one of them is true (XOR logic):
            # - No swaps (both False) = no flip needed
            # - PRESWAP only = norm swapped, need to flip
            # - ALLELE_SWAP only = liftover swapped, need to flip  
            # - Both swaps = they cancel out, no flip needed
            effect_flipped = (preswap == '1') != (swap == '1')  # XOR logic
            
            lifted_variants[variant_id] = {
                'chr': chrom,
                'pos': int(pos),
                'ref': ref,
                'alt': alt,
                'swap': swap == '1',
                'flip': flip == '1',
                'preswap': preswap == '1',
                'effect_flipped': effect_flipped,  # True if effect direction needs flipping
                'status': 'lifted'
            }
    
    print(f"Successfully lifted {len(lifted_variants)} variants", file=sys.stderr)
    
    # Parse rejected variants
    rejected_variants = []
    if os.path.exists(rejected_vcf):
        cmd = ['bcftools', 'query', '-f', '%ID\n', rejected_vcf]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        rejected_variants = [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]
        print(f"Failed to lift {len(rejected_variants)} variants", file=sys.stderr)
    
    return lifted_variants, rejected_variants


def update_sumstats(input_file, output_file, unmatched_file, lifted_info, rejected_ids,
                    chr_col, pos_col, ea_col, ref_col, effect_cols, eaf_cols=None, rsid_col=None):
    """
    Update summary statistics with lifted coordinates and flip effects if needed
    
    Args:
        input_file: Original summary statistics file
        output_file: Output updated summary statistics file
        unmatched_file: Output file for unmatched variants
        lifted_info: Dictionary of lifted variant information
        rejected_ids: List of rejected variant IDs
        chr_col: Chromosome column name
        pos_col: Position column name
        ea_col: Effect allele column name
        ref_col: Reference allele column name
        effect_cols: List of effect columns to flip (e.g., Z, BETA)
        eaf_cols: List of effect allele frequency columns to flip (e.g., EAF, EAF_UKB)
        rsid_col: RSID column name (optional)
    """
    print(f"Updating summary statistics...", file=sys.stderr)
    
    # Force garbage collection before loading large dataset
    gc.collect()
    
    # Read original data with explicit dtypes to save memory
    print(f"Reading {input_file}...", file=sys.stderr)
    df = pd.read_csv(input_file, sep='\t', low_memory=False)
    
    # Create variant IDs for matching (vectorized - much faster than apply)
    if rsid_col and rsid_col in df.columns:
        # Use RSID where available, otherwise chr:pos:ref:alt
        has_rsid = df[rsid_col].notna()
        df['_variant_id'] = df[rsid_col].where(
            has_rsid,
            df[chr_col].astype(str) + ':' + df[pos_col].astype(str) + ':' + 
            df[ref_col].astype(str) + ':' + df[ea_col].astype(str)
        )
    else:
        # Create chr:pos:ref:alt IDs
        df['_variant_id'] = (df[chr_col].astype(str) + ':' + df[pos_col].astype(str) + ':' + 
                            df[ref_col].astype(str) + ':' + df[ea_col].astype(str))
    
    # Add status columns
    df['LIFTOVER_STATUS'] = 'unknown'
    df['PRESWAP'] = False
    df['ALLELE_SWAP'] = False
    df['STRAND_FLIP'] = False
    df['LIFTED_CHR'] = df[chr_col].astype(str)
    # Convert position to numeric, allowing NaN values (will be replaced for lifted variants)
    df['LIFTED_POS'] = pd.to_numeric(df[pos_col], errors='coerce')
    
    # Vectorized update using map operations
    # Create mask for lifted variants
    lifted_mask = df['_variant_id'].isin(lifted_info.keys())
    rejected_mask = df['_variant_id'].isin(rejected_ids)
    
    # Update lifted variants
    df.loc[lifted_mask, 'LIFTED_CHR'] = df.loc[lifted_mask, '_variant_id'].map(lambda x: lifted_info[x]['chr'])
    df.loc[lifted_mask, 'LIFTED_POS'] = df.loc[lifted_mask, '_variant_id'].map(lambda x: lifted_info[x]['pos'])
    df.loc[lifted_mask, 'LIFTOVER_STATUS'] = 'lifted'
    df.loc[lifted_mask, 'PRESWAP'] = df.loc[lifted_mask, '_variant_id'].map(lambda x: lifted_info[x]['preswap'])
    df.loc[lifted_mask, 'ALLELE_SWAP'] = df.loc[lifted_mask, '_variant_id'].map(lambda x: lifted_info[x]['swap'])
    df.loc[lifted_mask, 'STRAND_FLIP'] = df.loc[lifted_mask, '_variant_id'].map(lambda x: lifted_info[x]['flip'])
    
    # Update alleles from lifted REF/ALT (these include strand flips)
    df.loc[lifted_mask, ref_col] = df.loc[lifted_mask, '_variant_id'].map(lambda x: lifted_info[x]['ref'])
    df.loc[lifted_mask, ea_col] = df.loc[lifted_mask, '_variant_id'].map(lambda x: lifted_info[x]['alt'])
    
    # Get effect_flipped status for each variant
    df['_effect_flipped'] = False
    df.loc[lifted_mask, '_effect_flipped'] = df.loc[lifted_mask, '_variant_id'].map(lambda x: lifted_info[x]['effect_flipped'])
    
    # Fix effect and frequency AT ONCE for effect_flipped variants
    # effect_flipped is True when final REF != original A1 (effect allele)
    # This captures ALL swaps (from norm and/or liftover)
    flip_mask = lifted_mask & df['_effect_flipped']
    
    if flip_mask.any():
        # Swap A1 and A2 columns to keep A1 as effect allele
        temp_ea = df.loc[flip_mask, ea_col].copy()
        df.loc[flip_mask, ea_col] = df.loc[flip_mask, ref_col]
        df.loc[flip_mask, ref_col] = temp_ea
        
        # Flip effect sizes (change sign)
        if effect_cols:
            for col in effect_cols:
                if col in df.columns:
                    df.loc[flip_mask, col] = -df.loc[flip_mask, col]
        
        # Flip effect allele frequency (EAF -> 1-EAF)
        if eaf_cols:
            for col in eaf_cols:
                if col in df.columns:
                    df.loc[flip_mask, col] = 1 - df.loc[flip_mask, col]
    
    # Update rejected variants
    df.loc[rejected_mask, 'LIFTOVER_STATUS'] = 'rejected'
    
    # Calculate summary statistics
    matched_count = lifted_mask.sum()
    strand_flipped_count = (df['STRAND_FLIP'] == True).sum()
    flipped_count = flip_mask.sum()
    
    # Drop temporary column
    df = df.drop('_effect_flipped', axis=1)
    
    # Update chromosome and position with lifted values
    df[chr_col] = df['LIFTED_CHR']
    df[pos_col] = df['LIFTED_POS']
    
    # Calculate summary statistics before splitting
    matched_count = lifted_mask.sum()
    strand_flipped_count = (df['STRAND_FLIP'] == True).sum()
    flipped_count = flip_mask.sum()
    total_count = len(df)
    
    # Write outputs in chunks to reduce memory usage
    print(f"Writing lifted variants to {output_file}...", file=sys.stderr)
    temp_output = output_file + '.tmp'
    # Determine compression based on output filename
    compression = 'gzip' if output_file.endswith('.gz') else None
    first_chunk = True
    for chunk in [df[df['LIFTOVER_STATUS'] == 'lifted']]:
        chunk_clean = chunk.drop(['_variant_id', 'LIFTED_CHR', 'LIFTED_POS'], axis=1)
        chunk_clean.to_csv(temp_output, sep='\t', index=False, mode='w' if first_chunk else 'a', header=first_chunk, compression=compression)
        first_chunk = False
        del chunk_clean
        gc.collect()
    # Only rename to final name after successful write
    if os.path.exists(output_file):
        os.remove(output_file)
    os.rename(temp_output, output_file)
    
    print(f"Writing unmatched variants to {unmatched_file}...", file=sys.stderr)
    temp_unmatched = unmatched_file + '.tmp'
    # Determine compression based on output filename
    compression_unmatched = 'gzip' if unmatched_file.endswith('.gz') else None
    first_chunk = True
    for chunk in [df[df['LIFTOVER_STATUS'] != 'lifted']]:
        chunk_clean = chunk.drop(['_variant_id', 'LIFTED_CHR', 'LIFTED_POS'], axis=1)
        chunk_clean.to_csv(temp_unmatched, sep='\t', index=False, mode='w' if first_chunk else 'a', header=first_chunk, compression=compression_unmatched)
        first_chunk = False
        del chunk_clean
        gc.collect()
    # Only rename to final name after successful write
    if os.path.exists(unmatched_file):
        os.remove(unmatched_file)
    os.rename(temp_unmatched, unmatched_file)
    
    print(f"\nSummary:", file=sys.stderr)
    print(f"  Total variants: {total_count}", file=sys.stderr)
    print(f"  Successfully lifted: {matched_count}", file=sys.stderr)
    print(f"  Strand flipped: {strand_flipped_count}", file=sys.stderr)
    print(f"  Allele swapped: {flipped_count}", file=sys.stderr)
    print(f"  Failed to lift: {total_count - matched_count}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(
        description='Liftover summary statistics between genome builds using bcftools',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Example:
  %(prog)s \\
    --input sumstats.txt.gz \\
    --output sumstats.hg38.txt.gz \\
    --unmatched sumstats.unmatched.txt.gz \\
    --chr-col CHR \\
    --pos-col POS \\
    --ea-col A1 \\
    --ref-col A2 \\
    --effect-col Z \\
    --eaf-col EAF_UKB \\
    --rsid-col RSID \\
    --source-fasta hg19.fa.gz \\
    --target-fasta hg38.fa.gz \\
    --chain-file hg19ToHg38.over.chain.gz
        '''
    )
    
    parser.add_argument('-i', '--input', required=True,
                        help='Input summary statistics file (txt or txt.gz)')
    parser.add_argument('-o', '--output', required=True,
                        help='Output lifted summary statistics file')
    parser.add_argument('-u', '--unmatched', required=True,
                        help='Output file for unmatched variants')
    
    parser.add_argument('--chr-col', required=True,
                        help='Chromosome column name')
    parser.add_argument('--pos-col', required=True,
                        help='Position column name')
    parser.add_argument('--ea-col', required=True,
                        help='Effect allele column name')
    parser.add_argument('--ref-col', required=True,
                        help='Reference allele column name')
    parser.add_argument('--effect-col', action='append',
                        help='Effect column name(s) to flip (e.g., Z, BETA). Can specify multiple times.')
    parser.add_argument('--eaf-col', action='append',
                        help='Effect allele frequency column name(s) to flip when alleles swap (e.g., EAF, EAF_UKB). Can specify multiple times.')
    parser.add_argument('--rsid-col',
                        help='RSID column name (optional)')
    
    parser.add_argument('--source-fasta', required=True,
                        help='Source reference fasta file (used to validate/fix REF alleles)')
    parser.add_argument('--target-fasta', required=True,
                        help='Target reference fasta file')
    parser.add_argument('--chain-file', required=True,
                        help='Chain file for liftover')
    
    parser.add_argument('--add-chr-prefix', action='store_true',
                        help='Add "chr" prefix to chromosome names (use if source fasta has chr1, chr2, etc.)')
    
    parser.add_argument('--temp-dir', 
                        help='Temporary directory for intermediate files')
    parser.add_argument('--keep-temp', action='store_true',
                        help='Keep temporary files')
    
    args = parser.parse_args()
    
    # Create temp directory
    if args.temp_dir:
        os.makedirs(args.temp_dir, exist_ok=True)
        temp_dir = args.temp_dir
    else:
        temp_dir = tempfile.mkdtemp(prefix='liftover_sumstats_')
    
    print(f"Using temporary directory: {temp_dir}", file=sys.stderr)
    
    try:
        # Step 1: Convert to VCF
        input_vcf = os.path.join(temp_dir, 'input.vcf.gz')
        if os.path.exists(input_vcf) and os.path.exists(input_vcf + '.tbi'):
            print(f"Found existing VCF: {input_vcf}, skipping conversion...", file=sys.stderr)
        else:
            sumstats_to_vcf(
                args.input, input_vcf,
                args.chr_col, args.pos_col, args.ea_col, args.ref_col,
                args.rsid_col, args.add_chr_prefix, args.source_fasta
            )
        
        # Step 2: Run liftover
        lifted_vcf = os.path.join(temp_dir, 'lifted.vcf.gz')
        rejected_vcf_path = os.path.join(temp_dir, 'lifted.rejected.vcf.gz')
        if os.path.exists(lifted_vcf) and os.path.exists(lifted_vcf + '.tbi'):
            print(f"Found existing lifted VCF: {lifted_vcf}, skipping liftover...", file=sys.stderr)
            rejected_vcf = rejected_vcf_path
        else:
            rejected_vcf = run_liftover(input_vcf, lifted_vcf, args.chain_file, args.source_fasta, args.target_fasta)
        
        # Step 3: Parse lifted VCF
        lifted_info, rejected_ids = parse_lifted_vcf(lifted_vcf, rejected_vcf)
        
        # Clear memory before final step
        gc.collect()
        
        # Step 4: Update summary statistics
        update_sumstats(
            args.input, args.output, args.unmatched,
            lifted_info, rejected_ids,
            args.chr_col, args.pos_col, args.ea_col, args.ref_col,
            args.effect_col or [],
            args.eaf_col or [],
            args.rsid_col
        )
        
        print("\nLiftover complete!", file=sys.stderr)
        
    finally:
        # Clean up temp directory
        if not args.keep_temp and not args.temp_dir:
            import shutil
            shutil.rmtree(temp_dir)
            print(f"Cleaned up temporary directory: {temp_dir}", file=sys.stderr)


if __name__ == '__main__':
    main()
