#!/usr/bin/env ruby

# Script that locates all data directories with FASTQ files and ensures that QC
# are run on these - unless already run.

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..', 'lib')

require 'miseq'

SRC = '/disk/orsted/miseq_microbio/'
DST = '/home/microbio/public_html/'

MiSeq::QC.run(SRC, DST)
