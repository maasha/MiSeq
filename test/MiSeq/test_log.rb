$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..', '..')

require 'test/helper'
require 'lib/miseq'

# Test class for Log.
class TestLog < Test::Unit::TestCase
  def setup
    @dir_src  = Dir.mktmpdir('miseq_src')
    @dir_dst  = Dir.mktmpdir('miseq_dst')
    @file_log = File.join(@dir_src, 'log.txt')
  end

  def teardown
    FileUtils.rm_rf @dir_src
  end

  test 'Log#log new log file works OK' do
    logger = MiSeq::Log.new(@file_log)
    logger.log('my message')

    lines = []

    File.open(@file_log) do |ios|
      ios.each_line { |line| lines << line.chomp }
    end

    assert_equal(1, lines.size)
    assert_equal('my message', lines.first.split("\t").last)
  end

  test 'Log#log appends works OK' do
    logger = MiSeq::Log.new(@file_log)
    logger.log('1 message')
    logger.log('2 message')

    lines = []

    File.open(@file_log) do |ios|
      ios.each_line { |line| lines << line.chomp }
    end

    assert_equal(2, lines.size)
    assert_equal('1 message', lines.first.split("\t").last)
    assert_equal('2 message', lines.last.split("\t").last)
  end
end
