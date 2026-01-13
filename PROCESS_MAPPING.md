# Snakemake to Nextflow Process Mapping

This document provides a detailed mapping between Snakemake rules and their equivalent Nextflow processes in the miND pipeline.

## Overview

The conversion maintains the same workflow logic while adapting to Nextflow's dataflow paradigm.

## Process Mapping Table

| Snakemake Rule | Nextflow Process | Changes | Status |
|----------------|------------------|---------|--------|
| `all` | FINALIZE_OUTPUT | Changed to process | ✓ |
| `makeHTMLReport` | MAKE_HTML_REPORT | Direct mapping | ✓ |
| `runDEAnalysis` | DE_ANALYSIS | Direct mapping | ✓ |
| `quantifySampleMappings` | QUANTIFY_SAMPLE_MAPPINGS | Direct mapping | ✓ |
| `getFastQLibSize` | GET_FASTQ_LIBSIZE | Direct mapping | ✓ |
| `combineSampleMappingStats` | COMBINE_SAMPLE_MAPPING_STATS | Direct mapping | ✓ |
| `combineAllMappingStats` | COMBINE_ALL_MAPPING_STATS | Direct mapping | ✓ |
| `sortBowtieMapping` | (removed) | Integrated into other processes | N/A |
| `mappingBowtieSpikeIns` | BOWTIE_SPIKEINS | Direct mapping | ✓ |
| `mappingBowtieGenome` | BOWTIE_GENOME | Direct mapping | ✓ |
| `mappingBowtieMirna` | BOWTIE_MIRNA | Direct mapping | ✓ |
| `mappingBowtieRNAcentral` | BOWTIE_RNACENTRAL | Direct mapping | ✓ |
| `mappingBowtieCDNA` | BOWTIE_CDNA | Direct mapping | ✓ |
| `miRDeepPrep` | MIRDEEP2_PREP | Direct mapping | ✓ |
| `mappingMiRDeep2MiRNA` | MIRDEEP2_QUANTIFIER | Renamed for clarity | ✓ |
| `mappingBBDukSpikeInsCore` | BBDUK_SPIKEINS_CORE | Direct mapping | ✓ |
| `mappingBBDukSpikeIns` | BBDUK_SPIKEINS | Direct mapping | ✓ |
| `filterCollapsedReads` | (removed) | Not used in current workflow | N/A |
| `collapseReadsFastq` | SEQCLUSTER_COLLAPSE | Direct mapping | ✓ |
| `uncompressing` | UNCOMPRESS_FASTQ_GZ, UNCOMPRESS_FQ_GZ | Split into two processes | ✓ |
| `moveFqToFastq` | (integrated) | Handled in COPY_FQ | ✓ |
| `copyFq2ToFastq` | COPY_FQ | Direct mapping | ✓ |
| `copyFastqToFastq` | COPY_FASTQ | Direct mapping | ✓ |
| `bam2fastq` | BAM2FASTQ | Direct mapping | ✓ |
| `multiQC` | MULTIQC | Direct mapping | ✓ |
| `fastQC` | FASTQC_RAW, FASTQC_TRIMMED | Split by stage | ✓ |
| `adapterTrimming` | CUTADAPT | Direct mapping | ✓ |

## Detailed Comparisons

### Input File Processing

**Snakemake Approach:**
```python
rule bam2fastq:
    input: sampleSheetPath + "/{filename}.bam"
    output: temp("%s/fastq_raw/{filename}.fastq" % outPath)
    shell: "samtools bam2fq {input} > {output}"
```

**Nextflow Equivalent:**
```groovy
process BAM2FASTQ {
    input:
    tuple val(sample), val(samplePath)
    
    output:
    tuple val(sample), path("${sample}.fastq"), emit: fastq
    
    script:
    """
    samtools bam2fq ${samplePath}.bam > ${sample}.fastq
    """
}
```

**Key Difference:** Nextflow uses channels and tuples instead of wildcards.

