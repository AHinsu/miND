# miND - miRNA NGS Data Pipeline

miND is a comprehensive Nextflow pipeline for miRNA NGS data analysis, following nf-core best practices.

## Overview

The miND pipeline processes small RNA sequencing data through the following stages:

1. **Quality Control** - FastQC analysis of raw and trimmed reads
2. **Adapter Trimming** - Removal of adapter sequences using cutadapt
3. **Read Collapsing** - Deduplication of identical reads
4. **Mapping** - Sequential mapping to:
   - Spike-in sequences (optional)
   - Reference genome
   - miRNA sequences (miRBase)
   - Other non-coding RNAs (RNAcentral)
   - cDNA sequences
5. **Quantification** - Expression analysis using miRDeep2
6. **Differential Expression** - Statistical analysis of expression differences (optional)
7. **Reporting** - Comprehensive HTML report with MultiQC integration

## Requirements

### Software Dependencies

- **Nextflow** (≥21.04.0)
- **Conda** or **Mamba** (for dependency management)
- **Python** (≥3.9) with pandas and xlrd
- **R** (≥4.0) with required packages

### Reference Data

The pipeline requires reference data for:
- Genome assemblies (stored in `repository/data/`)
- miRBase hairpin and mature sequences
- RNAcentral species-specific databases
- Spike-in sequences (optional)

## Installation

### Clone the Repository

```bash
git clone https://github.com/AHinsu/miND.git
cd miND
```

### Install Nextflow

#### Option 1: Using Conda
```bash
conda install -c bioconda nextflow
```

#### Option 2: Direct Installation
```bash
curl -s https://get.nextflow.io | bash
sudo mv nextflow /usr/local/bin/
```

#### Option 3: Using the Run Script
The `run_nextflow.sh` script will automatically install Nextflow if not found.

## Usage

### Basic Usage

```bash
./run_nextflow.sh -i SampleContrastSheet.xlsx
```

#### Advanced Usage

```bash
./run_nextflow.sh -i SampleContrastSheet.xlsx -o my_analysis -profile standard,conda
```

#### Command Line Options

- `-i, --input` - Path to SampleContrastSheet.xlsx file (required)
- `-o, --output` - Output subfolder name (optional)
- `-k, --keeptmp` - Keep temporary files and work directory
- `-profile` - Nextflow profile (default: standard,conda)
- `-resume` - Resume a previous run
- `--help` - Display help message
- `--version` - Display version information

#### Using Nextflow Directly

```bash
# Basic usage
nextflow run main.nf \
  --sampleSheet SampleContrastSheet.xlsx \
  -profile conda

# Or use --input as an alias for --sampleSheet
nextflow run main.nf \
  --input SampleContrastSheet.xlsx \
  --outputSubfolder my_analysis \
  -profile conda

# With custom resources
nextflow run main.nf \
  --sampleSheet SampleContrastSheet.xlsx \
  --threads_high 12 \
  --threads_medium 8 \
  --threads_low 4 \
  -profile conda
```

## Configuration

### Sample Sheet Format

The pipeline requires an Excel file (`.xlsx`) with two sheets:

#### 1. Project Details Sheet

Configure analysis parameters:
- Project ID
- Species
- Adapter type
- Read quality cutoff
- Minimum read length
- Differential expression analysis (Yes/No)
- Spike-in analysis (Yes/No)
- Significance level (alpha)

#### 2. Sample Group Matrix Sheet

List samples with columns:
- Sample ID
- Filename (without path)
- Group assignments
- Contrasts for differential expression

See `SampleContrastSheet.example.xlsx` for a template.

### Pipeline Configuration

#### Nextflow Configuration (`nextflow.config`)

Key parameters you can override:

```bash
nextflow run main.nf \
  --sampleSheet input.xlsx \
  --threads_high 8 \
  --threads_medium 4 \
  --threads_low 2 \
  --miRBaseVersion "22.1" \
  --rnacentralVersion "19.0"
```



## Supported Species

The pipeline includes pre-configured support for:

