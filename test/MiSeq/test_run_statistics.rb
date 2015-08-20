$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..', '..')

require 'test/helper'
require 'lib/miseq'

# rubocop:disable ClassLength

# Test class for MiSeq.
class TestRunStatistics < Test::Unit::TestCase
  def setup
    @dir_src      = Dir.mktmpdir('miseq_src')
    @dir_dst      = Dir.mktmpdir('miseq_dst')
    @file_stats   = File.join(@dir_src, 'GenerateFASTQRunStatistics.xml')
  end

  def teardown
    FileUtils.rm_rf @dir_src
  end

  test 'RunStatistics#complete? with non existing file' do
    assert_false(MiSeq::RunStatistics.complete?(''))
  end

  test 'RunStatistics#complete? without CompletionTime tag' do
    File.open(@file_stats, 'w') { |ios| ios.write('') }
    assert_false(MiSeq::RunStatistics.complete?(@file_stats))
  end

  test 'RunStatistics#complete? with CompletionTime tag' do
    File.open(@file_stats, 'w') { |ios| ios.write('  <CompletionTime>') }
    assert_true(MiSeq::RunStatistics.complete?(@file_stats))
  end
end
