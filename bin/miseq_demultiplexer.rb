#!/usr/bin/env ruby

require 'biopieces'
require 'optparse'
require 'csv'
require 'set'
require 'google_hash'

USAGE = <<USAGE
  This program demultiplexes Illumina Paired data given a samples file and four
  FASTQ files containing forward and reverse index data and forward and reverse
  read data.

  The samples file consists of three tab-separated columns: sample_id, forward
  index, reverse index).

  The FASTQ files are generated by the Illumina MiSeq instrument by adding the
  following key:

    <add key="CreateFastqForIndexReads" value="1">

  To the `MiSeq Reporter.exe.config` file located in the `MiSeq Reporter`
  installation folder, `C:\\Illumina\\MiSeqReporter` and restarting the
  `MiSeq Reporter` service. See the MiSeq Reporter User Guide page 29:

  http://support.illumina.com/downloads/miseq_reporter_user_guide_15042295.html

  Thus Basecalling using a SampleSheet.csv containing a single entry `Data` with
  no index information will generate the following files:

    Data_S1_L001_I1_001.fastq.gz
    Data_S1_L001_I2_001.fastq.gz
    Data_S1_L001_R1_001.fastq.gz
    Data_S1_L001_R2_001.fastq.gz
    Undetermined_S0_L001_I1_001.fastq.gz
    Undetermined_S0_L001_I2_001.fastq.gz
    Undetermined_S0_L001_R1_001.fastq.gz
    Undetermined_S0_L001_R2_001.fastq.gz

  Demultiplexing will generate file pairs according to the sample information
  in the samples file and input file suffix, one pair per sample, and these
  will be output to the output directory. Also a file pair with undetermined
  reads are created where the index sequence is appended to the sequence name.

  It is possible to allow up to three mismatches per index. Also, read pairs are
  filtered if either of the indexes have a mean quality score below a given
  threshold or any single position in the index have a quality score below a
  given theshold.

  Finally, a log file `Demultiplex.log` is output containing the status of the
  demultiplexing process along with a list of the samples ids and unique index1
  and index2 sequences.

  Usage: #{File.basename(__FILE__)} [options] <FASTQ files>

  Example: #{File.basename(__FILE__)} -m samples.tsv Data*.fastq.gz

  Options:
USAGE

