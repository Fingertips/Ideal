require 'rubygems'
require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "active_merchant_ideal"
    gem.summary = %Q{iDEAL gateway for ActiveMerchant}
    gem.description = %Q{iDEAL payment gateway for ActiveMerchant (see http://www.ideal.nl and http://www.activemerchant.org/)}
    gem.email = "frank.oxener@gmail.com"
    gem.homepage = "http://github.com/dovadi/active_merchant_ideal"
    gem.authors = ["Soemirno Kartosoewito, Matthijs Kadijk, Aloy Duran, Frank Oxener"]
    gem.add_dependency('activemerchant', '>= 1.5.1')
    gem.add_development_dependency "mocha", ">= 0.9.7"
    # gem is a Gem::Specification... see http://www.rubygems.org/read/chapter/20 for additional settings
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: gem install jeweler"
end

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
    t.test_files = FileList['remote_ideal_test.rb']
    t.verbose = true
  end
end

task :test => :check_dependencies

task :default => :test

require 'rake/rdoctask'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "active_merchant_ideal #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
