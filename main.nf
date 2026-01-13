#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

/*
 * miND - miRNA NGS data pipeline
 * Copyright (C) 2021 TAmiRNA GmbH
 * Written and developed by Andreas B. Diendorfer
 */

// Import groovy libraries
import groovy.json.JsonSlurper
import java.nio.file.Paths

/*
 * Parse Excel configuration file
 */
def parseExcelConfig(sampleSheet) {
    def configData = [:]
    def samples = []
    
    // Run Python script to parse Excel safely
    def parseScript = file("${projectDir}/scripts/parse_excel_config.py")
    if (parseScript.exists()) {
        try {
            // Use ProcessBuilder for safer command execution
            def command = ['python3', parseScript.toString(), sampleSheet.toString()]
            def proc = command.execute()
            proc.waitFor()
            
            if (proc.exitValue() == 0) {
                def jsonOutput = proc.in.text
                def jsonSlurper = new JsonSlurper()
                configData = jsonSlurper.parseText(jsonOutput)
            } else {
                def errorOutput = proc.err.text
                log.error "Failed to parse Excel configuration: ${errorOutput}"
            }
        } catch (Exception e) {
            log.error "Error executing Excel parser: ${e.message}"
        }
    } else {
        log.warn "Excel parser script not found: ${parseScript}"
    }
    
    return configData
}

/*
 * Main workflow
 */
workflow {
    // Check required parameters
    if (!params.sampleSheet) {
        error "Please provide a sample sheet with --sampleSheet parameter"
    }
    
    // Parse sample sheet
    sampleSheetFile = file(params.sampleSheet)
    if (!sampleSheetFile.exists()) {
        error "Sample sheet not found: ${params.sampleSheet}"
    }
    
    // Determine output path
    def sampleSheetPath = sampleSheetFile.parent
    def sampleSheetName = sampleSheetFile.name
    def sampleSheetStem = sampleSheetFile.baseName.replaceAll('.xlsx$', '')
    
    def outputSubfolder = params.outputSubfolder ?: sampleSheetStem.replaceAll(/-?_?SampleContrastSheet/, '') ?: 'default'
    def outPath = "${params.outdir}/${outputSubfolder}"
    
    // Parse Excel file to get sample list and configuration
    def config = parseExcelConfig(sampleSheetFile)
    
    // Update parameters from Excel configuration
    if (config.containsKey('samples') && config.samples.size() > 0) {
        log.info "Found ${config.samples.size()} samples in sample sheet"
        
        // Update params from Excel if present
        if (config.containsKey('projectID')) {
            params.projectID = config.projectID
        }
        if (config.containsKey('adapter')) {
            params.adapter = config.adapter
        }
        if (config.containsKey('readMinLength')) {
            params.readMinLength = config.readMinLength
        }
        if (config.containsKey('qualityCutoff')) {
            params.qualityCutoff = config.qualityCutoff
        }
        if (config.containsKey('alpha')) {
            params.alpha = config.alpha
        }
        if (config.containsKey('deAnalysis')) {
            params.deAnalysis = config.deAnalysis
        }
        if (config.containsKey('includeSpikeIns')) {
            params.includeSpikeIns = config.includeSpikeIns
        }
        if (config.containsKey('includeSequence')) {
            params.includeSequence = config.includeSequence
        }
        
        // Main pipeline execution
        MIND_PIPELINE(sampleSheetFile, sampleSheetPath, outPath, config.samples)
    } else {
        error "No samples found in sample sheet. Please check the Excel file format."
    }
}

/*
 * Main pipeline workflow
 */
