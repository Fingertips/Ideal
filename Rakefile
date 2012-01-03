require "bundler/gem_tasks"

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'test'
  test.test_files = FileList['test/gateway_test.rb']
  test.verbose = true
end

namespace :test do
  desc "Run the remote tests for iDEAL gateway"
  Rake::TestTask.new(:remote) do |test|
    test.libs << 'test'
    test.test_files = FileList['test/remote_test.rb']
    test.verbose = true
  end
end

task :default => :test