# Class containing methods for demultiplexing MiSeq sequences.
class Demultiplexer
  attr_reader :status

  # Public: Class method to run demultiplexing of MiSeq sequences.
  #
  # fastq_files - Array with paths to FASTQ files.
  # options     - Options Hash.
  #               :verbose        - Verbose flag (default: false).
  #               :mismatches_max - Integer value indicating max mismatches
  #                                 (default: 0).
  #               :samples_file   - String with path to samples file.
  #               :revcomp_index1 - Flag indicating that index1 should be
  #                                 reverse-complemented (default: false).
  #               :revcomp_index2 - Flag indicating that index2 should be
  #                                 reverse-complemented (default: false).
  #               :output_dir     - String with output directory (optional).
  #               :scores_min     - An Integer representing the Phred score
  #                                 minimum, such that a reads is dropped if a
  #                                 single position in the index contain a
  #                                 score below this value (default: 16).
  #               :scores_mean=>  - An Integer representing the mean Phread
  #                                 score, such that a read is dropped if the
  #                                 mean quality score is below this value
  #                                 (default: 16).
  #
  # Examples
  #
  #   Demultiplexer.run(['I1.fq', 'I2.fq', 'R1.fq', 'R2.fq'], \
  #     samples_file: 'samples.txt')
  #   # => <Demultiplexer>
  #
  # Returns Demultiplexer object
  def self.run(fastq_files, options)
    log_file      = File.join(options[:output_dir], 'Demultiplex.log')
    demultiplexer = new(fastq_files, options)
    Screen.clear if options[:verbose]
    demultiplexer.demultiplex
    puts demultiplexer.status if options[:verbose]
    demultiplexer.status.save(log_file)
  end

  # Constructor method for Demultiplexer object.
  #
  # fastq_files - Array with paths to FASTQ files.
  # options     - Options Hash.
  #               :verbose        - Verbose flag (default: false).
  #               :mismatches_max - Integer value indicating max mismatches
  #                                 (default: 0).
  #               :samples_file   - String with path to samples file.
  #               :revcomp_index1 - Flag indicating that index1 should be
  #                                 reverse-complemented (default: false).
  #               :revcomp_index2 - Flag indicating that index2 should be
  #                                 reverse-complemented (default: false).
  #               :output_dir     - String with output directory (optional).
  #               :scores_min     - An Integer representing the Phred score
  #                                 minimum, such that a reads is dropped if a
  #                                 single position in the index contain a
  #                                 score below this value (default: 16).
  #               :scores_mean=>  - An Integer representing the mean Phread
  #                                 score, such that a read is dropped if the
  #                                 mean quality score is below this value
  #                                 (default: 16).
  #
  # Returns Demultiplexer object
  def initialize(fastq_files, options)
    @options      = options
    @samples      = SampleReader.read(options[:samples_file],
                                      options[:revcomp_index1],
                                      options[:revcomp_index2])
    @undetermined = @samples.size + 1
    @index_hash   = IndexBuilder.build(@samples, options[:mismatches_max])
    @data_io      = DataIO.new(@samples, fastq_files, options[:compress],
                               options[:output_dir])
    @status       = Status.new
  end

  # Method to demultiplex reads according the index. This is done by
  # simultaniously read-opening all input files (forward and reverse index
  # files and forward and reverse read files) and read one entry from each.
  # Such four entries we call a set of entries. If the quality scores from
  # either index1 or index2 fails the criteria for mean and min required
  # quality the set is skipped. In the combined indexes are found in the
  # search index, then the reads are writting to files according to the sample
  # information in the search index. If the combined indexes are not found,
  # then the reads have their names appended with the index sequences and the
  # reads are written to the Undertermined files.
  #
  # Returns nothing.
  def demultiplex
    @data_io.open_input_files do |ios_in|
      @data_io.open_output_files do |ios_out|
        ios_in.each do |index1, index2, read1, read2|
          @status.count += 2
          puts(@status) if @options[:verbose] &&
                                           (@status.count % 1_000) == 0

          next unless index_qual_ok?(index1, index2)

          match_index(ios_out, index1, index2, read1, read2)

          # break if @status.count == 100_000
        end
      end
    end
  end

  private

  # Method that matches the combined index1 and index2 sequences against the
  # search index. In case of a match the reads are written to file according to
  # the information in the search index, otherwise the reads will have thier
  # names appended with the index sequences and they will be written to the
  # Undetermined files.
  #
  # ios_out - DataIO object with an accessor method for file output handles.
  # index1  - Seq object with index1.
  # index2  - Seq object with index2.
  # read1   - Seq object with read1.
  # read2   - Seq object with read2.
  #
  # Returns nothing.
  def match_index(ios_out, index1, index2, read1, read2)
    if (sample_id = @index_hash["#{index1.seq}#{index2.seq}".hash])
      write_match(ios_out, sample_id, read1, read2)
    else
      write_undetermined(ios_out, index1, index2, read1, read2)
    end
  end

  # Method that writes a index match to file according to the information in
  # the search index.
  #
  # ios_out - DataIO object with an accessor method for file output handles.
  # read1   - Seq object with read1.
  # read2   - Seq object with read2.
  #
  # Returns nothing.
  def write_match(ios_out, sample_id, read1, read2)
    @status.match += 2
    io_forward, io_reverse = ios_out[sample_id]

    io_forward.puts read1.to_fastq
    io_reverse.puts read2.to_fastq
  end

  # Method that appends the read names with the index sequences and writes
  # the reads to the Undetermined files.
  #
  # ios_out - DataIO object with an accessor method for file output handles.
  # index1  - Seq object with index1.
  # index2  - Seq object with index2.
  # read1   - Seq object with read1.
  # read2   - Seq object with read2.
  #
  # Returns nothing.
  def write_undetermined(ios_out, index1, index2, read1, read2)
    @status.undetermined += 2
    read1.seq_name = "#{read1.seq_name} #{index1.seq}"
    read2.seq_name = "#{read2.seq_name} #{index2.seq}"

    io_forward, io_reverse = ios_out[@undetermined]
    io_forward.puts read1.to_fastq
    io_reverse.puts read2.to_fastq
  end

  # Method to check the quality scores of the given indexes.
  # If the mean score is higher than @options[:scores_mean] or
  # if the min score is higher than @options[:scores_min] then
  # the indexes are OK.
  #
  # index1 - Index1 Seq object.
  # index2 - Index2 Seq object.
  #
  # Returns true if quality OK, else false.
  def index_qual_ok?(index1, index2)
    index_qual_mean_ok?(index1, index2) &&
      index_qual_min_ok?(index1, index2)
  end

  # Method to check the mean quality scores of the given indexes.
  # If the mean score is higher than @options[:scores_mean] the
  # indexes are OK.
  #
  # index1 - Index1 Seq object.
  # index2 - Index2 Seq object.
  #
  # Returns true if quality mean OK, else false.
  def index_qual_mean_ok?(index1, index2)
    if index1.scores_mean < @options[:scores_mean]
      @status.index1_bad_mean += 2
      return false
    elsif index2.scores_mean < @options[:scores_mean]
      @status.index2_bad_mean += 2
      return false
    end

    true
  end

  # Method to check the min quality scores of the given indexes.
  # If the min score is higher than @options[:scores_min] the
  # indexes are OK.
  #
  # index1 - Index1 Seq object.
  # index2 - Index2 Seq object.
  #
  # Returns true if quality min OK, else false.
  def index_qual_min_ok?(index1, index2)
    if index1.scores_min < @options[:scores_min]
      @status.index1_bad_min += 2
      return false
    elsif index2.scores_min < @options[:scores_min]
      @status.index2_bad_min += 2
      return false
    end

    true
  end

  # Method that iterates over @samples and compiles a sorted Array with all
  # unique index1 sequences.
  #
  # Returns Array with uniq index1 sequences.
  def uniq_index1
    @status.index1 = @samples.each_with_object(SortedSet.new) do |a, e|
      a << e.index1
    end.to_a
  end

  # Method that iterates over @samples and compiles a sorted Array with all
  # unique index2 sequences.
  #
  # Returns Array with uniq index2 sequences.
  def uniq_index2
    @status.index2 = @samples.each_with_object(SortedSet.new) do |a, e|
      a << e.index2
    end.to_a
  end
