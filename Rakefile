require "bundler/gem_tasks"

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
end

namespace :test do
  desc "Run the remote tests for iDEAL gateway"
  Rake::TestTask.new(:remote) do |t|
    t.libs << "test"
    t.test_files = FileList['test/remote_ideal_test.rb']
    t.verbose = true
  end
end

task :default => :test
