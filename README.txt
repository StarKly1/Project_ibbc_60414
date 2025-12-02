
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

If there are stil valid files the script will continue and prompt the user to input the desired FASTP configuration, while suggesting default parameters that are different from the base fastp default.


Then the following pipeline will be processed by sample pair:

FastQC on raw FASTQ files (output to /results/fastqc_raw)
    ↓
fastp on raw FASTQ files (output to /data/trimmed)
    ↓
FastQC on trimmed files by fastp (output to /results/fastqc_trimmed)
   

After all sample pairs present in data/raw have been processed MultiQC is ran at the project level with it's output in /results/muliqc.

---------------------------------------------------------------------------------------------------------------------------------


The additional routine to separate problematic files first separates files that do not follow the naming format:

sampleName_R1.fastq.gz
sampleName_R2.fastq.gz

It also checks if only one file of the pair is present, if so it's moved to problematic_files.

It further checks the validity of the files by using gzip -t.

Each of these actions, file and type of error are logged in a specific file in logs/ .




