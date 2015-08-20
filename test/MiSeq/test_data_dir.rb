$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..', '..')

require 'test/helper'
require 'lib/miseq'

# Test class for DataDir.
class TestDataDir < Test::Unit::TestCase
  def setup
    @dir_src = Dir.mktmpdir('miseq_src')
    @dir_dst = Dir.mktmpdir('miseq_dst')
  end

  def teardown
    FileUtils.rm_rf @dir_src
  end

  test 'DataDir#date with bad format fails' do
    dd = MiSeq::DataDir.new('/MiSeq/2013-04-50')
    assert_raise(MiSeq::DataDirError) { dd.date }
  end

  test 'DataDir#date returns OK' do
    dd = MiSeq::DataDir.new('/MiSeq/131223_')
    assert_equal('2013-12-23', dd.date)
  end

  test 'DataDir#rename with existing dir fails' do
    dd       = MiSeq::DataDir.new('/MiSeq/131223_')
    new_name = File.join(@dir_src, 'new')
    Dir.mkdir(new_name)
    assert_raise(MiSeq::DataDirError) { dd.rename(new_name) }
  end

  test 'DataDir#rename works OK' do
    old_name = File.join(@dir_src, '131223_')
    new_name = File.join(@dir_src, 'new')
    dd       = MiSeq::DataDir.new(old_name)
    Dir.mkdir(old_name)
    dd.rename(new_name)
    assert_true(File.directory? dd.dir)
  end
end
