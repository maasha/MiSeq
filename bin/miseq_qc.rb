#!/usr/bin/env ruby

# Script that locates all data directories with FASTQ files and ensures that QC
# are run on these - unless already run.

require_relative 'lib/miseq'

SRC = '/disk/orsted/miseq_microbio/'
DST = '/home/microbio/public_html/'

MiSeq::Data.qc(SRC, DST)