end

# Class containing methods for reading and checking sample information.
class SampleReader
  # Class method that reads sample information from a samples file, which
  # consists of ASCII text in three tab separated columns: The first column is
  # the sample_id, the second column is index1 and the third column is index2.
  #
  # If revcomp1 or revcomp2 is set then index1 and index2 are
  # reverse-complemented accordingly.
  #
  # file     - String with path to sample file.
  # revcomp1 - Flag indicating that index1 should be reverse-complemented.
  # revcomp2 - Flag indicating that index2 should be reverse-complemented.
  #
  # Examples
  #
  #   SampleReader.read("samples.txt", false, false)
  #   # => [<Sample>, <Sample>, <Sample> ...]
  #
  # Returns an Array of Sample objects.
  def self.read(file, revcomp1, revcomp2)
    sample_reader = new(revcomp1, revcomp2)
    sample_reader.samples_parse(file)
  end

  # Constructor method for SampleReader object. The given revcomp1 and revcomp2
  # flags are stored as instance variables.
  #
  # revcomp1 - Flag indicating that index1 should be reverse-complemented.
  # revcomp2 - Flag indicating that index2 should be reverse-complemented.
  #
  # Examples
  #
  #   SampleReader.new(false, false)
  #   # => <SampleReader>
  #
  # Returns SampleReader object.
  def initialize(revcomp1, revcomp2)
    @revcomp1 = revcomp1
    @revcomp2 = revcomp2
  end

  # Method that reads sample information from a samples file, which consists
  # of ASCII text in three tab separated columns: The first column is the
  # sample_id, the second column is index1 and the third column is index2.
  #
  # file - String with path to sample file.
  #
  # Examples
  #
  #   samples_parse("samples.txt")
  #   # => [<Sample>, <Sample>, <Sample> ...]
  #
  # Returns an Array of Sample objects.
  def samples_parse(file)
    samples = samples_read(file)
    samples_reverse_complement(samples)
    errors = []
    errors.push(*samples_check_index_combo(samples))
    errors.push(*samples_check_uniq_id(samples))

    unless errors.empty?
      pp errors
      fail 'errors found in sample file.'
    end

    samples
  end

  private

  # Method that reads sample information form a samples file, which consists
  # of ASCII text in three tab separated columns: The first column is the
  # sample_id, the second column is index1 and the third column is index2.
  #
  # If @options[:revcomp_index1] or @options[:revcomp_index2] is set then
  # index1 and index2 are reverse-complemented accordingly.
  #
  # file - String with path to sample file.
  #
  # Examples
  #
  #   samples_read("samples.txt")
  #   # => [<Sample>, <Sample>, <Sample> ...]
  #
  # Returns an Array of Sample objects.
  def samples_read(file)
    samples = []

    CSV.read(file, col_sep: "\t").each do |id, index1, index2|
      samples << Sample.new(id, index1, index2)
    end

    samples
  end

  # Method that iterates over the a given Array of sample Objects, and if
  # @options[:revcomp_index1] or @options[:revcomp_index2] is set then
  # index1 and index2 are reverse-complemented accordingly.
  #
  # samples - Array of Sample objects.
  #
  # Returns nothing.
  def samples_reverse_complement(samples)
    samples.each do |sample|
      sample.index1 = index_reverse_complement(sample.index1) if @revcomp1
      sample.index2 = index_reverse_complement(sample.index2) if @revcomp2
    end
  end

  # Method that reverse-complements a given index sequence.
  #
  # index - Index String.
  #
  # Returns reverse-complemented index String.
  def index_reverse_complement(index)
    BioPieces::Seq.new(seq: index, type: :dna).reverse.complement.seq
  end

  # Method that iterates over the a given Array of sample Objects, and if
  # the combination of index1 and index2 is non-unique an error is pushed
  # on an error Array.
  #
  # samples - Array of Sample objects.
  #
  # Returns an Array of found errors.
  def samples_check_index_combo(samples)
    errors = []
    lookup = {}

    samples.each do |sample|
      if (id2 = lookup["#{sample.index1}#{sample.index2}"])
        errors << ['Samples with same index combo', sample.id, id2].join("\t")
      else
        lookup["#{sample.index1}#{sample.index2}"] = sample.id
      end
    end

    errors
  end

  # Method that iterates over the a given Array of sample Objects, and if
  # a sample id is non-unique an error is pushed  on an error Array.
  #
  # samples - Array of Sample objects.
  #
  # Returns an Array of found errors.
  def samples_check_uniq_id(samples)
    errors = []
    lookup = Set.new

    samples.each do |sample|
      if lookup.include? sample.id
        errors << ['Non-unique sample id', sample.id].join("\t")
      end

      lookup << sample.id
    end

    errors
  end

  # Struct for holding sample information.
  #
  # id     - Sample id.
  # index1 - Index1 sequence.
  # index2 - Index2 sequence.
  #
  # Examples
  #
  #   Sample.new("test1", "atcg", "gcta")
  #     # => <Sample>
  #
  # Returns Sample object.
  Sample = Struct.new(:id, :index1, :index2)
