#!/usr/bin/env python3
"""
Parse Excel sample sheet for miND pipeline
Converts Excel configuration to JSON for Nextflow
"""

import sys
import json
import pandas as pd
import pathlib

def parse_excel_config(excel_file):
    """Parse the Excel sample sheet and return configuration as JSON"""
    
    config = {}
    samples = []
    
    try:
        # Read Project Details sheet
        xls_config = pd.read_excel(
            excel_file, 
            header=None, 
            index_col=0, 
            sheet_name='Project Details',
            converters={0: str, 1: str},
            usecols="A,B"
        )
        
        # Convert to dictionary
        project_details = {}
        for index, row in xls_config.iterrows():
            if pd.notna(row[1]):
                project_details[index] = row[1]
        
        # Read Sample Group Matrix sheet
        samples_df = pd.read_excel(
            excel_file,
            index_col=0,
            sheet_name='Sample Group Matrix',
            converters={0: str, 1: str, 2: str},
            usecols="A:G"
        )
        
        # Extract sample filenames
        for index, row in samples_df.iterrows():
            filename = row.get("Filename")
            if pd.notna(filename) and isinstance(filename, str):
                # Remove file extensions
                filename = filename.replace(".fastq.gz", "")
                filename = filename.replace(".fq.gz", "")
                filename = filename.replace(".fastq", "")
                filename = filename.replace(".fq", "")
                filename = filename.replace(".bam", "")
                samples.append(filename)
        
        # Build configuration
        config['projectDetails'] = project_details
        config['samples'] = samples
        
        # Parse key configuration values
        if 'Project ID' in project_details:
            config['projectID'] = project_details['Project ID']
        
        if 'Species' in project_details:
            config['species'] = project_details['Species']
        
        if 'Differential expression analysis' in project_details:
            config['deAnalysis'] = 1 if project_details['Differential expression analysis'] == 'Yes' else 0
        
        if 'Spikein analysis' in project_details:
            if project_details['Spikein analysis'] != 'No':
                config['includeSpikeIns'] = 1
                config['spikeInVersion'] = project_details['Spikein analysis']
            else:
                config['includeSpikeIns'] = 0
        
        if 'Adapter' in project_details:
            adapter = project_details['Adapter']
            if adapter == "Illumina Universal Adapter":
                config['adapter'] = "-a IlluminaUniversal=AGATCGGAAGAG"
                config['adapterName'] = adapter
            elif adapter == "Illumina Small RNA 3'":
                config['adapter'] = "-a IlluminaSmallRNA3p=TGGAATTCTC"
                config['adapterName'] = adapter
            elif adapter == "RealSeq":
                config['adapter'] = "-a Realseq3P=TGGAATTCTC -u1"
                config['adapterName'] = adapter
            else:
                config['adapter'] = project_details.get('Custom adapter (cutadapt cfg)', '')
                config['adapterName'] = ''
        
        if 'Minimum read length' in project_details:
            config['readMinLength'] = str(project_details['Minimum read length'])
        
        if 'Reads quality cutoff' in project_details:
            config['qualityCutoff'] = str(project_details['Reads quality cutoff'])
        
        if 'Significance level' in project_details:
            config['alpha'] = str(project_details['Significance level'])
        
        if 'Report spikein sequences' in project_details:
            config['includeSequence'] = 1 if project_details['Report spikein sequences'] == 'Yes' else 0
        
    except Exception as e:
        print(json.dumps({"error": str(e)}), file=sys.stderr)
        sys.exit(1)
    
    return config

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: parse_excel_config.py <excel_file>", file=sys.stderr)
        sys.exit(1)
    
    excel_file = sys.argv[1]
    
    if not pathlib.Path(excel_file).exists():
        print(f"Error: File not found: {excel_file}", file=sys.stderr)
        sys.exit(1)
    
    config = parse_excel_config(excel_file)
    print(json.dumps(config, indent=2))
