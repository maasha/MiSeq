# Namespace for MiSeq classes.
module MiSeq
  # Error class for QC errors.
  QCError = Class.new(StandardError)

  # Class for running Quality Control (QC) on a directory with FASTQ files from
  # a MiSeq run.
  class QC
    SEQ_DIR   = 'Fastq'
    BP_SCRIPT = 'miseq_qc.bp'

    # Run QC on all dirs in src unless already present in dst.
    def self.run(src, dst)
      fail QCError, "No such directory: #{src}" unless File.directory? src
      fail QCError, "No such directory: #{dst}" unless File.directory? dst

      qc = new(src, dst)
      qc.run
    end

    # Constructor for QC.
    #
    # @param src [String] path to dir with MiSeq runs.
    # @param dst [String] path to analysis dst.
    #
    # @return [QC] Class instance.
    def initialize(src, dst)
      @src    = src
      @dst    = dst
      @logger = MiSeq::Log.new(File.join(@dst, 'miseq_qc.log'))
    end

    # Method to run QC of all MiSeq runs in the dst dir for which no src dir
    # exist with the same basename.
    def run
      qc_dirs.each do |dir|
        dst_dir = File.join(@dst, dir)
        src_dir = File.join(@src, dir)

        @logger.log("QC of #{dst_dir} start")

        Dir.mkdir dst_dir
        sample_dir = File.join(dst_dir, SEQ_DIR)
        FileUtils.ln_s(src_dir, sample_dir)
        files = fastq_files(sample_dir)

        write_sample_file(File.join(dst_dir, 'samples.txt'), files)
        copy_biopieces_script(dst_dir)
        run_biopieces_script(dst_dir)

        @logger.log("QC of #{dst_dir} done")
      end
    end

    private

    # Return a list of all src directories with a YYYY-MM-DD prefix.
    #
    # @return [Array] List of directories.
    def src_dirs
      Dir["#{@src}/*"].select do |file|
        File.directory?(file) && File.basename(file).match(/^\d{4}-\d{2}-\d{2}/)
      end
    end

    # Return a list of all dst directories with a YYYY-MM-DD prefix.
    #
    # @return [Array] List of directories.
    def dst_dirs
      Dir["#{@dst}/*"].select do |file|
        File.directory?(file) && File.basename(file).match(/^\d{4}-\d{2}-\d{2}/)
      end
    end

    # Returns a list of all directories that should be QC'ed.
    #
    # @return [Array] List of sorted directories
    def qc_dirs
      src_dirs.map { |dir| File.basename dir } -
        dst_dirs.map { |dir| File.basename dir }.sort
    end

    # Return a list of all FASTQ files from a director.
    #
    # @param dir [String] Full path to directory
    #
    # @return [Array] List of files
    def fastq_files(dir)
      Dir["#{dir}/*.fastq.gz"].reject { |f| f.match(/Undetermined/) }.sort
    end

    # Write a sample file
    #
    # @param files [String] List of FASTQ files.
    def write_sample_file(sample_file, files)
      samples = extract_sample_names(files)
      read1   = sample_paths(files, '_R1_')
      read2   = sample_paths(files, '_R2_')

      @logger.log("Processing #{samples.size} samples")
      @logger.log("Processing #{read1.size} R1 files")
      @logger.log("Processing #{read2.size} R2 files")

      table = [samples, read1, read2]

      File.open(sample_file, 'w') do |ios|
        table.transpose.each do |row|
          ios.puts row.join("\t")
        end
      end
    end

    # Return a list of sample names from a bunch of FASTQ files.
    #
    # @param files [Array] List of FASTQ files.
    #
    # @raise [MiSeq::QCError] on bad file name format.
    #
    # @return [Array] List of sample names.
    def extract_sample_names(files)
      names = []

      files.each do |file|
        base = File.basename file

        next if base.match(/_R2_/)

        unless base.match(/_L\d{3}_R1_\d{3}\.fastq\.gz$/)
          fail QCError, "Unable to match sample name: #{base}"
        end

        len = '_L001_R1_001.fastq.gz'.length

        names << base[0...-1 * len]
      end

      names
    end

    # Return a list of sample paths matching a given pattern.
    #
    # @param files   [Array]  List of abosolute paths.
    # @param pattern [String] Pattern for matching files.
    #
    # @return [Array] List of relative paths.
    def sample_paths(files, pattern)
      paths = []

      files.each do |file|
        base = File.basename(file)

        base.match(Regexp.new(pattern)) && paths << File.join(SEQ_DIR, base)
      end

      paths
    end

    # Copy the biopieces qc script file to the dst dir.
    #
    # @param dst [String] Destination directory.
    def copy_biopieces_script(dst)
      bin_dir = File.join(File.dirname(__FILE__), '..', '..', 'bin')

      FileUtils.cp(File.join(bin_dir, BP_SCRIPT), dst)
    end

    # Run the Biopieces QC script.
    #
    # @param dst [String] Destination directory.
    def run_biopieces_script(dst)
      `cd #{dst} && nice -n 19 /usr/bin/env ruby #{BP_SCRIPT}`
    end
  end
end