end

# Class containing methods for building an search index.
class IndexBuilder
  # Class method that build a search index from a given Array of samples.
  #
  # samples - Array of samples (Sample objects with id, index1 and index2).
  #
  # Examples
  #
  #   IndexBuilder.build(samples)
  #     # => <Google Hash>
  #
  # Returns a Google Hash where the key is the index and the value is the TODO
  def self.build(samples, mismatches_max)
    index_builder = new(samples, mismatches_max)
    index_hash    = index_builder.index_init
    index_builder.index_populate(index_hash)
  end

  # Constructor method for IndexBuilder object. The given Array of samples and
  # mismatches_max are saved as an instance variable.
  #
  # samples        - Array of Sample objects.
  # mismatches_max - Integer denoting the maximum number of misses allowed in
  #                  an index sequence.
  #
  # Examples
  #
  #   IndexBuilder.new(samples, 2)
  #     # => <IndexBuilder>
  #
  # Returns an IndexBuilder object.
  def initialize(samples, mismatches_max)
    @samples        = samples
    @mismatches_max = mismatches_max
  end

  # Method to initialize the index. If @mismatches_max is <= then
  # GoogleHashSparseLongToInt is used else GoogleHashDenseLongToInt due to
  # memory and performance.
  #
  # Returns a Google Hash.
  def index_init
    if @mismatches_max <= 1
      index_hash = GoogleHashSparseLongToInt.new
    else
      index_hash = GoogleHashDenseLongToInt.new
    end

    index_hash
  end

  # Method to populate the index.
  #
  # index_hash - Google Hash with initialized index.
  #
  # Returns a Google Hash.
  def index_populate(index_hash)
    @samples.each_with_index do |sample, i|
      index_list1 = permutate([sample.index1], @mismatches_max)
      index_list2 = permutate([sample.index2], @mismatches_max)

      # index_check_list_sizes(index_list1, index_list2)

      index_list1.product(index_list2).each do |index1, index2|
        key = "#{index1}#{index2}".hash

        index_check_existing(index_hash, key)

        index_hash[key] = i
      end
    end

    index_hash
  end

  private

  # Method to check if two index lists differ in size, if so an exception is
  # raised.
  #
  # index_list1 - Array with index1
  # index_list2 - Array with index2
  #
  # Returns nothing.
  def index_check_list_sizes(index_list1, index_list2)
    return if index_list1.size == index_list2.size

    fail "Permutated list sizes differ: \
    #{index_list1.size} != #{index_list2.size}"
  end

  # Method to check if a index key already exists in the index, and if so an
  # exception is raised.
  #
  # index_hash - Google Hash with index
  # key        - Integer from Google Hash's #hash method
  #
  # Returns nothing.
  def index_check_existing(index_hash, key)
    return unless index_hash[key]

    fail "Index combo of #{index1} and #{index2} already exists for \
         sample id: #{@samples[index_hash[key]].id} and #{sample.id}"
  end

  # Method that for each word in a given Array of word permutates each word a
  # given number (permuate) of times using a given alphabet, such that an Array
  # of words with all possible combinations is returned.
  #
  # list     - Array of words (Strings) to permutate.
  # permuate - Number of permutations (Integer).
  # alphabet - String with alphabet used for permutation.
  #
  # Examples
  #
  #   permutate(["AA"], 1, "ATCG")
  #   # => ["AA", "TA", "CA", "GA", "AA", "AT", "AC, "AG"]
  #
  # Returns an Array with permutated words (Strings).
  def permutate(list, permutations = 2, alphabet = 'ATCG')
    permutations.times do
      set = list.each_with_object(Set.new) { |e, a| a.add(e.to_sym) }

      list.each do |word|
        new_words = permutate_word(word, alphabet)
        new_words.map { |new_word| set.add(new_word.to_sym) }
      end

      list = set.map(&:to_s)
    end

    list
  end

  # Method that permutates a given word using a given alphabet, such that an
  # Array of words with all possible combinations is returned.
  #
  # word     - String with word to permutate.
  # alphabet - String with alphabet used for permutation.
  #
  # Examples
  #
  #   permutate("AA", "ATCG")
  #   # => ["AA", "TA", "CA", "GA", "AA", "AT", "AC, "AG"]
  #
  # Returns an Array with permutated words (Strings).
  def permutate_word(word, alphabet)
    new_words = []

    (0...word.size).each do |pos|
      alphabet.each_char do |char|
        new_words << "#{word[0...pos]}#{char}#{word[pos + 1..-1]}"
      end
    end

    new_words
  end
