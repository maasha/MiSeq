# Namespace for MiSeq classes.
module MiSeq
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
end
