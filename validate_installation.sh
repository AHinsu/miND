#!/bin/bash
# Quick validation script for Nextflow installation
# Tests syntax and basic functionality

set -e

echo "======================================================"
echo "miND Nextflow Pipeline - Validation Script"
echo "======================================================"
echo ""

# Check Nextflow installation
echo "1. Checking Nextflow installation..."
if command -v nextflow &> /dev/null; then
    NEXTFLOW_VERSION=$(nextflow -version 2>&1 | grep "nextflow version" | awk '{print $3}')
    echo "   ✓ Nextflow found: version $NEXTFLOW_VERSION"
else
    echo "   ✗ Nextflow not found!"
    echo "   Install with: conda install -c bioconda nextflow"
    echo "   Or: curl -s https://get.nextflow.io | bash"
    exit 1
fi

# Check Nextflow version
echo ""
echo "2. Checking Nextflow version compatibility..."
REQUIRED_VERSION="21.04.0"
if [[ "$NEXTFLOW_VERSION" > "$REQUIRED_VERSION" ]] || [[ "$NEXTFLOW_VERSION" == "$REQUIRED_VERSION" ]]; then
    echo "   ✓ Version $NEXTFLOW_VERSION is compatible (≥ $REQUIRED_VERSION)"
else
    echo "   ⚠ Version $NEXTFLOW_VERSION may not be compatible"
    echo "   Recommended: ≥ $REQUIRED_VERSION"
fi

# Check main.nf exists
echo ""
echo "3. Checking pipeline files..."
if [ -f "main.nf" ]; then
    echo "   ✓ main.nf found"
else
    echo "   ✗ main.nf not found!"
    exit 1
fi

if [ -f "nextflow.config" ]; then
    echo "   ✓ nextflow.config found"
else
    echo "   ✗ nextflow.config not found!"
    exit 1
fi

if [ -f "run_nextflow.sh" ]; then
    echo "   ✓ run_nextflow.sh found"
else
    echo "   ✗ run_nextflow.sh not found!"
    exit 1
fi

# Check scripts directory
echo ""
echo "4. Checking required scripts..."
if [ -f "scripts/parse_excel_config.py" ]; then
    echo "   ✓ parse_excel_config.py found"
else
    echo "   ✗ parse_excel_config.py not found!"
    exit 1
fi

# Validate Nextflow syntax
echo ""
echo "5. Validating Nextflow pipeline syntax..."
if nextflow config main.nf > /dev/null 2>&1; then
    echo "   ✓ Pipeline syntax is valid"
else
    echo "   ✗ Pipeline syntax validation failed!"
    echo "   Run: nextflow config main.nf"
    exit 1
fi

# Check Python dependencies
echo ""
echo "6. Checking Python dependencies..."
python3 -c "import pandas" 2>/dev/null && echo "   ✓ pandas installed" || echo "   ⚠ pandas not installed (required for Excel parsing)"
python3 -c "import xlrd" 2>/dev/null && echo "   ✓ xlrd installed" || echo "   ⚠ xlrd not installed (required for Excel parsing)"

# Check conda
echo ""
echo "7. Checking conda installation..."
if command -v conda &> /dev/null; then
    CONDA_VERSION=$(conda --version | awk '{print $2}')
    echo "   ✓ Conda found: version $CONDA_VERSION"
else
    echo "   ⚠ Conda not found (required for managing environments)"
fi

# Check example files
echo ""
echo "8. Checking example files..."
if [ -f "SampleContrastSheet.example.xlsx" ]; then
    echo "   ✓ Example sample sheet found"
else
    echo "   ⚠ Example sample sheet not found"
fi

# Check reference data directory
echo ""
echo "9. Checking reference data structure..."
if [ -d "repository/data" ]; then
    echo "   ✓ Repository data directory exists"
    
    # Count subdirectories
    GENOME_COUNT=$(find repository/data -maxdepth 1 -type d | wc -l)
    echo "   ℹ Found $((GENOME_COUNT - 1)) genome directories"
else
    echo "   ⚠ Repository data directory not found"
    echo "   You'll need to set up reference data before running analyses"
fi

# Check environment files
echo ""
echo "10. Checking conda environment files..."
ENV_COUNT=0
for ENV_FILE in envs/*.yml; do
    if [ -f "$ENV_FILE" ]; then
        ((ENV_COUNT++))
    fi
done
echo "   ✓ Found $ENV_COUNT conda environment files"

# Summary
echo ""
echo "======================================================"
echo "Validation Summary"
echo "======================================================"
echo ""
echo "✓ = Passed"
echo "⚠ = Warning (may need attention)"
echo "✗ = Failed (must be fixed)"
echo ""

# Check if validation passed
if [ $? -eq 0 ]; then
    echo "Overall status: PASSED ✓"
    echo ""
    echo "Your installation appears to be ready!"
    echo ""
    echo "Next steps:"
    echo "1. Set up reference data in repository/data/"
    echo "2. Prepare your sample sheet (see SampleContrastSheet.example.xlsx)"
    echo "3. Run: ./run_nextflow.sh -i YourSampleSheet.xlsx"
    echo ""
else
    echo "Overall status: FAILED ✗"
    echo ""
    echo "Please address the errors above before running the pipeline."
    echo ""
fi

echo "For more information, see:"
echo "  - README.md (general documentation)"
echo "  - QUICK_REFERENCE.md (quick reference guide)"
echo "======================================================"