end

# Class containing methods for reading and write FASTQ data files.
class DataIO
  def initialize(samples, fastq_files, compress, output_dir)
    @samples      = samples
    @compress     = compress
    @output_dir   = output_dir
    @suffix1      = extract_suffix(fastq_files.grep(/_R1_/).first)
    @suffix2      = extract_suffix(fastq_files.grep(/_R2_/).first)
    @input_files  = identify_input_files(fastq_files)
    @undetermined = @samples.size + 1
    @file_hash    = nil
  end

  # Method that extracts the Sample, Lane, Region information from a given file.
  #
  # file - String with file name.
  #
  # Examples
  #
  #   extract_suffix("Sample1_S1_L001_R1_001.fastq.gz")
  #   # => "_S1_L001_R1_001"
  #
  # Returns String with SLR info.
  def extract_suffix(file)
    if file =~ /.+(_S\d_L\d{3}_R[12]_\d{3}).+$/
      slr = Regexp.last_match(1)
    else
      fail "Unable to parse file SLR from: #{file}"
    end

    append_suffix(slr)
  end

  # Method that appends a file suffix to a given Sample, Lane, Region
  # information String based on the @options[:compress] option. The
  # file suffix can be either ".fastq.gz", ".fastq.bz2", or ".fastq".
  #
  # slr - String Sample, Lane, Region information.
  #
  # Examples
  #
  #   append_suffix("_S1_L001_R1_001")
  #   # => "_S1_L001_R1_001.fastq.gz"
  #
  # Returns String with SLR info and file suffix.
  def append_suffix(slr)
    case @compress
    when /gzip/
      slr << '.fastq.gz'
    when /bzip2/
      slr << '.fastq.bz2'
    else
      slr << '.fastq'
    end

    slr
  end

  # Method identify the different input files from a given Array of FASTQ files.
  # The forward index file contains a _I1_, the reverse index file contains a
  # _I2_, the forward read file contains a _R1_ and finally, the reverse read
  # file contain a _R2_.
  #
  # fastq_files - Array with FASTQ files (Strings).
  #
  # Returns an Array with input files (Strings).
  def identify_input_files(fastq_files)
    input_files = []

    input_files << fastq_files.grep(/_I1_/).first
    input_files << fastq_files.grep(/_I2_/).first
    input_files << fastq_files.grep(/_R1_/).first
    input_files << fastq_files.grep(/_R2_/).first

    input_files
  end

  # Method that opens the @input_files for reading.
  #
  # input_files - Array with input file paths.
  #
  # Returns an Array with IO objects (file handles).
  def open_input_files
    @file_ios = []

    @input_files.each do |input_file|
      @file_ios << BioPieces::Fastq.open(input_file)
    end

    yield self
  ensure
    close_input_files
  end

  # Method that closes open input files.
  #
  # Returns nothing.
  def close_input_files
    @file_ios.map(&:close)
  end

  # Method that reads a Seq entry from each of the file handles in the
  # @file_ios Array. Iteration stops when no more Seq entries are found.
  #
  # Yields an Array with 4 Seq objects.
  #
  # Returns nothing
  def each
    loop do
      entries = @file_ios.each_with_object([]) { |e, a| a << e.next_entry }

      break if entries.compact.size != 4

      yield entries
    end
  end

  # Method that opens the output files for writing.
  #
  # Yeilds a Hash with an incrementing index as keys, and a tuple of file
  # handles as values.
  def open_output_files
    @file_hash = {}
    comp       = @compress

    @file_hash.merge!(open_output_files_samples(comp))
    @file_hash.merge!(open_output_files_undet(comp))

    yield self
  ensure
    close_output_files
  end

  def close_output_files
    @file_hash.each_value { |value| value.map(&:close) }
  end

  # Getter method that returns a tuple of file handles from @file_hash when
  # given a key.
  #
  # key - Key used to lookup
  #
  # Returns Array with a tuple of IO objects.
  def [](key)
    @file_hash[key]
  end

  # Method that opens the sample output files for writing.
  #
  # comp - Symbol with type of output compression.
  #
  # Returns a Hash with an incrementing index as keys, and a tuple of file
  # handles as values.
  def open_output_files_samples(comp)
    file_hash = {}

    @samples.each_with_index do |sample, i|
      file_forward = File.join(@output_dir, "#{sample.id}#{@suffix1}")
      file_reverse = File.join(@output_dir, "#{sample.id}#{@suffix2}")
      io_forward   = BioPieces::Fastq.open(file_forward, 'w', compress: comp)
      io_reverse   = BioPieces::Fastq.open(file_reverse, 'w', compress: comp)
      file_hash[i] = [io_forward, io_reverse]
    end

    file_hash
  end

  # Method that opens the undertermined output files for writing.
  #
  # comp - Symbol with type of output compression.
  #
  # Returns a Hash with an incrementing index as keys, and a tuple of file
  # handles as values.
  def open_output_files_undet(comp)
    file_hash    = {}
    file_forward = File.join(@output_dir, "Undetermined#{@suffix1}")
    file_reverse = File.join(@output_dir, "Undetermined#{@suffix2}")
    io_forward   = BioPieces::Fastq.open(file_forward, 'w', compress: comp)
    io_reverse   = BioPieces::Fastq.open(file_reverse, 'w', compress: comp)
    file_hash[@undetermined] = [io_forward, io_reverse]

    file_hash
  end