workflow MIND_PIPELINE {
    take:
        sampleSheet
        sampleSheetPath
        outPath
        sampleList
    
    main:
        // Create sample channel from list
        samples_ch = Channel.fromList(sampleList)
        
        // Process raw input files - determine format for each sample
        // Check which format exists for each sample
        samples_with_format = samples_ch.map { sample ->
            def samplePath = "${sampleSheetPath}/${sample}"
            def format = null
            
            // Check file existence in order of preference
            if (file("${samplePath}.bam").exists()) {
                format = 'bam'
            } else if (file("${samplePath}.fastq.gz").exists()) {
                format = 'fastq.gz'
            } else if (file("${samplePath}.fq.gz").exists()) {
                format = 'fq.gz'
            } else if (file("${samplePath}.fastq").exists()) {
                format = 'fastq'
            } else if (file("${samplePath}.fq").exists()) {
                format = 'fq'
            } else {
                log.warn "No input file found for sample: ${sample}"
            }
            
            return [sample, format, samplePath]
        }.filter { it[1] != null }
        
        // Branch samples by format
        samples_with_format.branch {
            bam: it[1] == 'bam'
                return [it[0], it[2]]
            fastq_gz: it[1] == 'fastq.gz'
                return [it[0], it[2]]
            fq_gz: it[1] == 'fq.gz'
                return [it[0], it[2]]
            fastq: it[1] == 'fastq'
                return [it[0], it[2]]
            fq: it[1] == 'fq'
                return [it[0], it[2]]
        }.set { samples_branched }
        
        // Process each format
        bam_fastq = BAM2FASTQ(samples_branched.bam, sampleSheetPath, outPath)
        fastq_gz_fastq = UNCOMPRESS_FASTQ_GZ(samples_branched.fastq_gz, sampleSheetPath, outPath)
        fq_gz_fastq = UNCOMPRESS_FQ_GZ(samples_branched.fq_gz, sampleSheetPath, outPath)
        fastq_copy = COPY_FASTQ(samples_branched.fastq, sampleSheetPath, outPath)
        fq_copy = COPY_FQ(samples_branched.fq, sampleSheetPath, outPath)
        
        // Combine all raw fastq files
        fastq_raw = bam_fastq.fastq
            .mix(fastq_gz_fastq.fastq)
            .mix(fq_gz_fastq.fastq)
            .mix(fastq_copy.fastq)
            .mix(fq_copy.fastq)
        
        // Quality control on raw data
        FASTQC_RAW(fastq_raw, outPath)
        
        // Adapter trimming
        CUTADAPT(fastq_raw, outPath)
        
        // Quality control on trimmed data
        FASTQC_TRIMMED(CUTADAPT.out.trimmed_fastq, outPath)
        
        // Collapse reads
        SEQCLUSTER_COLLAPSE(CUTADAPT.out.trimmed_fastq, outPath)
        
        // Get library sizes
        GET_FASTQ_LIBSIZE(CUTADAPT.out.trimmed_fastq, outPath)
        
        // miRDeep2 preparation
        MIRDEEP2_PREP(CUTADAPT.out.trimmed_fastq, outPath)
        
        // BBDuk spike-in mapping (core)
        BBDUK_SPIKEINS_CORE(CUTADAPT.out.trimmed_fastq, outPath)
        
        // BBDuk spike-in mapping (full)
        BBDUK_SPIKEINS(CUTADAPT.out.trimmed_fastq, outPath)
        
        // Bowtie mapping cascade
        BOWTIE_SPIKEINS(MIRDEEP2_PREP.out.collapsed_reads, outPath)
        BOWTIE_GENOME(BOWTIE_SPIKEINS.out.unmapped, outPath)
        BOWTIE_MIRNA(BOWTIE_GENOME.out.mapped, outPath)
        BOWTIE_RNACENTRAL(BOWTIE_MIRNA.out.unmapped, outPath)
        BOWTIE_CDNA(BOWTIE_RNACENTRAL.out.unmapped, outPath)
        
        // miRDeep2 quantification
        MIRDEEP2_QUANTIFIER(BOWTIE_GENOME.out.mapped, outPath)
        
        // Combine mapping stats per sample
        COMBINE_SAMPLE_MAPPING_STATS(
            MIRDEEP2_QUANTIFIER.out.mirna_csv,
            BBDUK_SPIKEINS_CORE.out.stats,
            outPath
        )
        
        // Combine all mapping stats
        COMBINE_ALL_MAPPING_STATS(
            COMBINE_SAMPLE_MAPPING_STATS.out.csv.collect(),
            sampleSheet,
            outPath
        )
        
        // Quantify sample mappings
        QUANTIFY_SAMPLE_MAPPINGS(
            GET_FASTQ_LIBSIZE.out.libsize.collect(),
            BOWTIE_SPIKEINS.out.map.collect(),
            BOWTIE_GENOME.out.map.collect(),
            BOWTIE_MIRNA.out.map.collect(),
            BOWTIE_RNACENTRAL.out.map.collect(),
            BOWTIE_CDNA.out.map.collect(),
            BOWTIE_GENOME.out.mapped_ssd.collect(),
            BOWTIE_GENOME.out.unmapped_ssd.collect(),
            sampleSheet,
            outPath
        )
        
        // MultiQC
        MULTIQC(
            FASTQC_RAW.out.zip.collect(),
            FASTQC_TRIMMED.out.zip.collect(),
            CUTADAPT.out.log.collect(),
            outPath
        )
        
        // Differential expression analysis (conditional)
        if (params.deAnalysis == 1) {
            DE_ANALYSIS(
                COMBINE_ALL_MAPPING_STATS.out.csv,
                sampleSheet,
                outPath
            )
            de_dir = DE_ANALYSIS.out.de_dir
        } else {
            de_dir = Channel.empty()
        }
        
        // Generate HTML report
        MAKE_HTML_REPORT(
            sampleSheet,
            COMBINE_ALL_MAPPING_STATS.out.csv,
            COMBINE_ALL_MAPPING_STATS.out.rpm_mirna,
            QUANTIFY_SAMPLE_MAPPINGS.out.csv,
            QUANTIFY_SAMPLE_MAPPINGS.out.genome_mapping,
            MULTIQC.out.html,
            de_dir,
            outPath
        )
        
        // Final assembly
        FINALIZE_OUTPUT(
            MAKE_HTML_REPORT.out.html,
            sampleSheet,
            sampleSheetPath,
            outPath
        )
    
    emit:
        report = MAKE_HTML_REPORT.out.html
}

