# Namespace for MiSeq classes.
module MiSeq
  # Error class for Data errors.
  DataError = Class.new(StandardError)

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
end