- Homo sapiens (hsa)
- Mus musculus (mmu)
- Rattus norvegicus (rno)
- Sus scrofa (ssc)
- Bos taurus (bta)
- Canis lupus familiaris (cfa)
- Felis catus (fca)
- Equus caballus (eca)
- Oryctolagus cuniculus (ocu)
- Danio rerio (dre)
- Drosophila melanogaster (dme)
- Caenorhabditis elegans (cel)
- And more...

## Output Structure

```
output/
└── [analysis_name]/
    ├── fastqc_raw/              # Raw read QC
    ├── fastqc_trimmed/          # Trimmed read QC
    ├── fastq_trimmed/           # Trimmed FASTQ files
    ├── mapping_bowtie_*/        # Bowtie mapping results
    ├── mapping_mirdeep2_miRNA/  # miRDeep2 quantification
    ├── analysis_sampleMappingStats/  # Per-sample statistics
    ├── analysis_quantifySampleMappings/  # Combined quantification
    ├── analysis_differentialExpression/  # DE analysis (if enabled)
    ├── multiqc/                 # MultiQC report
    ├── analysis/
    │   └── report.html          # Main HTML report
    └── [DATE]_[PROJECTID]_MINDreport.zip  # Final results package
```

## Why Nextflow?

This pipeline uses Nextflow for workflow management and follows nf-core best practices, offering:

- **Better portability** - Easier containerization with Docker/Singularity
- **Cloud support** - Native support for cloud execution (AWS, Google Cloud, Azure)
- **Reactive dataflow** - More flexible channel-based data flow
- **Resume capability** - Better handling of pipeline resumption with `-resume`
- **Modern syntax** - DSL2 provides cleaner, more modular code
- **Best practices** - Follows nf-core community standards

## Examples

### Example 1: Basic Analysis

```bash
./run_nextflow.sh -i examples/E-MTAB-6885_SampleContrastSheet.xlsx
```

### Example 2: Custom Output Location

```bash
./run_nextflow.sh \
  -i SampleContrastSheet.xlsx \
  -o experiment_2024_01
```

### Example 3: Resume Failed Run

```bash
./run_nextflow.sh \
  -i SampleContrastSheet.xlsx \
  -resume
```

### Example 4: Using Docker

```bash
nextflow run main.nf \
  --sampleSheet SampleContrastSheet.xlsx \
  -profile docker
```

## Troubleshooting

### Nextflow Issues

**Issue**: Out of memory errors
```bash
# Increase Java heap size
export NXF_OPTS='-Xms1g -Xmx4g'
```

**Issue**: Permission denied errors
```bash
# Ensure scripts are executable
chmod +x run_nextflow.sh scripts/*.py
```

**Issue**: Conda environment creation fails
```bash
# Use mamba instead
nextflow run main.nf -profile conda --conda-frontend mamba
```

## Performance Tuning

### Thread Allocation

Adjust thread counts in `nextflow.config`:

```groovy
params {
    threads_high = 12    // For intensive tasks (trimming, mapping)
    threads_medium = 8   // For moderate tasks
    threads_low = 4      // For light tasks
}
```

### Memory Requirements

- Minimum: 16 GB RAM
- Recommended: 32 GB RAM
- Large datasets: 64+ GB RAM

## Citation

If you use miND in your research, please cite:

```
Diendorfer AB, et al. (2021)
miND - A miRNA NGS Data Analysis Pipeline
TAmiRNA GmbH
```

## License

This project is licensed under the GNU Affero General Public License v3.0 or later.
See LICENSE file for details.

## Copyright

Copyright (C) 2021 TAmiRNA GmbH

## Authors

- **Andreas B. Diendorfer** - Original development
- **GitHub Copilot** - Nextflow conversion

## Support

For issues and questions:
- GitHub Issues: https://github.com/AHinsu/miND/issues
- Website: https://www.tamirna.com/mind

## Changelog

### Version 2.0 (Current - Nextflow)
- Nextflow-based pipeline implementation
- Added DSL2 syntax for better modularity
- Improved error handling and resume capability
- Added support for Docker and Singularity containers
- Enhanced reporting with timeline and trace
- Removed legacy Snakemake support