### Quality Control

**Snakemake Approach:**
```python
rule fastQC:
    input: "%s/fastq_{mod}/{filename}.fastq" % outPath
    output:
        html = "%s/fastqc_{mod}/{filename}_fastqc.html" % outPath,
        zip = temp("%s/fastqc_{mod}/{filename}_fastqc.zip" % outPath)
    shell: "fastqc '{input}' --outdir='{params.outPath}/fastqc_{wildcards.mod}/'"
```

**Nextflow Equivalent:**
```groovy
process FASTQC_RAW {
    input:
    tuple val(sample), path(fastq)
    
    output:
    path "${sample}_fastqc.html", emit: html
    path "${sample}_fastqc.zip", emit: zip
    
    script:
    """
    fastqc ${fastq} --outdir=.
    """
}
```

**Key Difference:** Separate processes for raw and trimmed in Nextflow for clarity.

### Adapter Trimming

**Snakemake Approach:**
```python
rule adapterTrimming:
    input: "%s/fastq_raw/{filename}.fastq" % outPath
    output: temp("%s/fastq_trimmed/{filename}.fastq" % outPath)
    shell:
        "cutadapt {config[adapter]} --minimum-length {config[readMinLength]} "
        "--quality-cutoff {config[qualityCutoff]} --discard-untrimmed "
        "--cores={threads} -o '{output}' '{input}' > {log} 2>&1"
```

**Nextflow Equivalent:**
```groovy
process CUTADAPT {
    input:
    tuple val(sample), path(fastq)
    
    output:
    tuple val(sample), path("${sample}.fastq"), emit: trimmed_fastq
    path "${sample}.log", emit: log
    
    script:
    """
    cutadapt ${params.adapter} \
        --minimum-length ${params.readMinLength} \
        --quality-cutoff ${params.qualityCutoff} \
        --discard-untrimmed \
        --cores=${task.cpus} \
        -o ${sample}.fastq \
        ${fastq} > ${sample}.log 2>&1
    """
}
```

**Key Difference:** Nextflow uses `params` and `task.cpus` instead of `config` and `threads`.

### Bowtie Mapping

**Snakemake Approach:**
```python
rule mappingBowtieGenome:
    input: "%s/mapping_bowtie_spikeins/{filename}.unmapped.fasta" % outPath
    output:
        map = "%s/mapping_bowtie_genome/{filename}.map" % outPath,
        mapped = temp("%s/mapping_bowtie_genome/{filename}.mapped.fasta" % outPath),
        unmapped = temp("%s/mapping_bowtie_genome/{filename}.unmapped.fasta" % outPath)
    shell:
        "bowtie --threads {threads} -f -k1 -v2 --fullref "
        "--un '{output.unmapped}' --al '{output.mapped}' "
        "{config[repoPath]}/{config[genomeID]}/{config[genomeVersion]}/bowtiedb/genome "
        "'{input}' > '{output.map}'"
```

**Nextflow Equivalent:**
```groovy
process BOWTIE_GENOME {
    input:
    tuple val(sample), path(fasta)
    
    output:
    tuple val(sample), path("${sample}.map"), emit: map
    tuple val(sample), path("${sample}.mapped.fasta"), emit: mapped
    tuple val(sample), path("${sample}.unmapped.fasta"), emit: unmapped
    
    script:
    """
    bowtie --threads ${task.cpus} -f -k1 -v2 --fullref \
        --un ${sample}.unmapped.fasta \
        --al ${sample}.mapped.fasta \
        ${params.repoPath}/${params.genomeID}/${params.genomeVersion}/bowtiedb/genome \
        ${fasta} > ${sample}.map
    """
}
```

**Key Difference:** Nextflow processes emit multiple named outputs for better channel management.

### Differential Expression Analysis

