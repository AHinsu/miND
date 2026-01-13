# Quick Reference Guide - miND Nextflow Pipeline

## Quick Start

```bash
# Install Nextflow
curl -s https://get.nextflow.io | bash

# Run pipeline
./run_nextflow.sh -i SampleContrastSheet.xlsx

# Resume a failed run
./run_nextflow.sh -i SampleContrastSheet.xlsx -resume
```

## Common Commands

### Basic Usage
```bash
# Run with default settings
./run_nextflow.sh -i input.xlsx

# Specify output directory
./run_nextflow.sh -i input.xlsx -o my_analysis

# Keep work directory for debugging
./run_nextflow.sh -i input.xlsx -k

# Resume previous run
./run_nextflow.sh -i input.xlsx -resume
```

### Advanced Usage
```bash
# Use specific profile
./run_nextflow.sh -i input.xlsx -profile conda

# Direct Nextflow execution
nextflow run main.nf --sampleSheet input.xlsx

# With custom parameters
nextflow run main.nf \
  --sampleSheet input.xlsx \
  --threads_high 12 \
  --threads_medium 8 \
  --threads_low 4
```

## Command-Line Options

| Option | Description | Example |
|--------|-------------|---------|
| `-i, --input` | Sample sheet path | `-i data.xlsx` |
| `-o, --output` | Output subfolder | `-o analysis1` |
| `-k, --keeptmp` | Keep work directory | `-k` |
| `-profile` | Execution profile | `-profile conda` |
| `-resume` | Resume failed run | `-resume` |
| `--help` | Show help | `--help` |
| `--version` | Show version | `--version` |

## Configuration Parameters

### Resource Allocation
```bash
nextflow run main.nf \
  --sampleSheet input.xlsx \
  --threads_high 12 \
  --threads_medium 8 \
  --threads_low 4
```

### Reference Versions
```bash
nextflow run main.nf \
  --sampleSheet input.xlsx \
  --miRBaseVersion "22.1" \
  --rnacentralVersion "19.0"
```

## Execution Profiles

### Standard (Default)
```bash
./run_nextflow.sh -i input.xlsx -profile standard
```
- Local execution
- No containerization

### Conda
```bash
./run_nextflow.sh -i input.xlsx -profile conda
```
- Uses conda environments
- Automatic dependency management

### Docker
```bash
./run_nextflow.sh -i input.xlsx -profile docker
```
- Uses Docker containers
- Better reproducibility

### Singularity
```bash
./run_nextflow.sh -i input.xlsx -profile singularity
```
- Uses Singularity containers
- HPC-friendly

## File Locations

### Input
```
/path/to/samples/
├── sample1.fastq.gz
├── sample2.fastq.gz
└── SampleContrastSheet.xlsx
```

### Output
```
output/[analysis_name]/
├── fastqc_raw/
├── fastqc_trimmed/
├── mapping_bowtie_*/
├── analysis/
│   └── report.html
└── [DATE]_[PROJECTID]_MINDreport.zip
```

## Troubleshooting

### Pipeline Fails
```bash
# Check logs
cat .nextflow.log

# Resume from last successful step
./run_nextflow.sh -i input.xlsx -resume

# Clean and restart
rm -rf work .nextflow*
./run_nextflow.sh -i input.xlsx
```

### Out of Memory
```bash
# Increase Java heap
export NXF_OPTS='-Xms1g -Xmx4g'
./run_nextflow.sh -i input.xlsx
```

### Conda Issues
```bash
# Use mamba instead
nextflow run main.nf \
  --sampleSheet input.xlsx \
  -profile conda \
  -with-conda-mamba
```

## Monitoring

### During Execution
```bash
# Watch log file
tail -f .nextflow.log

# Monitor specific process
grep "CUTADAPT" .nextflow.log
```

### After Execution
```bash
# View report
firefox pipeline_report.html

# View timeline
firefox timeline.html

# Check resource usage
cat trace.txt
```

## Common Workflows

### First-Time Setup
```bash
# 1. Install Nextflow
curl -s https://get.nextflow.io | bash
sudo mv nextflow /usr/local/bin/

# 2. Install conda (if not present)
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh

# 3. Validate installation
./validate_installation.sh

# 4. Run test
./run_nextflow.sh -i examples/E-MTAB-6885_SampleContrastSheet.xlsx
```

### Regular Usage
```bash
# 1. Prepare sample sheet
cp SampleContrastSheet.example.xlsx my_samples.xlsx
# Edit my_samples.xlsx with your data

# 2. Run pipeline
./run_nextflow.sh -i my_samples.xlsx -o $(date +%Y%m%d)

# 3. Check results
firefox output/*/analysis/report.html
```

### Debugging Failed Run
```bash
# 1. Check what failed
cat .nextflow.log | grep ERROR

# 2. Resume from failure point
./run_nextflow.sh -i input.xlsx -resume

# 3. If still failing, clean and retry
rm -rf work .nextflow*
./run_nextflow.sh -i input.xlsx
```

## Performance Tips

### For Large Datasets
```bash
# Use more threads
nextflow run main.nf \
  --sampleSheet input.xlsx \
  --threads_high 16 \
  --threads_medium 12 \
  --threads_low 8

# Use work directory on fast storage
export NXF_WORK=/fast/scratch/work
./run_nextflow.sh -i input.xlsx
```

### For HPC Systems
```bash
# Use SLURM executor (edit nextflow.config first)
nextflow run main.nf \
  --sampleSheet input.xlsx \
  -profile slurm,singularity
```

## Sample Sheet Tips

### Required Sheets
1. **Project Details**
   - Project ID
   - Species
   - Adapter type
   - Read quality settings

2. **Sample Group Matrix**
   - Sample names
   - Filenames
   - Group assignments
   - Contrasts

### Common Issues
- ✗ Wrong file extensions in Filename column
- ✗ Missing samples in Sample Group Matrix
- ✗ Incorrect species name
- ✓ Use example file as template

## Quick Checks

### Before Running
```bash
# Check Nextflow version
nextflow -version

# Validate pipeline syntax
nextflow config main.nf

# Check sample sheet
python3 scripts/parse_excel_config.py input.xlsx
```

### After Running
```bash
# Check output files
ls -lh output/*/analysis/report.html

# Verify all samples processed
grep "Completed" .nextflow.log | wc -l

# Check for errors
grep -i error .nextflow.log
```

## Environment Variables

```bash
# Nextflow work directory
export NXF_WORK=/path/to/work

# Java heap size
export NXF_OPTS='-Xms1g -Xmx4g'

# Conda cache directory
export NXF_CONDA_CACHEDIR=/path/to/conda/cache

# Temp directory
export NXF_TEMP=/path/to/tmp
```

## Getting Help

```bash
# Show pipeline help
./run_nextflow.sh --help

# Show Nextflow help
nextflow help run

# Validate installation
./validate_installation.sh

# Check documentation
cat README.md
cat MIGRATION.md
cat PROCESS_MAPPING.md
```

## Resources

- **Main Docs**: README.md
- **Nextflow Docs**: https://www.nextflow.io/docs/latest/
- **nf-core**: https://nf-co.re/
- **Issues**: https://github.com/AHinsu/miND/issues

---

**Version**: 2.0
**Last Updated**: January 2024