/*
 * Process definitions
 */

process BAM2FASTQ {
    label 'low_cpu'
    tag "$sample"
    
    input:
    tuple val(sample), val(samplePath)
    val sampleSheetPath
    val outPath
    
    output:
    tuple val(sample), path("${sample}.fastq"), emit: fastq
    
    script:
    """
    samtools bam2fq ${samplePath}.bam > ${sample}.fastq
    """
}

process UNCOMPRESS_FASTQ_GZ {
    label 'low_cpu'
    tag "$sample"
    
    input:
    tuple val(sample), val(samplePath)
    val sampleSheetPath
    val outPath
    
    output:
    tuple val(sample), path("${sample}.fastq"), emit: fastq
    
    script:
    """
    gzip -dc ${samplePath}.fastq.gz > ${sample}.fastq
    """
}

process UNCOMPRESS_FQ_GZ {
    label 'low_cpu'
    tag "$sample"
    
    input:
    tuple val(sample), val(samplePath)
    val sampleSheetPath
    val outPath
    
    output:
    tuple val(sample), path("${sample}.fastq"), emit: fastq
    
    script:
    """
    gzip -dc ${samplePath}.fq.gz > ${sample}.fastq
    """
}

process COPY_FASTQ {
    label 'low_cpu'
    tag "$sample"
    
    input:
    tuple val(sample), val(samplePath)
    val sampleSheetPath
    val outPath
    
    output:
    tuple val(sample), path("${sample}.fastq"), emit: fastq
    
    script:
    """
    cp ${samplePath}.fastq ${sample}.fastq
    """
}

process COPY_FQ {
    label 'low_cpu'
    tag "$sample"
    
    input:
    tuple val(sample), val(samplePath)
    val sampleSheetPath
    val outPath
    
    output:
    tuple val(sample), path("${sample}.fastq"), emit: fastq
    
    script:
    """
    cp ${samplePath}.fq ${sample}.fastq
    """
}

