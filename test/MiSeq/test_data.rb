$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..', '..')

require 'test/helper'
require 'lib/miseq'

# rubocop:disable ClassLength

# Test class for MiSeq.
class TestData < Test::Unit::TestCase
  def setup
    @dir_src = Dir.mktmpdir('miseq_src')
    @dir_dst = Dir.mktmpdir('miseq_dst')

    setup_dir_src_ok
    setup_dir_src_unfinished
  end

  def setup_dir_src_ok
    @dir_src_ok = Dir.mktmpdir('miseq_src_ok')

    3.times do |i|
      data_dir     = File.join(@dir_src_ok, ('130400'.to_i + i).to_s + '_test')
      file_stats   = File.join(data_dir, 'GenerateFASTQRunStatistics.xml')
      file_samples = File.join(data_dir, 'SampleSheet.csv')

      Dir.mkdir(data_dir)

      File.open(file_stats, 'w') { |ios| ios.puts "  <CompletionTime>#{i}" }

      File.open(file_samples, 'w') do |ios|
        ios.puts "Investigator Name, Martin Hansen #{i}"
        ios.puts "Experiment Name, Big Bang #{i}"
      end
    end
  end

  def setup_dir_src_unfinished
    @dir_src_unfinished = Dir.mktmpdir('miseq_src_unfinished')

    3.times do |i|
      data_dir     = File.join(@dir_src_unfinished,
                               ('130400'.to_i + i).to_s + '_test')
      file_stats   = File.join(data_dir, 'GenerateFASTQRunStatistics.xml')
      file_samples = File.join(data_dir, 'SampleSheet.csv')

      Dir.mkdir(data_dir)

      if i != 2
        File.open(file_stats, 'w') { |ios| ios.puts "  <CompletionTime>#{i}" }
      end

      File.open(file_samples, 'w') do |ios|
        ios.puts "Investigator Name, Martin Hansen #{i}"
        ios.puts "Experiment Name, Big Bang #{i}"
      end
    end
  end

  def teardown
    FileUtils.rm_rf @dir_src
  end

  test 'Data#sync works OK' do
    MiSeq::Data.sync(@dir_src_ok, @dir_dst)

    file1 = '2013-04-00_Martin_Hansen_0_Big_Bang_0.tar'
    file2 = '2013-04-01_Martin_Hansen_1_Big_Bang_1.tar'
    file3 = '2013-04-02_Martin_Hansen_2_Big_Bang_2.tar'

    assert_true(File.exist? File.join(@dir_dst, file1))
    assert_true(File.exist? File.join(@dir_dst, file2))
    assert_true(File.exist? File.join(@dir_dst, file3))
  end

  test 'Data#sync dst permissions are OK' do
    MiSeq::Data.sync(@dir_src_ok, @dir_dst)

    file = '2013-04-00_Martin_Hansen_0_Big_Bang_0.tar'
    dst  = File.join(@dir_dst, file)

    assert_equal('-rw-------', `ls -l #{dst}`[0..9])
  end

  test 'Data#sync with existing dirs works OK' do
    MiSeq::Data.sync(@dir_src_ok, @dir_dst)
    MiSeq::Data.sync(@dir_src_ok, @dir_dst)

    file1 = '2013-04-00_Martin_Hansen_0_Big_Bang_0.tar'
    file2 = '2013-04-01_Martin_Hansen_1_Big_Bang_1.tar'
    file3 = '2013-04-02_Martin_Hansen_2_Big_Bang_2.tar'

    assert_true(File.exist? File.join(@dir_dst, file1))
    assert_true(File.exist? File.join(@dir_dst, file2))
    assert_true(File.exist? File.join(@dir_dst, file3))
  end

  test 'Data#sync with unfinished data dir works OK' do
    MiSeq::Data.sync(@dir_src_unfinished, @dir_dst)

    file1 = '2013-04-00_Martin_Hansen_0_Big_Bang_0.tar'
    file2 = '2013-04-01_Martin_Hansen_1_Big_Bang_1.tar'
    file3 = '2013-04-02_Martin_Hansen_2_Big_Bang_2.tar'

    assert_true(File.exist? File.join(@dir_dst, file1))
    assert_true(File.exist? File.join(@dir_dst, file2))
    assert_false(File.exist? File.join(@dir_dst, file3))
  end

  test 'Data#sync log works OK' do
    MiSeq::Data.sync(@dir_src_unfinished, @dir_dst)

    lines = []

    File.open(File.join(@dir_src_unfinished, 'miseq_sync.log')) do |ios|
      ios.each { |line| lines << line }
    end

    assert_equal(8, lines.size)
  end
end
