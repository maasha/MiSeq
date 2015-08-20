#!/usr/bin/env ruby

# Namespace for MiSeq classes.
module MiSeq
  require 'English'
  require 'pp'

  # Error class for SampleSheet errors.
  SampleSheetError = Class.new(StandardError)

  # Error class for DataDir errors.
  DataDirError = Class.new(StandardError)

  # Error class for Data errors.
  DataError = Class.new(StandardError)

  # Class for parsing the GenerateFASTQRunStatistics.xml file to determine if a
  # MiSeq run has completed.
  class RunStatistics
    # Returns true if the MiSeq run has completed.
    #
    # @param file [String] Path to run statistics file.
    #
    # @return [Boolean]
    def self.complete?(file)
      new(file).complete?
    end

    # Constructor for RunStatistics.
    #
    # @oaram file [String] Path to file.
    #
    # @return [RunStatistics] Class instance.
    def initialize(file)
      @file = file
    end

    # Locates the CompletionTime tag in GenerateFASTQRunStatistics.xml and
    # returns true if found else false.
    #
    # @return [Boolean]
    def complete?
      parse_run_statistics.select { |line| line =~ /CompletionTime/ }.any?
    end

    private

    # Parse RunStatistics file and return a list of lines.
    #
    # @return [Array] List of Samplesheet lines.
    def parse_run_statistics
      return [] unless File.exist? @file

      File.read(@file).split($INPUT_RECORD_SEPARATOR)
    end
  end

  # Class for parsing information from MiSeq Samplesheets.
  class SampleSheet
    # Constructor for SampleSheet.
    #
    # @oaram file [String] Path to Samplesheet file.
    #
    # @return [SampleSheet] Class instance.
    def initialize(file)
      @file = file
    end

    # Extract the Investigator Name from the SampleSheet lines.
    # Any whitespace in the Investigator Name is replaced by underscores.
    #
    # @raise [SampleSheetError] On failing Experiment Name line.
    # @raise [SampleSheetError] On failing Experiment Name field.
    #
    # @return [String] Investigator name.
    def investigator_name
      lines       = parse_samplesheet
      match_lines = lines.select { |line| line =~ /^Investigator Name/ }

      fail SampleSheetError, 'No Investigator Name line' if match_lines.empty?

      fields = match_lines.first.split(',')

      fail SampleSheetError, 'No Investigator Name field' if fields.size != 2

      fields[1].strip.gsub(' ', '_')
    end

    # Extract the Experiment Name from the SampleSheet lines.
    # Any whitespace in the Experiment Name is replaced by underscores.
    #
    # @raise [SampleSheetError] On failing Experiment Name line.
    # @raise [SampleSheetError] On failing Experiment Name field.
    #
    # @return [String] Experiment name.
    def experiment_name
      lines = parse_samplesheet

      match_lines = lines.select { |line| line =~ /^Experiment Name/ }

      fail SampleSheetError, 'No Experiment Name line' if match_lines.empty?

      fields = match_lines.first.split(',')

      fail SampleSheetError, 'No Experiment Name in file' if fields.size != 2

      fields[1].strip.gsub(' ', '_')
    end

    private

    # Parse Samplesheet file and return a list of lines.
    #
    # @raise [SampleSheetError] unless SampleSheet.csv file exist.
    #
    # @return [Array] List of Samplesheet lines.
    def parse_samplesheet
      fail SampleSheetError, "No such file: #{@file}" unless File.exist? @file

      lines = []

      File.open(@file) do |ios|
        ios.each_line { |line| lines << line.chomp }
      end

      lines
    end
  end

  # Class for manipulating a MiSeq data directory.
  class DataDir
    attr_reader :dir

    # Constructor for DataDir class.
    #
    # @param dir [String] Path to MiSeq data dir.
    #
    # @return [DataDir] Class instance.
    def initialize(dir)
      @dir = dir
    end

    # Extract data from a given dir path and return this in ISO 8601 format
    # (YYYY-MM-DD).
    #
    # @raise [DataDirError] On failed extraction.
    #
    # @return [String] ISO 8601 date.
    def date
      date = File.basename(@dir)[0...6]

      fail DataDirError, "Bad date format: #{date}" unless date =~ /^\d{6}$/

      year  = date[0..1].to_i + 2000
      month = date[2..3]
      day   = date[4..5]

      "#{year}-#{month}-#{day}"
    end

    # Rename DataDir.
    #
    # @param new_name [String] New directory name.
    #
    # @raise [DataDirError] If directory already exist.
    def rename(new_name)
      fail DataDirError, "Dir exits: #{new_name}" if File.directory? new_name

      File.rename(@dir, new_name)

      @dir = new_name
    end
  end

  # Class for synchronizing MiSeq data.
  class Data
    # Synchcronize MiSeq data between a specified src dir and dst URL.
    # Prior to synchronization, the subdirectories are given sane names and are
    # packed with tar.
    #
    # @param src [String] Source directory.
    # @param dst [String] Destination URL.
    def self.sync(src, dst)
      data = new(src, dst)
      data.rename
      data.tar
      # data.remove # TODO: untested
      data.sync
    end

    # Constructor for Data class.
    #
    # @param src [String] Source directory.
    # @param dst [String] Destination URL.
    #
    # @return [Data] Class instance.
    def initialize(src, dst)
      @src       = src
      @dst       = dst
      @logger    = MiSeq::Log.new(File.join(@src, 'miseq_sync.log'))
      @new_names = []
    end

    # Rename all MiSeq data dirs based on sane date format and information from
    # SampleSheets.
    def rename
      dirs.each do |dir|
        file_stats   = File.join(dir, 'GenerateFASTQRunStatistics.xml')
        file_samples = File.join(dir, 'SampleSheet.csv')

        next unless MiSeq::RunStatistics.complete?(file_stats)

        dd = MiSeq::DataDir.new(dir)
        ss = MiSeq::SampleSheet.new(file_samples)

        new_name = compile_new_name(dir, dd.date, ss.investigator_name,
                                    ss.experiment_name)

        dd.rename(new_name)

        @logger.log("Renamed #{File.basename(dir)} to " \
                    "#{File.basename(new_name)}")

        @new_names << new_name
      end
    end

    # Back all reanamed dirs with tar.
    #
    # @raise [DataError] if tar file exist.
    # @raise [DataError] if tar fails.
    def tar
      @new_names.each do |dir|
        fail "Tar file exist: #{dir}.tar" if File.exist? "#{dir}.tar"

        cmd = "tar -cf #{dir}.tar #{dir} > /dev/null 2>&1"

        @logger.log("Tar of #{File.basename(dir)} start")

        system(cmd)

        fail DataError, "Command failed: #{cmd}" unless $CHILD_STATUS.success?

        @logger.log("Tar of #{File.basename(dir)} done")
      end
    end

    # # Remove original subdirectories.
    # def remove
    #   @new_names.each do |dir|
    #     # FileUtils.rm_rf dir
    #   end
    # end
    def sync
      log = "#{@src}/rsync.log"
      src = "#{@src}/*.tar"
      cmd = "rsync -Haq #{src} #{@dst} --log-file #{log} --chmod=Fu=rw,og="

      @logger.log('Rsync start')

      system(cmd)

      fail "Command failed: #{cmd}" unless $CHILD_STATUS.success?

      @logger.log('Rsync done')
    end

    private

    # Find MiSeq data dirs in base dir.
    #
    # @return [Array] List of dirs.
    def dirs
      Dir["#{@src}/*"].select { |dir| File.basename(dir) =~ /^\d{6}_/ }
    end

    # Compile a new directory name.
    #
    # @param dir [String] Old directory name.
    # @param date [String] Date.
    # @param investigator_name [String] Investigator name.
    # @param experiment_name [String] Experiment name.
    #
    # @return [String] New directory name.
    def compile_new_name(dir, date, investigor_name, experiment_name)
      path = File.dirname dir

      new_name = [date, investigor_name, experiment_name].join('_')

      File.join(path, new_name)
    end
  end

  # Class for logging messages.
  class Log
    # Constructor for Log class.
    #
    # @param file [String] Path to log file.
    def initialize(file)
      @file = file
    end

    # Write time stamp and message to log file.
    #
    # @param msg [String] Message to write.
    def log(msg)
      File.open(@file, 'a') do |ios|
        ios.puts [Time.now, msg].join("\t")
      end
    end
  end
end
