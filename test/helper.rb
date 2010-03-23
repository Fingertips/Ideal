require 'rubygems'
require 'test/unit'
require 'mocha'

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'active_merchant_ideal'

ActiveMerchant::Billing::Base.mode = :test

# Test gateways
class SimpleTestGateway < ActiveMerchant::Billing::Gateway
end

class SubclassGateway < SimpleTestGateway
end

class Hash #:nodoc:
  # Return a new hash with all keys converted to symbols.
  def symbolize_keys
    inject({}) do |options, (key, value)|
      options[(key.to_sym rescue key) || key] = value
      options
    end
  end
  # Destructively convert all keys to symbols.
  def symbolize_keys!
    self.replace(self.symbolize_keys)
  end
end

module ActiveMerchant
  module Assertions
    def assert_field(field, value)
      clean_backtrace do 
        assert_equal value, @helper.fields[field]
      end
    end

    # Allows the testing of you to check for negative assertions:
    # 
    #   # Instead of
    #   assert !something_that_is_false
    # 
    #   # Do this
    #   assert_false something_that_should_be_false
    # 
    # An optional +msg+ parameter is available to help you debug.
    def assert_false(boolean, message = nil)
      message = build_message message, '<?> is not false or nil.', boolean

      clean_backtrace do
        assert_block message do
          not boolean
        end
      end
    end

    # A handy little assertion to check for a successful response:
    # 
    #   # Instead of
    #   assert response.success?
    # 
    #   # DRY that up with
    #   assert_success response
    # 
    # A message will automatically show the inspection of the response
    # object if things go afoul.
    def assert_success(response)
      clean_backtrace do
        assert response.success?, "Response failed: #{response.inspect}"
      end
    end

    # The negative of +assert_success+
    def assert_failure(response)
      clean_backtrace do
        assert_false response.success?, "Response expected to fail: #{response.inspect}"
      end
    end

    def assert_valid(validateable)
      clean_backtrace do
        assert validateable.valid?, "Expected to be valid"
      end
    end

    def assert_not_valid(validateable)
      clean_backtrace do
        assert_false validateable.valid?, "Expected to not be valid"
      end
    end

    private
    def clean_backtrace(&block)
      yield
    rescue Test::Unit::AssertionFailedError => e
      path = File.expand_path(__FILE__)
      raise Test::Unit::AssertionFailedError, e.message, e.backtrace.reject { |line| File.expand_path(line) =~ /#{path}/ }
    end
  end
end


module Test
  module Unit
    class TestCase
      HOME_DIR = RUBY_PLATFORM =~ /mswin32/ ? ENV['HOMEPATH'] : ENV['HOME'] unless defined?(HOME_DIR)
      LOCAL_CREDENTIALS = File.join(HOME_DIR.to_s, '.active_merchant/fixtures.yml') unless defined?(LOCAL_CREDENTIALS)
      DEFAULT_CREDENTIALS = File.join(File.dirname(__FILE__), 'fixtures.yml') unless defined?(DEFAULT_CREDENTIALS)

      include ActiveMerchant::Billing
      include ActiveMerchant::Assertions

      private

      def all_fixtures
        @@fixtures ||= load_fixtures
      end

      def fixtures(key)
        data = all_fixtures[key] || raise(StandardError, "No fixture data was found for '#{key}'")

        data.dup
      end

      def load_fixtures
        file = File.exists?(LOCAL_CREDENTIALS) ? LOCAL_CREDENTIALS : DEFAULT_CREDENTIALS
        yaml_data = YAML.load(File.read(file))
        symbolize_keys(yaml_data)

        yaml_data
      end

      def symbolize_keys(hash)
        return unless hash.is_a?(Hash)

        hash.symbolize_keys!
        hash.each{|k,v| symbolize_keys(v)}
      end
    end
  end
end
