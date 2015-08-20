#!/usr/bin/env ruby

# Outputs a table of sample and file names from a directory with MiSeq FASTQ files.

require 'pp'

def find_prefix(files)
  prefix = ""

  hash = Hash.new { |h, k| h[k] = {} }

  files.each do |file|
    file.split(//).each_with_index { |c, i| hash[i][c] = true }
  end

  hash.each_value do |value|
    break if value.size > 1

    prefix << value.first.first
  end

  prefix
end

def find_suffix(files)
  suffix = ""

  hash = Hash.new { |h, k| h[k] = {} }

  files.each do |file|
    file.reverse.split(//).each_with_index { |c, i| hash[i][c] = true }
  end

  hash.each_value do |value|
    break if value.size > 1

    suffix << value.first.first
  end

  suffix.reverse
end

if ARGV.size == 0
  $stderr.puts "Usage: #{File.basename(__FILE__)} <FASTQ files>" if ARGV.size == 0
  exit
end

files = ARGV.dup
files = files.map { |file| File.basename(file) }.select { |file| file.match /_R1_/}.sort

prefix = find_prefix(files)
suffix = find_suffix(files)

$stderr.puts "Prefex: #{prefix}   Suffix: #{suffix}"

puts "# ID Name-match"

files.each do |file|
  sample  = file[prefix.size     ... -1 * suffix.size]
  pattern = file[prefix.size - 1 ..  -1 * suffix.size]

  puts [sample, pattern].join(" ")
end
