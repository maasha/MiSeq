$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..', '..')

require 'test/helper'
require 'lib/miseq'

# Test class for SampleSheet.
class TestSampleSheet < Test::Unit::TestCase
  def setup
    @dir_src      = Dir.mktmpdir('miseq_src')
    @dir_dst      = Dir.mktmpdir('miseq_dst')
    @file_stats   = File.join(@dir_src, 'GenerateFASTQRunStatistics.xml')
    @file_samples = File.join(@dir_src, 'Samplesheet.csv')
    @file_log     = File.join(@dir_src, 'log.txt')
  end

  def teardown
    FileUtils.rm_rf @dir_src
  end

  test 'SampleSheet#investigator_name without SampleSheet.csv fails' do
    ss = MiSeq::SampleSheet.new('')
    assert_raise(MiSeq::SampleSheetError) { ss.investigator_name }
  end

  test 'SampleSheet#investigator_name without Investigator line fails' do
    File.open(@file_samples, 'w') { |ios| ios.write('') }
    ss = MiSeq::SampleSheet.new(@file_samples)
    assert_raise(MiSeq::SampleSheetError) { ss.investigator_name }
  end

  test 'SampleSheet#investigator_name without Investigator field fails' do
    File.open(@file_samples, 'w') { |ios| ios.write('Investigator Name') }
    ss = MiSeq::SampleSheet.new(@file_samples)
    assert_raise(MiSeq::SampleSheetError) { ss.investigator_name }
  end

  test 'SampleSheet#investigator_name with Investigator name returns OK' do
    line = 'Investigator Name, Martin Hansen'
    File.open(@file_samples, 'w') { |ios| ios.write(line) }
    ss = MiSeq::SampleSheet.new(@file_samples)
    assert_equal('Martin_Hansen', ss.investigator_name)
  end

  test 'SampleSheet#experiment_name without SampleSheet.csv fails' do
    ss = MiSeq::SampleSheet.new('')
    assert_raise(MiSeq::SampleSheetError) { ss.experiment_name }
  end

  test 'SampleSheet#experiment_name without Experiment line fails' do
    File.open(@file_samples, 'w') { |ios| ios.write('') }
    ss = MiSeq::SampleSheet.new(@file_samples)
    assert_raise(MiSeq::SampleSheetError) { ss.experiment_name }
  end

  test 'SampleSheet#experiment_name without Experiment field fails' do
    File.open(@file_samples, 'w') { |ios| ios.write('Experiment Name') }
    ss = MiSeq::SampleSheet.new(@file_samples)
    assert_raise(MiSeq::SampleSheetError) { ss.experiment_name }
  end

  test 'SampleSheet#experiment_name with Experiment name returns OK' do
    line = 'Experiment Name, Big Bang'
    File.open(@file_samples, 'w') { |ios| ios.write(line) }
    ss = MiSeq::SampleSheet.new(@file_samples)
    assert_equal('Big_Bang', ss.experiment_name)
  end
end
