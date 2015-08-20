# Namespace for MiSeq classes.
module MiSeq
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