process CUTADAPT {
    label 'high_cpu'
    tag "$sample"
    publishDir "${outPath}/fastq_trimmed", mode: 'copy'
    
    input:
    tuple val(sample), path(fastq)
    val outPath
    
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

process FASTQC_RAW {
    label 'low_cpu'
    tag "$sample"
    publishDir "${outPath}/fastqc_raw", mode: 'copy'
    
    input:
    tuple val(sample), path(fastq)
    val outPath
    
    output:
    path "${sample}_fastqc.html", emit: html
    path "${sample}_fastqc.zip", emit: zip
    
    script:
    """
    fastqc ${fastq} --outdir=.
    """
}

process FASTQC_TRIMMED {
    label 'low_cpu'
    tag "$sample"
    publishDir "${outPath}/fastqc_trimmed", mode: 'copy'
    
    input:
    tuple val(sample), path(fastq)
    val outPath
    
    output:
    path "${sample}_fastqc.html", emit: html
    path "${sample}_fastqc.zip", emit: zip
    
    script:
    """
    fastqc ${fastq} --outdir=.
    """
}

process SEQCLUSTER_COLLAPSE {
    label 'low_cpu'
    tag "$sample"
    
    input:
    tuple val(sample), path(fastq)
    val outPath
    
    output:
    tuple val(sample), path("${sample}.fastq"), emit: collapsed
    
    script:
    """
    seqcluster collapse -f ${fastq} -o ./
    mv collapse/*.fastq ${sample}.fastq || mv *.fastq ${sample}.fastq
    """
}

process GET_FASTQ_LIBSIZE {
    label 'low_cpu'
    tag "$sample"
    publishDir "${outPath}/fastq_trimmed", mode: 'copy', pattern: "*.libsize"
    
    input:
    tuple val(sample), path(fastq)
    val outPath
    
    output:
    tuple val(sample), path("${sample}.fastq.libsize"), emit: libsize
    
    script:
    """
    wc -l ${fastq} | awk '{print \$1/4}' > ${sample}.fastq.libsize
    """
}

process MIRDEEP2_PREP {
    label 'medium_cpu'
    tag "$sample"
    
    input:
    tuple val(sample), path(fastq)
    val outPath
    
    output:
    tuple val(sample), path("${sample}.fasta"), emit: collapsed_reads
    
    script:
    """
    mapper.pl ${fastq} -e -h -j -l ${params.readMinLength} -o ${task.cpus} -m -s ${sample}.fasta > mapper.log 2>&1
    rm -fr mapper_logs bowtie.log
    """
}

process BBDUK_SPIKEINS_CORE {
    label 'high_cpu'
    tag "$sample"
    
    input:
    tuple val(sample), path(fastq)
    val outPath
    
    output:
    tuple val(sample), path("${sample}.txt"), emit: stats
    
    script:
    """
    bbduk.sh threads=${task.cpus} -Xmx1024m \
        in=${fastq} \
        outm=stdout.fq \
        ref=libs/spikeins/spikeins_core.fa \
        stats=${sample}.txt \
        statscolumns=5 \
        k=13 \
        maskmiddle=f \
        rcomp=f \
        hdist=0 \
        edist=0 \
        rename=t > /dev/null
    """
}

process BBDUK_SPIKEINS {
    label 'high_cpu'
    tag "$sample"
    
    input:
    tuple val(sample), path(fastq)
    val outPath
    
    output:
    tuple val(sample), path("${sample}.txt"), emit: stats
    
    script:
    """
    bbduk.sh threads=${task.cpus} -Xmx1024m \
        in=${fastq} \
        outm=stdout.fq \
        ref=libs/spikeins/spikeins.fa \
        stats=${sample}.txt \
        statscolumns=5 \
        k=21 \
        maskmiddle=f \
        rcomp=f \
        hdist=0 \
        edist=0 \
        rename=t > /dev/null
    """
}

process BOWTIE_SPIKEINS {
    label 'medium_cpu'
    tag "$sample"
    publishDir "${outPath}/mapping_bowtie_spikeins", mode: 'copy'
    
    input:
    tuple val(sample), path(fasta)
    val outPath
    
    output:
    tuple val(sample), path("${sample}.map"), emit: map
    tuple val(sample), path("${sample}.unmapped.fasta"), emit: unmapped
    
    script:
    """
    bowtie --threads ${task.cpus} -f -k1 --fullref --best -v0 --norc \
        --un ${sample}.unmapped.fasta \
        libs/spikeins/spikeins_full \
        ${fasta} > ${sample}.map
    """
}

process BOWTIE_GENOME {
    label 'medium_cpu'
    tag "$sample"
    publishDir "${outPath}/mapping_bowtie_genome", mode: 'copy'
    
    input:
    tuple val(sample), path(fasta)
    val outPath
    
    output:
    tuple val(sample), path("${sample}.map"), emit: map
    tuple val(sample), path("${sample}.mapped.fasta"), emit: mapped
    tuple val(sample), path("${sample}.unmapped.fasta"), emit: unmapped
    tuple val(sample), path("${sample}.mapped.ssd"), emit: mapped_ssd
    tuple val(sample), path("${sample}.unmapped.ssd"), emit: unmapped_ssd
    
    script:
    """
    # Run Bowtie mapping to genome
    bowtie --threads ${task.cpus} -f -k1 -v2 --fullref \
        --un ${sample}.unmapped.fasta \
        --al ${sample}.mapped.fasta \
        ${params.repoPath}/${params.genomeID}/${params.genomeVersion}/bowtiedb/genome \
        ${fasta} > ${sample}.map
    
    # Calculate sequence size distributions for mapped reads
    cat ${sample}.mapped.fasta | \
        awk 'BEGIN {FS="x"; OFS="\\t"} 
             NR%2==1 {header=\$0; split(\$1,a,"_"); count=\$2} 
             NR%2==0 {len=length(\$0); totals[len]+=count} 
             END {for(l in totals) print totals[l], l}' | \
        sort -k2 -n > ${sample}.mapped.ssd
    
    # Calculate sequence size distributions for unmapped reads
    cat ${sample}.unmapped.fasta | \
        awk 'BEGIN {FS="x"; OFS="\\t"} 
             NR%2==1 {header=\$0; split(\$1,a,"_"); count=\$2} 
             NR%2==0 {len=length(\$0); totals[len]+=count} 
             END {for(l in totals) print totals[l], l}' | \
        sort -k2 -n > ${sample}.unmapped.ssd
    """
}

process BOWTIE_MIRNA {
    label 'medium_cpu'
    tag "$sample"
    publishDir "${outPath}/mapping_bowtie_mirna", mode: 'copy'
    
    input:
    tuple val(sample), path(fasta)
    val outPath
    
    output:
    tuple val(sample), path("${sample}.map"), emit: map
    tuple val(sample), path("${sample}.unmapped.fasta"), emit: unmapped
    
    script:
    """
    bowtie --threads ${task.cpus} -f -k1 --fullref --best -v1 \
        --un ${sample}.unmapped.fasta \
        ${params.repoPath}/mirbase/${params.miRBaseVersion}/hairpin/bowtiedb/hairpin-${params.speciesCode} \
        ${fasta} > ${sample}.map
    """
}

process BOWTIE_RNACENTRAL {
    label 'medium_cpu'
    tag "$sample"
    publishDir "${outPath}/mapping_bowtie_rnacentral", mode: 'copy'
    
    input:
    tuple val(sample), path(fasta)
    val outPath
    
    output:
    tuple val(sample), path("${sample}.map"), emit: map
    tuple val(sample), path("${sample}.unmapped.fasta"), emit: unmapped
    
    script:
    """
    bowtie --threads ${task.cpus} -f -k1 --fullref --best -v1 --norc \
        --un ${sample}.unmapped.fasta \
        ${params.repoPath}/rnacentral/${params.rnacentralVersion}/bowtiedb/rnacentral_species_specific_ids-${params.speciesTxid} \
        ${fasta} > ${sample}.map
    """
}

process BOWTIE_CDNA {
    label 'medium_cpu'
    tag "$sample"
    publishDir "${outPath}/mapping_bowtie_cdna", mode: 'copy'
    
    input:
    tuple val(sample), path(fasta)
    val outPath
    
    output:
    tuple val(sample), path("${sample}.map"), emit: map
    tuple val(sample), path("${sample}.unmapped.fasta"), emit: unmapped
    
    script:
    """
    bowtie --threads ${task.cpus} -f -k1 --fullref --best -v1 --norc \
        --un ${sample}.unmapped.fasta \
        ${params.repoPath}/${params.genomeID}/${params.genomeVersion}/bowtiedb/cdna \
        ${fasta} > ${sample}.map
    """
}

process MIRDEEP2_QUANTIFIER {
    label 'medium_cpu'
    tag "$sample"
    publishDir "${outPath}/mapping_mirdeep2_miRNA/${sample}", mode: 'copy'
    
    input:
    tuple val(sample), path(fasta)
    val outPath
    
    output:
    tuple val(sample), path("miRNAs_expressed_all_samples_default.csv"), emit: mirna_csv
    
    script:
    """
    quantifier.pl \
        -p ${params.repoPath}/mirbase/${params.miRBaseVersion}/hairpin/uncompressed/hairpin-${params.speciesCode}.dna.fa \
        -y default \
        -T ${task.cpus} \
        -d \
        -m ${params.repoPath}/mirbase/${params.miRBaseVersion}/mature/uncompressed/mature-${params.speciesCode}.dna.fa \
        -r ${fasta} > quantifier.log 2>&1
    
    rm -fr expression_analyses/expression_analyses_default/*.ebwt
    """
}

process COMBINE_SAMPLE_MAPPING_STATS {
    label 'low_cpu'
    tag "$sample"
    publishDir "${outPath}/analysis_sampleMappingStats", mode: 'copy'
    
    input:
    tuple val(sample), path(mirna_csv)
    tuple val(sample), path(spikeins_txt)
    val outPath
    
    output:
    tuple val(sample), path("${sample}.csv"), emit: csv
    
    script:
    """
    sleep 3
    Rscript ${projectDir}/scripts/combineSampleMappingStats.R \
        --outFile=${sample}.csv \
        --includeSpikeIns=${params.includeSpikeIns} \
        --input.miRNA=${mirna_csv} \
        --input.spikeins=${spikeins_txt}
    """
}

process COMBINE_ALL_MAPPING_STATS {
    label 'low_cpu'
    publishDir "${outPath}/analysis_sampleMappingStats", mode: 'copy'
    
    input:
    path csv_files
    path sampleSheet
    val outPath
    
    output:
    path "all_samples.csv", emit: csv
    path "all_samples_rpm_miRNA.csv", emit: rpm_mirna
    path "all_samples_rpm_lib.csv", emit: rpm_lib
    path "all_samples_rpm_dist.dat", emit: rpm_plot
    
    script:
    """
    sleep 3
    Rscript ${projectDir}/scripts/combineAllMappingStats.R \
        --outFile=all_samples.csv \
        --includeSequence=${params.includeSequence} \
        --sampleSheetFile=${sampleSheet} \
        ${csv_files}
    """
}

process QUANTIFY_SAMPLE_MAPPINGS {
    label 'high_cpu'
    publishDir "${outPath}/analysis_quantifySampleMappings", mode: 'copy'
    
    input:
    path libsize_files
    path spikeins_maps
    path genome_maps
    path mirna_maps
    path rnacentral_maps
    path cdna_maps
    path mapped_ssd_files
    path unmapped_ssd_files
    path sampleSheet
    val outPath
    
    output:
    path "all_samples.csv", emit: csv
    path "all_samples.dat", emit: dat
    path "all_samples_perc.csv", emit: csv_perc
    path "all_samples_perc.dat", emit: dat_perc
    path "all_samples_genome_mapping.csv", emit: genome_mapping
    
    script:
    """
    sleep 3
    Rscript ${projectDir}/scripts/quantifySampleMappings.R \
        --outFile=all_samples.csv \
        --outFileGenomeMapping=all_samples_genome_mapping.csv \
        --sampleSheetFile=${sampleSheet} \
        --cores=${task.cpus} \
        ${genome_maps}
    """
}

process MULTIQC {
    label 'low_cpu'
    publishDir "${outPath}/multiqc", mode: 'copy'
    
    input:
    path fastqc_raw_zips
    path fastqc_trimmed_zips
    path cutadapt_logs
    val outPath
    
    output:
    path "multiqc_report.html", emit: html
    
    script:
    """
    mkdir -p fastqc_raw fastqc_trimmed cutadapt_logs
    mv *_raw_fastqc.zip fastqc_raw/ || true
    mv *_trimmed_fastqc.zip fastqc_trimmed/ || true
    mv *.log cutadapt_logs/ || true
    
    multiqc fastqc_raw/ fastqc_trimmed/ cutadapt_logs/ \
        --config ${projectDir}/multiqc_config.yaml \
        -o .
    """
}

process DE_ANALYSIS {
    label 'low_cpu'
    publishDir "${outPath}/analysis_differentialExpression", mode: 'copy'
    
    input:
    path reads_file
    path sampleSheet
    val outPath
    
    output:
    path ".", emit: de_dir
    
    script:
    """
    sleep 3
    Rscript ${projectDir}/scripts/differentialExpression.R \
        --outDir=. \
        --readsFile=${reads_file} \
        --sampleSheetFile=${sampleSheet} \
        --alpha=${params.alpha}
    """
}

process MAKE_HTML_REPORT {
    label 'low_cpu'
    publishDir "${outPath}/analysis", mode: 'copy'
    
    input:
    path sampleSheet
    path mirna_stats
    path mirna_stats_rpm
    path sample_quant
    path genome_mapping
    path multiqc_html
    path de_dir
    val outPath
    
    output:
    path "report.html", emit: html
    
    script:
    """
    Rscript -e "rmarkdown::render('${projectDir}/scripts/report.Rmd', output_file='report.html')"
    """
}

process FINALIZE_OUTPUT {
    publishDir "${outPath}", mode: 'copy'
    
    input:
    path report_html
    path sampleSheet
    val sampleSheetPath
    val outPath
    
    output:
    path "*.zip", emit: final_zip
    
    script:
    """
    # Create rundata directory
    mkdir -p rundata
    echo '${sampleSheetPath}' > rundata/inputfiles.txt
    ls -l "${sampleSheetPath}" >> rundata/inputfiles.txt
    cp ${sampleSheet} rundata/
    tar cfz rundata/nextflow.tar.gz main.nf nextflow.config run_nextflow.sh scripts/
    
    # Generate report zip file
    DATE=\$(date -I)
    cp ${report_html} "\${DATE}_${params.projectID}_MINDreport.html"
    zip -q -j "\${DATE}_${params.projectID}_${params.speciesCode}_${params.alpha}_MINDreport.zip" \
        "\${DATE}_${params.projectID}_MINDreport.html" \
        ${outPath}/multiqc/multiqc_report.html \
        ${sampleSheet}
    rm "\${DATE}_${params.projectID}_MINDreport.html"
    
    echo ""
    echo "####################################################"
    echo "#          miND - miRNA NGS data pipeline          #"
    echo "#         Copyright (C) 2021 TAmiRNA GmbH          #"
    echo "#  Written and developed by Andreas B. Diendorfer  #"
    echo "#                                                  #"
    echo "#                  RUN FINISHED!                   #"
    echo "####################################################"
    echo ""
    echo "Your results file is located at:"
    echo "${outPath}/\${DATE}_${params.projectID}_${params.speciesCode}_${params.alpha}_MINDreport.zip"
    echo ""
    """
}
