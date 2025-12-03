#!/usr/bin/env bash
set -euo pipefail

echo "===================================================================================="
echo "   IBBC 60414 - Folder Structure , Fastp and FastQC Pipeline , File Verification"
echo "===================================================================================="
echo
echo "Please enter a tools_qc environment with FastQC, Fastp and Multiqc before running this script."


#Creates the necessary directories
echo "[1/6] Creating folder structure..."

mkdir -p data/raw
mkdir -p data/problematic_files
mkdir -p data/fastp_trimmed
mkdir -p results/fastqc_raw
mkdir -p results/fastqc_trimmed
mkdir -p results/multiqc
mkdir -p logs

RAW_DIR="data/raw"
QUAR_DIR="data/problematic_files"
LOG_DIR="logs"
TRIM_DIR="data/fastp_trimmed"
FASTQC_RAW="results/fastqc_raw"
FASTQC_TRIM="results/fastqc_trimmed"
QUAR_LOG="${LOG_DIR}/problematic_files.log"

echo "Folder structure ready."
echo


# Asks user to place raw data files in the "data/raw"
echo "FASTQ files should be placed in: $RAW_DIR"
read -p "Have you placed your FASTQ files in data/raw? (y/n): " READY
READY=${READY:-n}

if [[ "$READY" != "y" ]]; then
    echo "Please place your FASTQ files inside data/raw and rerun."
    exit 1
fi


# Additional script - It separates and logs corrupted or unpaired files to a problematic_files folder
echo "[2/6] Running problematic files check..."
echo "Logging to: $QUAR_LOG"
echo "Problematic Files Log - $(date -Iseconds)" > "$QUAR_LOG"
echo "---------------------------------------------" >> "$QUAR_LOG"