end

# Class containing methods to records demultiplexing status.
class Status
  attr_accessor :count, :match, :undetermined, :index1_bad_mean,
                :index2_bad_mean, :index1_bad_min, :index2_bad_min
  # Method to initialize a Status object, which contains the following instance
  # variables initialized to 0:
  #
  #   @count           - Number or reads.
  #   @match           - Number of reads found in index.
  #   @undetermined    - Number of reads not found in index.
  #   @index1_bad_mean - Number of reads dropped due to bad mean in index1.
  #   @index2_bad_mean - Number of reads dropped due to bad mean in index2.
  #   @index1_bad_min  - Number of reads dropped due to bad min in index1.
  #   @index2_bad_min  - Number of reads dropped due to bad min in index2.
  #
  # Examples
  #
  #   Status.new
  #   # => <Status>
  #
  # Returns a Status object.
  def initialize
    @count           = 0
    @match           = 0
    @undetermined    = 0
    @index1_bad_mean = 0
    @index2_bad_mean = 0
    @index1_bad_min  = 0
    @index2_bad_min  = 0
    @time_start      = Time.now
  end

  # Method to format a String from a Status object. This is done by adding the
  # relevant instance variables to a Hash and return this as an YAML String.
  #
  # Returns a YAML String.
  def to_s
    { count:                @count,
      match:                @match,
      undetermined:         @undetermined,
      undetermined_percent: undetermined_percent,
      index1_bad_mean:      @index1_bad_mean,
      index2_bad_mean:      @index2_bad_mean,
      index1_bad_min:       @index1_bad_min,
      index2_bad_min:       @index2_bad_min,
      time:                 time }.to_yaml
  end

  # Method that calculate the percentage of undetermined reads.
  #
  # Returns a Float with the percentage of undetermined reads.
  def undetermined_percent
    (100 * @undetermined / @count.to_f).round(1)
  end

  # Method that calculates the elapsed time and formats a nice Time String.
  #
  # Returns String with elapsed time.
  def time
    time_elapsed = Time.now - @time_start
    (Time.mktime(0) + time_elapsed).strftime('%H:%M:%S')
  end

  # Method to save stats to the log file 'Demultiplex.log' in the output
  # directory.
  #
  # Returns nothing.
  def save(file)
    @stats[:sample_id] = @samples.map(&:id)

    @stats[:index1] = uniq_index1
    @stats[:index2] = uniq_index2

    File.open(file, 'w') do |ios|
      ios.puts @status
    end
  end
