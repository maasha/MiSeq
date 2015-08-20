# Namespace for MiSeq classes.
module MiSeq
  # Error class for SampleSheet errors.
  SampleSheetError = Class.new(StandardError)

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
end