**Snakemake Approach:**
```python
rule runDEAnalysis:
    input:
        readsFile = "%s/analysis_sampleMappingStats/all_samples.csv" % outPath,
        sampleSheetFile = sampleSheet
    output: directory("%s/analysis_differentialExpression/" % outPath)
    shell:
        "Rscript scripts/differentialExpression.R --outDir='{output}' "
        "--readsFile='{input.readsFile}' --sampleSheetFile='{input.sampleSheetFile}' "
        "--alpha='{params.alpha}'"
```

**Nextflow Equivalent:**
```groovy
process DE_ANALYSIS {
    input:
    path reads_file
    path sampleSheet
    
    output:
    path ".", emit: de_dir
    
    script:
    """
    Rscript ${projectDir}/scripts/differentialExpression.R \
        --outDir=. \
        --readsFile=${reads_file} \
        --sampleSheetFile=${sampleSheet} \
        --alpha=${params.alpha}
    """
}
```

**Key Difference:** Nextflow uses absolute paths for scripts via `${projectDir}`.

## Configuration Mapping

### Thread Configuration

**Snakemake (config.yaml):**
```yaml
threads:
  high: 6
  medium: 4
  low: 2
```

**Nextflow (nextflow.config):**
```groovy
params {
    threads_high = 6
    threads_medium = 4
    threads_low = 2
}

process {
    withLabel: high_cpu { cpus = params.threads_high }
    withLabel: medium_cpu { cpus = params.threads_medium }
    withLabel: low_cpu { cpus = params.threads_low }
}
```

### Conda Environments

**Snakemake:**
```python
rule fastQC:
    conda: "envs/fastqc.yml"
```

**Nextflow:**
```groovy
process {
    withName: 'FASTQC.*' {
        conda = "${projectDir}/envs/fastqc.yml"
    }
}
```

## Workflow Structure Differences

### Snakemake (Pull-based)

```python
rule all:
    input: expand("{outPath}/analysis/report.html")

# Snakemake works backwards from target files
```

### Nextflow (Push-based)

```groovy
workflow {
    // Create input channel
    samples = Channel.fromList(sampleList)
    
    // Process data through pipeline
    fastq = INPUT_PROCESSING(samples)
    trimmed = CUTADAPT(fastq)
    report = MAKE_HTML_REPORT(...)
}
```

## Channel Management

Nextflow introduces explicit data channels:

```groovy
// Single sample channel
samples_ch = Channel.fromList(['sample1', 'sample2'])

// Tuple channel (sample + file)
fastq_ch = samples_ch.map { sample ->
    [sample, file("${sample}.fastq")]
}

// Mixing channels
all_fastq = bam_fastq
    .mix(fastq_gz_fastq)
    .mix(fastq_copy)
```

## Error Handling

**Snakemake:**
```python
# Retry automatically based on exit codes
# Use --restart-times flag
```

**Nextflow:**
```groovy
process {
    errorStrategy = 'retry'
    maxRetries = 1
}
```

## Resume Capability

**Snakemake:**
- Based on file modification times
- Reruns if output is older than input

**Nextflow:**
- Based on input file hashes
- More robust caching
- Use `-resume` flag

## Best Practices

1. **Process Naming:** Use UPPERCASE for processes in Nextflow
2. **Channel Management:** Explicitly name all process outputs
3. **Configuration:** Use `params` for user-configurable values
4. **Paths:** Use `${projectDir}` for script paths
5. **Resources:** Use `task.cpus` and `task.memory` in processes

## Migration Tips

1. Convert wildcards to sample variables in tuples
2. Replace `{threads}` with `${task.cpus}`
3. Replace `{config[...]}` with `${params....}`
4. Convert temp() files to temporary process outputs
5. Replace expand() with channel operations

## Validation

After conversion, verify:
- [ ] All rules have equivalent processes
- [ ] Dependencies are correctly modeled as channels
- [ ] Configuration parameters are accessible
- [ ] Output paths are correct
- [ ] Conda environments are properly referenced

---

**Note:** This mapping is based on miND pipeline version 2.0 (Nextflow) and version 1.3 (Snakemake).
