# Namespace for MiSeq classes.
module MiSeq
  # Error class for DataDir errors.
  DataDirError = Class.new(StandardError)

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
end