end

# Module containing class methods for clearing and resetting a terminal screen.
module Screen
  # Method that uses console code to clear the screen.
  #
  # Returns nothing.
  def self.clear
    print "\e[H\e[2J"
  end

  # Method that uses console code to move cursor to 1,1 coordinate.
  #
  # Returns nothing.
  def self.reset
    print "\e[1;1H"
  end
end

DEFAULT_SCORE_MIN  = 16
DEFAULT_SCORE_MEAN = 16
DEFAULT_MISMATCHES = 1

ARGV << '-h' if ARGV.empty?

options = {}

OptionParser.new do |opts|
  opts.banner = USAGE

  opts.on('-h', '--help', 'Display this screen') do
    $stderr.puts opts
    exit
  end

  opts.on('-s', '--samples_file <file>', String, 'Path to samples file') do |o|
    options[:samples_file] = o
  end

  opts.on('-m', '--mismatches_max <uint>', Integer, "Maximum mismatches_max \
    allowed (default=#{DEFAULT_MISMATCHES})") do |o|
    options[:mismatches_max] = o
  end

  opts.on('--revcomp_index1', 'Reverse complement index1') do |o|
    options[:revcomp_index1] = o
  end

  opts.on('--revcomp_index2', 'Reverse complement index2') do |o|
    options[:revcomp_index2] = o
  end

  opts.on('--scores_min <uint>', Integer, "Drop reads if a single position in \
    the index have a quality score below scores_min \
    (default=#{DEFAULT_SCORE_MIN})") do |o|
    options[:scores_min] = o
  end

  opts.on('--scores_mean <uint>', Integer, "Drop reads if the mean index \
    quality score is below scores_mean (default=#{DEFAULT_SCORE_MEAN})") do |o|
    options[:scores_mean] = o
  end

  opts.on('-o', '--output_dir <dir>', String, 'Output directory') do |o|
    options[:output_dir] = o
  end

  opts.on('-c', '--compress <gzip|bzip2>', String, 'Compress output using \
    gzip or bzip2 (default=<no compression>)') do |o|
    options[:compress] = o.to_sym
  end

  opts.on('-v', '--verbose', 'Verbose output') do |o|
    options[:verbose] = o
  end
