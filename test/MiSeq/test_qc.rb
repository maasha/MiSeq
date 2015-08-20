$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..', '..')

require 'test/helper'
require 'lib/miseq'

# Test class for QC.
class TestQC < Test::Unit::TestCase
  def setup
    @src = Dir.mktmpdir('miseq_src')
    @dst = Dir.mktmpdir('miseq_dst')

    setup_src
  end

  def setup_src
    @dir = File.join(@src, '2015-08-23_foo')

    Dir.mkdir @dir

    setup_data
  end

  def setup_data
    file1 = File.join(@dir, 'foo_S94_L001_R1_001.fastq.gz')
    file2 = File.join(@dir, 'foo_S94_L001_R2_001.fastq.gz')

    File.open(file1, 'w') do |ios|
      ios.puts '@DHWCT801:422:H3CYMBCXX:1:1101:1494:2136 1:N:0:ATTACTCGTATAGCCT'
      ios.puts 'ATCG'
      ios.puts '+'
      ios.puts '8888'
    end

    File.open(file2, 'w') do |ios|
      ios.puts '@DHWCT801:422:H3CYMBCXX:1:1101:1494:2136 2:N:0:ATTACTCGTATAGCCT'
      ios.puts 'ATCG'
      ios.puts '+'
      ios.puts '8888'
    end
  end

  def setup_bad_data
    file1 = File.join(@dir, 'foo_S94_L00X_R1_001.fastq.gz')
    file2 = File.join(@dir, 'foo_S94_L00X_R2_001.fastq.gz')

    File.open(file1, 'w') do |ios|
      ios.puts '@DHWCT801:422:H3CYMBCXX:1:1101:1494:2136 1:N:0:ATTACTCGTATAGCCT'
      ios.puts 'ATCG'
      ios.puts '+'
      ios.puts '8888'
    end

    File.open(file2, 'w') do |ios|
      ios.puts '@DHWCT801:422:H3CYMBCXX:1:1101:1494:2136 2:N:0:ATTACTCGTATAGCCT'
      ios.puts 'ATCG'
      ios.puts '+'
      ios.puts '8888'
    end
  end

  def teardown
    FileUtils.rm_rf @src
  end

  test 'QC#run without valid src dir raises' do
    assert_raise(MiSeq::QCError) { MiSeq::QC.run('asdf', @dst) }
  end

  test 'QC#run without valid dst dir raises' do
    assert_raise(MiSeq::QCError) { MiSeq::QC.run(@src, 'asdf') }
  end

  test 'QC#run with bad FASTQ file names raises' do
    setup_bad_data
    assert_raise(MiSeq::QCError) { MiSeq::QC.run(@src, @dst) }
  end

  test 'QC#run works OK' do
    MiSeq::QC.run(@src, @dst)

    assert_equal(8, Dir["#{@dst}/*/*/*"].size)
  end
end
