version 1.0

import "../../../tasks/broad/Utilities.wdl" as utils
import "../../../tasks/broad/InternalTasks.wdl" as InternalTasks
import "../../../tasks/broad/Qc.wdl" as Qc


## Copyright Broad Institute, 2022
##
## This WDL pipeline implements A CheckFingerprint Task
## It runs the Picard tool 'CheckFingerprint' against a supplied input file (VCF, CRAM, BAM or SAM) using a set of 'fingerprint' genotypes.
## These genotypes can either be generated by pulling them from the (Broad-internal) Mercury Fingerprint Store or be supplied as inputs to the pipeline.
                                                                                                                                                                                                                                                                                                  ##
## Runtime parameters are optimized for Broad's Google Cloud Platform implementation.
## For program versions, see docker containers.
##
## LICENSING :
## This script is released under the WDL source code license (BSD-3) (see LICENSE in
## https://github.com/broadinstitute/wdl). Note however that the programs it calls may
## be subject to different licenses. Users are responsible for checking that they are
## authorized to run all programs before running this script. Please see the docker
## page at https://hub.docker.com/r/broadinstitute/genomes-in-the-cloud/ for detailed
## licensing information pertaining to the included programs.

workflow CheckFingerprint {

  String pipeline_version = "1.0.6"

  input {
    File? input_vcf
    File? input_vcf_index
    File? input_bam
    File? input_bam_index

    # The name of the sample in the input_vcf.  Not required if there is only one sample in the VCF
    String? input_sample_alias

    # If this is true, we will read fingerprints from Mercury
    # Otherwise, we will use the optional input fingerprint VCFs below
    Boolean read_fingerprint_from_mercury = false
    File? fingerprint_genotypes_vcf
    File? fingerprint_genotypes_vcf_index

    String? sample_lsid
    String sample_alias

    String output_basename

    File ref_fasta
    File ref_fasta_index
    File ref_dict

    File haplotype_database_file

    String? environment
    File? vault_token_path
  }

  if (defined(input_vcf) && defined(input_bam)) {
    call utils.ErrorWithMessage as ErrorMessageDoubleInput {
      input:
        message = "input_vcf and input_bam cannot both be defined as input"
    }
  }

  if (read_fingerprint_from_mercury && (!defined(sample_lsid) || !defined(environment) || !defined(vault_token_path))) {
    call utils.ErrorWithMessage as ErrorMessageIncompleteForReadingFromMercury {
      input:
        message = "sample_lsid, environment, and vault_token_path must defined when reading from Mercury"
    }
  }

  # sample_alias may contain spaces, so make a filename-safe version for the downloaded fingerprint file
  call InternalTasks.MakeSafeFilename {
    input:
      name = sample_alias
  }

  if (read_fingerprint_from_mercury) {
    call InternalTasks.DownloadGenotypes {
      input:
        sample_alias = sample_alias,
        sample_lsid = select_first([sample_lsid]),
        output_vcf_base_name = MakeSafeFilename.output_safe_name + ".reference.fingerprint",
        haplotype_database_file = haplotype_database_file,
        ref_fasta = ref_fasta,
        ref_fasta_index = ref_fasta_index,
        ref_dict = ref_dict,
        environment = select_first([environment]),
        vault_token_path = select_first([vault_token_path])
    }
  }

  Boolean fingerprint_downloaded_from_mercury = select_first([DownloadGenotypes.fingerprint_retrieved, false])

  File? fingerprint_vcf_to_use = if (fingerprint_downloaded_from_mercury) then DownloadGenotypes.reference_fingerprint_vcf else fingerprint_genotypes_vcf
  File? fingerprint_vcf_index_to_use = if (fingerprint_downloaded_from_mercury) then DownloadGenotypes.reference_fingerprint_vcf_index else fingerprint_genotypes_vcf_index

  if ((defined(fingerprint_vcf_to_use)) && (defined(input_vcf) || defined(input_bam))) {
    call Qc.CheckFingerprint {
      input:
        input_bam = input_bam,
        input_bam_index = input_bam_index,
        input_vcf = input_vcf,
        input_vcf_index = input_vcf_index,
        input_sample_alias = input_sample_alias,
        genotypes = select_first([fingerprint_vcf_to_use]),
        genotypes_index = fingerprint_vcf_index_to_use,
        expected_sample_alias = sample_alias,
        output_basename = output_basename,
        haplotype_database_file = haplotype_database_file,
        ref_fasta = ref_fasta,
        ref_fasta_index = ref_fasta_index
    }
  }

  output {
    Boolean fingerprint_read_from_mercury = fingerprint_downloaded_from_mercury
    File? reference_fingerprint_vcf = fingerprint_vcf_to_use
    File? reference_fingerprint_vcf_index = fingerprint_vcf_index_to_use
    File? fingerprint_summary_metrics_file = CheckFingerprint.summary_metrics
    File? fingerprint_detail_metrics_file = CheckFingerprint.detail_metrics
    Float? lod_score = CheckFingerprint.lod
  }
  meta {
    allowNestedInputs: true
  }
}
