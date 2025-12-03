# Project_ibbc_60414
Project made for the UC Introdução à Bioinformática e Biologia Computacional at FCUL


Pipeline for application of FastQC, Fastp and MultiQC to files in the format of _R1.fastq.gz and _R2.fastq.gz.  With additional feature that detects, classifies, logs and separates problematic FASTQ files.

For the correct function of the script it must be run on a tools_qc environment with the tools (fastqc, fastp and multiqc) installed. 

To activate the environment if already installed:
conda activate tools_qc

To create the environment:
conda create -n tools_qc fastqc fastp multiqc -y
conda activate tools_qc


When running main.sh it will create the following folder structure around it:


Project_ibbc_60414/

├── main.sh				← Script file for the entire pipeline

├── data/

│   ├── raw/               ← input FASTQ files

│   ├── trimmed/           ← fastp outputs

├── results/

│   ├── fastqc_raw/        ← FastQC without trimming

│   ├── fastqc_trimmed/    ← FastQC after trimming by fastp

│   ├── multiqc/           ← Final MultiQC report

├── problematic_files		← Files considered problematic

├── logs/                  ← Logs created during the process




It will then ask the user to place the raw FASTQ files in data/raw. For the first run it is necessary to answer no (n) and to close the script, place the files and rerun the script. Afterward it will run the check for problematic files logging and moving the appropriate files to /problematic_files. 

If there are stil valid files the script will continue and prompt the user to input the desired FASTP configuration, while suggesting default parameters that are different from the base fastp default, further changes should be done in the script itself.


Then the following pipeline will be processed by sample pair:

FastQC on raw FASTQ files (output to /results/fastqc_raw)
    ↓
fastp on raw FASTQ files (output to /data/trimmed)
    ↓
FastQC on trimmed files by fastp (output to /results/fastqc_trimmed)
   

After all sample pairs present in data/raw have been processed MultiQC is ran at the project level with it's output in /results/muliqc.

---------------------------------------------------------------------------------------------------------------------------------


The additional routine to separate problematic files first separates files that do not follow the naming format and saves the correct ones in a SAMPLES array to be used later:

sampleName_R1.fastq.gz
sampleName_R2.fastq.gz

The SAMPLES array saves the sample name and the corresponding R1 and R2.

CODE EXCERPT-----------------------------------------------------------------------------------------------------------------

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

------------------------------------------------------------------------------------------------------------------------------




It also checks if only one file of the pair is present, if so it's moved to problematic_files.
This check uses the SAMPLES array and checks every file in the array which could lead to some redundant checks, 
as in when it checks sample1_R1.fastq.gz it verifies if both R1 and R2 are present, and then it does the same check for R2, which in the case of it being correct is redundant.

CODE EXCERPT---------------------------------------------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------------------------------------------------------------



In the same for loop it further checks the validity of the files by using gzip -t  to verify the .gz files without decompressing.

CODE EXCERPT --------------------------------------------------------------------------------------------------------------------------

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

-----------------------------------------------------------------------------------------------------------------------------------------



Each of these actions, file and type of error are logged in a specific file in logs/ .