end.parse!

options[:mismatches_max] ||= DEFAULT_MISMATCHES
options[:scores_min]     ||= DEFAULT_SCORE_MIN
options[:scores_mean]    ||= DEFAULT_SCORE_MEAN
options[:output_dir]     ||= Dir.pwd

Dir.mkdir options[:output_dir] unless File.directory? options[:output_dir]

unless options[:samples_file]
  fail OptionParser::MissingArgument, 'No samples_file specified.'
end

unless File.file? options[:samples_file]
  fail OptionParser::InvalidArgument, "No such file: #{options[:samples_file]}"
end

unless options[:mismatches_max] >= 0
  fail OptionParser::InvalidArgument,
       "mismatches_max must be >= 0 - not #{options[:mismatches_max]}"
end

unless options[:mismatches_max] <= 3
  fail OptionParser::InvalidArgument,
       "mismatches_max must be <= 3 - not #{options[:mismatches_max]}"
end

unless options[:scores_min] >= 0
  fail OptionParser::InvalidArgument,
       "scores_min must be >= 0 - not #{options[:scores_min]}"
end

unless options[:scores_min] <= 40
  fail OptionParser::InvalidArgument,
       "scores_min must be <= 40 - not #{options[:scores_min]}"
end

unless options[:scores_mean] >= 0
  fail OptionParser::InvalidArgument,
       "scores_mean must be >= 0 - not #{options[:scores_mean]}"
end

unless options[:scores_mean] <= 40
  fail OptionParser::InvalidArgument,
       "scores_mean must be <= 40 - not #{options[:scores_mean]}"
end

if options[:compress]
  unless options[:compress] =~ /^gzip|bzip2$/
    fail OptionParser::InvalidArgument,
         "Bad argument to --compress: #{options[:compress]}"
  end
end

fastq_files = ARGV.dup

if fastq_files.size != 4
  fail ArgumentError, "Expected 4 input files - not #{fastq_files.size}"
end

Demultiplexer.run(fastq_files, options)
