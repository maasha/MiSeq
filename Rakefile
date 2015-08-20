require 'pp'
require 'bundler'
require 'rake/testtask'

task default: 'test'

Rake::TestTask.new do |t|
  t.test_files = Dir['test/*'].select do |f|
    File.basename(f).match(/^test_.+\.rb$/)
  end

  t.warning    = true
end