#shopt -s nullglob    makes sure that it returns an empty list when no files meet the criteria
shopt -s nullglob
FASTQ_FILES=("$RAW_DIR"/*.fastq.gz)

#if the list is empty/ has no correctly named files it exits the program and prompts the user to make the needed modifications
if [[ ${#FASTQ_FILES[@]} -eq 0 ]]; then
    echo "No FASTQ files found in data/raw. Please make sure they are in the correct directory and have the correct file naming convention."
    echo "R1 files should end with '_R1.fastq.gz' and R2 files with '_R2.fastq.gz'."
    exit 1
fi


#Checks if the naming convention of each file is correct and stores them in SAMPLES
declare -A SAMPLES

for file in "${FASTQ_FILES[@]}"; do
    base=$(basename "$file")

    if [[ "$base" =~ (.*)_R1\.fastq\.gz$ ]]; then
        sample="${BASH_REMATCH[1]}"
        SAMPLES["$sample,R1"]="$file"
    elif [[ "$base" =~ (.*)_R2\.fastq\.gz$ ]]; then
        sample="${BASH_REMATCH[1]}"
        SAMPLES["$sample,R2"]="$file"
    else
        echo "Unknown pattern moving $file to Problematic files folder"
        echo "[Unknown Pattern] $file Problematic Files" >> "$QUAR_LOG"
        mv "$file" "$QUAR_DIR/"
    fi
done

# Uses the SAMPLES array to check if every sample has a R1 and R2 pair
for key in "${!SAMPLES[@]}"; do
    IFS=',' read -r sample readtype <<< "$key"

    R1="${SAMPLES[$sample,R1]:-}"
    R2="${SAMPLES[$sample,R2]:-}"

    #If the sample has no pair it will be moved to the Problematic_files folder
    if [[ -z "$R1" || -z "$R2" ]]; then
        echo "Unpaired sample: $sample"
        [[ -n "$R1" ]] && echo "[Unpaired] $sample → missing R2 → quarantined $R1" >> "$QUAR_LOG" && mv "$R1" "$QUAR_DIR/"
        [[ -n "$R2" ]] && echo "[Unpaired] $sample → missing R1 → quarantined $R2" >> "$QUAR_LOG" && mv "$R2" "$QUAR_DIR/"
        continue
    fi

    #it's checking the integrity of each *_R1.fastq.gz or *_R2.fastq.gz using gzip -t without decompressing the file

    echo -n "Checking integrity of $sample ... "

    #if one of the files is corrupted, it logs which one it is to a .log file and moves both to the problematic_files folder
    if ! gzip -t "$R1" >/dev/null 2>&1; then
        echo "R1 corrupted"
        echo "[Corrupted] $sample R1 ($R1) → quarantined" >> "$QUAR_LOG"
        mv "$R1" "$QUAR_DIR/"
        mv "$R2" "$QUAR_DIR/"
        continue
    fi

    if ! gzip -t "$R2" >/dev/null 2>&1; then
        echo "R2 corrupted"
        echo "[Corrupted] $sample R2 ($R2) → quarantined" >> "$QUAR_LOG"
        mv "$R1" "$QUAR_DIR/"
        mv "$R2" "$QUAR_DIR/"
        continue
    fi

    echo "OK"
done

echo "Problematic Files check complete."
echo


#checks if there are still files in data/raw if there aren't it aborts the script 
VALID_R1=("$RAW_DIR"/*_R1.fastq.gz)
VALID_R2=("$RAW_DIR"/*_R2.fastq.gz)

if [[ ${#VALID_R1[@]} -eq 0 || ${#VALID_R2[@]} -eq 0 ]]; then
    echo "ERROR: No valid sample pairs in data/raw."
    exit 1
fi

echo "[3/6] Valid FASTQ files detected."
echo


#Prompt fot users to change the parameters of  fastp
echo "[4/6] FASTP configuration"

read -p "Number of threads [4]: " THREADS; THREADS=${THREADS:-4}
read -p "Minimum mean quality (--cut_mean_quality) [20]: " QMEAN; QMEAN=${QMEAN:-20}
read -p "Sliding window size (--cut_window_size) [4]: " WINSIZE; WINSIZE=${WINSIZE:-4}
read -p "Minimum read length (--length_required) [50]: " MINLEN; MINLEN=${MINLEN:-50}

read -p "Auto-detect adapters? (y/n) [y]: " ADAPT_DETECT
ADAPT_DETECT=${ADAPT_DETECT:-y}

if [[ "$ADAPT_DETECT" == "n" ]]; then
    read -p "Adapter seq R1: " ADAPTER1
    read -p "Adapter seq R2: " ADAPTER2
fi

echo


# Main pipeline 

echo "[5/6] Running main pipeline..."

#creats a main .log file for the process
MASTER_LOG="logs/pipeline_$(date +%Y%m%d_%H%M%S).log"
echo "Pipeline Start: $(date -Iseconds)" > "$MASTER_LOG"

for R1 in "${VALID_R1[@]}"; do
    sample=$(basename "$R1" | sed -E 's/_R1.*//')
    R2="${RAW_DIR}/${sample}_R2.fastq.gz"

    echo "Processing $sample" | tee -a "$MASTER_LOG"

    SAMPLE_LOG="logs/${sample}.log"

    # applies fastqc to the raw data the 2<&1 makes sure that erros and warnings are sent to the log file
    fastqc -t "$THREADS" -o "$FASTQC_RAW" "$R1" "$R2" >>"$SAMPLE_LOG" 2>&1

    # applies fastp with the specified parameters given by the user to the raw data
    CMD="fastp -i $R1 -I $R2 \
        -o ${TRIM_DIR}/${sample}_R1.trim.fastq.gz \
        -O ${TRIM_DIR}/${sample}_R2.trim.fastq.gz \
        --cut_mean_quality $QMEAN \
        --cut_window_size $WINSIZE \
        --length_required $MINLEN \
        --thread $THREADS \
        --html ${TRIM_DIR}/${sample}_fastp.html \
        --json ${TRIM_DIR}/${sample}_fastp.json"

    if [[ "$ADAPT_DETECT" == "y" ]]; then
        CMD+=" --detect_adapter_for_pe"
    else
        CMD+=" --adapter_sequence $ADAPTER1 --adapter_sequence_r2 $ADAPTER2"
    fi

    eval $CMD >>"$SAMPLE_LOG" 2>&1

    #Applies fastqc to the trimmed files created by fastp
    fastqc -t "$THREADS" -o "$FASTQC_TRIM" \
        "${TRIM_DIR}/${sample}_R1.trim.fastq.gz" \
        "${TRIM_DIR}/${sample}_R2.trim.fastq.gz" >>"$SAMPLE_LOG" 2>&1

    echo "$sample complete." | tee -a "$MASTER_LOG"
done

echo
echo "[6/6] Pipeline completed."
echo "Running MultiQC..."

# Run MultiQC and save results in results/multiqc
multiqc . --outdir results/multiqc

if [[ $? -eq 0 ]]; then
    echo "MultiQC completed successfully."
else
    echo "MultiQC failed. Check for errors."
fi

echo
echo "All tasks finished successfully."
