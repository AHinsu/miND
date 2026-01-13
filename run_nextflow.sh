#!/bin/bash
# Nextflow run script for miND pipeline
# Copyright (C) 2021 TAmiRNA GmbH
# Adapted from Snakemake version to Nextflow

source ~/.bashrc

MINDVERSION="2.0-nextflow"

# read command line arguments
POSITIONAL=()
count=0
while [[ $# -gt 0 ]]
do
  key="$1"
  case $key in
      -i|--input)
      (( count++ ))
      INPUT="$2"
      shift
      shift
      ;;
      -)
      (( count++ ))
      STDIN=YES
      shift
      ;;
      -o|--output)
      (( count++ ))
      OUTPUT="$2"
      shift
      shift
      ;;
      -k|--keeptmp)
      (( count++ ))
      KEEPTMP=YES
      shift
      ;;
      --help)
      (( count++ ))
      HELP=YES
      shift
      ;;
      --version)
      (( count++ ))
      VERSION=YES
      shift
      ;;
      -profile)
      (( count++ ))
      PROFILE="$2"
      shift
      shift
      ;;
      -resume)
      (( count++ ))
      RESUME=YES
      shift
      ;;
      *)    # unknown option
      (( count++ ))
      POSITIONAL+=("$1") # save it in an array for later
      shift
      ;;
  esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

# set to read from stdin if no arguments are passed
if (( ${count} == 0 )); then
  STDIN=YES
fi

if [[ "${STDIN}" == "YES" ]] || [[ "${INPUT}" == "-" ]]; then
  INPUT=$(</dev/stdin)
fi

if [[ -n $1 ]]; then
  INPUT=$1
fi
if [[ -n $2 ]]; then
  OUTPUT=$2
fi

if [[ "${HELP}" == "YES" ]]; then
  echo "Usage: ./run_nextflow.sh [OPTION]... [FILE]..."
  echo "Run miND pipeline (Nextflow version) based on configuration in the -i FILE and generate output"
  echo ""
  echo "With no FILE, or when FILE is -, read configuration file path from standard input."
  echo ""
  echo "  -i, --input       Path to configuration SampleContrastSheet.xlsx file"
  echo "  -o, --output      Output subfolder name"
  echo "  -k, --keeptmp     Keep temporary output files (work directory)"
  echo "  -profile          Nextflow profile to use (default: standard,conda)"
  echo "  -resume           Resume a previous run"
  echo "      --help        display this help and exit"
  echo "      --version     display version information and exit"
  echo ""
  echo "miND pipeline online help: <https://www.tamirna.com/mind>"
  exit 0
fi

if [[ "${VERSION}" == "YES" ]]; then
  echo "miND ${MINDVERSION}"
  echo "Copyright (C) 2021 TAmiRNA GmbH"
  echo "License GNU AGPLv3: GNU Affero General Public License v3.0 or later <https://www.gnu.org/licenses/agpl-3.0.html>."
  echo "This is free software: you are free to change and redistribute it."
  echo "There is NO WARRANTY, to the extent permitted by law."
  echo ""
  echo "Written and developed by Andreas B. Diendorfer"
  echo "Converted to Nextflow by GitHub Copilot"
  exit 0
fi

# Check if input file is provided
if [[ -z "${INPUT}" ]]; then
  echo "Error: No input sample sheet provided"
  echo "Use --help for usage information"
  exit 1
fi

# Check if Nextflow is installed
if ! command -v nextflow &> /dev/null; then
  echo "Nextflow is not installed. Installing Nextflow..."
  
  # Check if conda is available
  if [[ $(type -P "conda") ]]; then
    echo "Installing Nextflow via conda..."
    conda install -y -c bioconda nextflow
  else
    # Install Nextflow directly
    echo "Installing Nextflow directly..."
    curl -s https://get.nextflow.io | bash
    chmod +x nextflow
    sudo mv nextflow /usr/local/bin/
  fi
  
  # Verify installation
  if ! command -v nextflow &> /dev/null; then
    echo "Error: Failed to install Nextflow"
    exit 1
  fi
fi

echo "Nextflow version: $(nextflow -version)"

# Set default profile if not specified
if [[ -z "${PROFILE}" ]]; then
  PROFILE="standard,conda"
fi

# Build Nextflow command
NF_CMD="nextflow run main.nf"
NF_CMD="${NF_CMD} --sampleSheet '${INPUT}'"

if [[ -n "${OUTPUT}" ]]; then
  NF_CMD="${NF_CMD} --outputSubfolder '${OUTPUT}'"
fi

NF_CMD="${NF_CMD} -profile ${PROFILE}"

if [[ "${RESUME}" == "YES" ]]; then
  NF_CMD="${NF_CMD} -resume"
fi

# Add work directory retention option
if [[ "${KEEPTMP}" != "YES" ]]; then
  NF_CMD="${NF_CMD} -with-report"
  NF_CMD="${NF_CMD} -with-timeline"
  NF_CMD="${NF_CMD} -with-dag dag.svg"
fi

echo ""
echo "####################################################"
echo "#          miND - miRNA NGS data pipeline          #"
echo "#         Copyright (C) 2021 TAmiRNA GmbH          #"
echo "#  Written and developed by Andreas B. Diendorfer  #"
echo "#            Nextflow version 2.0                  #"
echo "####################################################"
echo ""
echo "Running pipeline with command:"
echo "${NF_CMD}"
echo ""

# Execute Nextflow
eval ${NF_CMD}

EXIT_CODE=$?

# Cleanup work directory if requested
if [[ "${KEEPTMP}" != "YES" ]] && [[ ${EXIT_CODE} -eq 0 ]]; then
  echo ""
  echo "Cleaning up work directory..."
  rm -rf work/
fi

echo ""
if [[ ${EXIT_CODE} -eq 0 ]]; then
  echo "Pipeline completed successfully!"
else
  echo "Pipeline failed with exit code ${EXIT_CODE}"
fi

exit ${EXIT_CODE}
