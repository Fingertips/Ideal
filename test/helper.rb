require 'rubygems'
require 'test/unit'
require 'mocha'
require 'active_support/test_case'

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'ideal'

$stdout.sync = true

unless defined?(Test::Unit::AssertionFailedError)
  Test::Unit::AssertionFailedError = ActiveSupport::TestCase::Assertion
end

module Test
  module Unit
    class TestCase
      HOME_DIR = RUBY_PLATFORM =~ /mswin32/ ? ENV['HOMEPATH'] : ENV['HOME'] unless defined?(HOME_DIR)
      LOCAL_CREDENTIALS = File.join(HOME_DIR.to_s, '.ideal/fixtures.yml') unless defined?(LOCAL_CREDENTIALS)
      DEFAULT_CREDENTIALS = File.join(File.dirname(__FILE__), 'fixtures.yml') unless defined?(DEFAULT_CREDENTIALS)
      
      def strip_whitespace(str)
        str.gsub(/\s/m,'')
      end
      
      private

      def all_fixtures
        @fixtures ||= load_fixtures
      end

      def fixtures(key)
        data = all_fixtures[key] || raise(StandardError, "No fixture data was found for '#{key}'")
        data.dup
      end

      def load_fixtures
        file = File.exists?(LOCAL_CREDENTIALS) ? LOCAL_CREDENTIALS : DEFAULT_CREDENTIALS
        YAML.load(File.read(file))
      end
    end
  end
end
