#!/usr/bin/env ruby

# Script that locates all subdirectories starting with a number in the src
# specified below. Each of these subdirs are renamed based on information
# located in the SampleSheet.csv file within. Next each directory is packed with
# tar and synchcronized to a remote location.

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..', 'lib')

require 'miseq'

SRC = '/volume1/miseq_data/'
DST = 'microbio@newton:data/'

MiSeq::Data.sync(SRC, DST)
