require File.dirname(__FILE__) + '/helper'

module IdealTestCases
  # This method is called at the end of the file when all fixture data has been loaded.
  def self.setup_ideal_gateway!
    ActiveMerchant::Billing::IdealGateway.class_eval do
      self.merchant_id = '123456789'

      self.passphrase = 'passphrase'
      self.private_key = PRIVATE_KEY
      self.private_certificate = PRIVATE_CERTIFICATE
      self.ideal_certificate = IDEAL_CERTIFICATE

      self.test_url = "https://idealtest.example.com:443/ideal/iDeal"
      self.live_url = "https://ideal.example.com:443/ideal/iDeal"
    end
  end

  VALID_PURCHASE_OPTIONS = {
    :issuer_id         => '0001',
    :expiration_period => 'PT10M',
    :return_url        => 'http://return_to.example.com',
    :order_id          => '12345678901',
    :description       => 'A classic Dutch windmill',
    :entrance_code     => '1234'
  }

  ###
  #
  # Actual test cases
  #

  class ClassMethodsTest < Test::Unit::TestCase
    def test_merchant_id
      assert_equal IdealGateway.merchant_id, '123456789'
    end

    def test_private_certificate_returns_a_loaded_Certificate_instance
      assert_equal IdealGateway.private_certificate.to_text,
        OpenSSL::X509::Certificate.new(PRIVATE_CERTIFICATE).to_text
    end

    def test_private_key_returns_a_loaded_PKey_RSA_instance
      assert_equal IdealGateway.private_key.to_text,
        OpenSSL::PKey::RSA.new(PRIVATE_KEY, IdealGateway.passphrase).to_text
    end

    def test_ideal_certificate_returns_a_loaded_Certificate_instance
      assert_equal IdealGateway.ideal_certificate.to_text,
        OpenSSL::X509::Certificate.new(IDEAL_CERTIFICATE).to_text
    end
  end

  class GeneralTest < Test::Unit::TestCase
    def setup
      @gateway = IdealGateway.new
    end

    def test_optional_initialization_options
      assert_equal 0, IdealGateway.new.sub_id
      assert_equal 1, IdealGateway.new(:sub_id => 1).sub_id
    end

    def test_returns_the_test_url_when_in_the_test_env
      @gateway.stubs(:test?).returns(true)
      assert_equal IdealGateway.test_url, @gateway.send(:acquirer_url)
    end

    def test_returns_the_live_url_when_not_in_the_test_env
      @gateway.stubs(:test?).returns(false)
      assert_equal IdealGateway.live_url, @gateway.send(:acquirer_url)
    end

    def test_returns_created_at_timestamp
      timestamp = '2001-12-17T09:30:47.000Z'
      Time.any_instance.stubs(:gmtime).returns(DateTime.parse(timestamp))

      assert_equal timestamp, @gateway.send(:created_at_timestamp)
    end

    def test_ruby_to_java_keys_conversion
      keys = [
        [:acquirer_transaction_request, 'AcquirerTrxReq'],
        [:acquirer_status_request,      'AcquirerStatusReq'],
        [:directory_request,            'DirectoryReq'],
        [:created_at,                   'createDateTimeStamp'],
        [:issuer,                       'Issuer'],
        [:merchant,                     'Merchant'],
        [:transaction,                  'Transaction'],
        [:issuer_id,                    'issuerID'],
        [:merchant_id,                  'merchantID'],
        [:sub_id,                       'subID'],
        [:token_code,                   'tokenCode'],
        [:merchant_return_url,          'merchantReturnURL'],
        [:purchase_id,                  'purchaseID'],
        [:expiration_period,            'expirationPeriod'],
        [:entrance_code,                'entranceCode']
      ]

      keys.each do |key, expected_key|
        assert_equal expected_key, @gateway.send(:javaize_key, key)
      end
    end

    def test_does_not_convert_unknown_key_to_java_key
      assert_equal 'not_a_registered_key', @gateway.send(:javaize_key, :not_a_registered_key)
    end

    def test_token_generation
      expected_token = Digest::SHA1.hexdigest(OpenSSL::X509::Certificate.new(PRIVATE_CERTIFICATE).to_der).upcase
      assert_equal expected_token, @gateway.send(:token)
    end

    def test_token_code_generation
      message = "Top\tsecret\tman.\nI could tell you, but then I'd have to kill you…"
      stripped_message = message.gsub(/\s/m, '')

      sha1 = OpenSSL::Digest::SHA1.new
      OpenSSL::Digest::SHA1.stubs(:new).returns(sha1)

      signature = IdealGateway.private_key.sign(sha1, stripped_message)
      encoded_signature = Base64.encode64(signature).strip.gsub(/\n/, '')

      assert_equal encoded_signature, @gateway.send(:token_code, message)
    end

    def test_posts_data_with_ssl_to_acquirer_url_and_return_the_correct_response
      IdealResponse.expects(:new).with('response', :test => true)
      @gateway.expects(:ssl_post).with(@gateway.acquirer_url, 'data').returns('response')
      @gateway.send(:post_data, 'data', IdealResponse)

      @gateway.stubs(:test?).returns(false)
      IdealResponse.expects(:new).with('response', :test => false)
      @gateway.expects(:ssl_post).with(@gateway.acquirer_url, 'data').returns('response')
      @gateway.send(:post_data, 'data', IdealResponse)
    end
  end

  class XMLBuildingTest < Test::Unit::TestCase
    def setup
      @gateway = IdealGateway.new
    end

    def test_contains_correct_info_in_root_node
      expected_xml = Builder::XmlMarkup.new
      expected_xml.instruct!
      expected_xml.tag!('AcquirerTrxReq', 'xmlns' => IdealGateway::XML_NAMESPACE, 'version' => IdealGateway::API_VERSION) {}

      assert_equal expected_xml.target!, @gateway.send(:xml_for, :acquirer_transaction_request, [])
    end

    def test_creates_correct_xml_with_java_keys_from_array_with_ruby_keys
      expected_xml = Builder::XmlMarkup.new
      expected_xml.instruct!
      expected_xml.tag!('AcquirerTrxReq', 'xmlns' => IdealGateway::XML_NAMESPACE, 'version' => IdealGateway::API_VERSION) do
        expected_xml.tag!('a_parent') do
          expected_xml.tag!('createDateTimeStamp', '2009-01-26')
        end
      end

      assert_equal expected_xml.target!, @gateway.send(:xml_for, :acquirer_transaction_request, [[:a_parent, [[:created_at, '2009-01-26']]]])
    end
  end

  class RequestBodyBuildingTest < Test::Unit::TestCase
    def setup
      @gateway = IdealGateway.new

      @gateway.stubs(:created_at_timestamp).returns('created_at_timestamp')
      @gateway.stubs(:token).returns('the_token')
      @gateway.stubs(:token_code)

      @transaction_id = '0001023456789112'
    end

    def test_build_transaction_request_body_raises_ArgumentError_with_missing_required_options
      options = VALID_PURCHASE_OPTIONS.dup
      options.keys.each do |key|
        options.delete(key)

        assert_raise(ArgumentError) do
          @gateway.send(:build_transaction_request_body, 100, options)
        end
      end
    end

    def test_valid_with_valid_options
      assert_not_nil @gateway.send(:build_transaction_request_body, 4321, VALID_PURCHASE_OPTIONS)
    end

    def test_checks_that_fields_are_not_too_long
      assert_raise ArgumentError do
        @gateway.send(:build_transaction_request_body, 1234567890123, VALID_PURCHASE_OPTIONS) # 13 chars
      end

      [
        [:order_id, '12345678901234567'], # 17 chars,
        [:description, '123456789012345678901234567890123'], # 33 chars
        [:entrance_code, '12345678901234567890123456789012345678901'] # 41
      ].each do |key, value|
        options = VALID_PURCHASE_OPTIONS.dup
        options[key] = value

        assert_raise ArgumentError do
          @gateway.send(:build_transaction_request_body, 4321, options)
        end
      end
    end

    def test_checks_that_fields_do_not_contain_diacritical_characters
      assert_raise ArgumentError do
        @gateway.send(:build_transaction_request_body, 'graphème', VALID_PURCHASE_OPTIONS)
      end

      [:order_id, :description, :entrance_code].each do |key, value|
        options = VALID_PURCHASE_OPTIONS.dup
        options[key] = 'graphème'

        assert_raise ArgumentError do
          @gateway.send(:build_transaction_request_body, 4321, options)
        end
      end
    end

    def test_builds_a_transaction_request_body
      money = 4321

      message = 'created_at_timestamp' +
                VALID_PURCHASE_OPTIONS[:issuer_id] +
                IdealGateway.merchant_id +
                @gateway.sub_id.to_s +
                VALID_PURCHASE_OPTIONS[:return_url] +
                VALID_PURCHASE_OPTIONS[:order_id] +
                money.to_s +
                IdealGateway::CURRENCY +
                IdealGateway::LANGUAGE +
                VALID_PURCHASE_OPTIONS[:description] +
                VALID_PURCHASE_OPTIONS[:entrance_code]

      @gateway.expects(:token_code).with(message).returns('the_token_code')

      @gateway.expects(:xml_for).with(:acquirer_transaction_request, [
        [:created_at, 'created_at_timestamp'],
        [:issuer, [[:issuer_id, VALID_PURCHASE_OPTIONS[:issuer_id]]]],

        [:merchant, [
          [:merchant_id,         IdealGateway.merchant_id],
          [:sub_id,              @gateway.sub_id],
          [:authentication,      IdealGateway::AUTHENTICATION_TYPE],
          [:token,               'the_token'],
          [:token_code,          'the_token_code'],
          [:merchant_return_url, VALID_PURCHASE_OPTIONS[:return_url]]
        ]],

        [:transaction, [
          [:purchase_id,       VALID_PURCHASE_OPTIONS[:order_id]],
          [:amount,            money],
          [:currency,          IdealGateway::CURRENCY],
          [:expiration_period, VALID_PURCHASE_OPTIONS[:expiration_period]],
          [:language,          IdealGateway::LANGUAGE],
          [:description,       VALID_PURCHASE_OPTIONS[:description]],
          [:entrance_code,     VALID_PURCHASE_OPTIONS[:entrance_code]]
        ]]
      ])

      @gateway.send(:build_transaction_request_body, money, VALID_PURCHASE_OPTIONS)
    end

    def test_builds_a_directory_request_body
      message = 'created_at_timestamp' + IdealGateway.merchant_id + @gateway.sub_id.to_s
      @gateway.expects(:token_code).with(message).returns('the_token_code')

      @gateway.expects(:xml_for).with(:directory_request, [
        [:created_at, 'created_at_timestamp'],
        [:merchant, [
          [:merchant_id,    IdealGateway.merchant_id],
          [:sub_id,         @gateway.sub_id],
          [:authentication, IdealGateway::AUTHENTICATION_TYPE],
          [:token,          'the_token'],
          [:token_code,     'the_token_code']
        ]]
      ])

      @gateway.send(:build_directory_request_body)
    end

    def test_builds_a_status_request_body_raises_ArgumentError_with_missing_required_options
      assert_raise(ArgumentError) do
        @gateway.send(:build_status_request_body, {})
      end
    end

    def test_builds_a_status_request_body
      options = { :transaction_id => @transaction_id }

      message = 'created_at_timestamp' + IdealGateway.merchant_id + @gateway.sub_id.to_s + options[:transaction_id]
      @gateway.expects(:token_code).with(message).returns('the_token_code')

      @gateway.expects(:xml_for).with(:acquirer_status_request, [
        [:created_at, 'created_at_timestamp'],
        [:merchant, [
          [:merchant_id,    IdealGateway.merchant_id],
          [:sub_id,         @gateway.sub_id],
          [:authentication, IdealGateway::AUTHENTICATION_TYPE],
          [:token,          'the_token'],
          [:token_code,     'the_token_code']
        ]],

        [:transaction, [
          [:transaction_id, options[:transaction_id]]
        ]],
      ])

      @gateway.send(:build_status_request_body, options)
    end
  end

  class GeneralResponseTest < Test::Unit::TestCase
    def test_resturns_if_it_is_a_test_request
      assert IdealResponse.new(DIRECTORY_RESPONSE_WITH_MULTIPLE_ISSUERS, :test => true).test?

      assert !IdealResponse.new(DIRECTORY_RESPONSE_WITH_MULTIPLE_ISSUERS, :test => false).test?
      assert !IdealResponse.new(DIRECTORY_RESPONSE_WITH_MULTIPLE_ISSUERS).test?
    end
  end

  class SuccessfulResponseTest < Test::Unit::TestCase
    def setup
      @response = IdealResponse.new(DIRECTORY_RESPONSE_WITH_MULTIPLE_ISSUERS)
    end

    def test_initializes_with_only_response_body
      assert_equal REXML::Document.new(DIRECTORY_RESPONSE_WITH_MULTIPLE_ISSUERS).root.to_s,
                    @response.instance_variable_get(:@response).to_s
    end

    def test_successful
      assert @response.success?
    end

    def test_returns_no_error_messages
      assert_nil @response.error_message
    end

    def test_returns_no_error_code
      assert_nil @response.error_code
    end
  end

  class ErrorResponseTest < Test::Unit::TestCase
    def setup
      @response = IdealResponse.new(ERROR_RESPONSE)
    end

    def test_unsuccessful
      assert !@response.success?
    end

    def test_returns_error_messages
      assert_equal 'Failure in system', @response.error_message
      assert_equal 'System generating error: issuer', @response.error_details
      assert_equal 'Betalen met iDEAL is nu niet mogelijk.', @response.consumer_error_message
    end

    def test_returns_error_code
      assert_equal 'SO1000', @response.error_code
    end

    def test_returns_error_type
      [
        ['IX1000', :xml],
        ['SO1000', :system],
        ['SE2000', :security],
        ['BR1200', :value],
        ['AP1000', :application]
      ].each do |code, type|
        @response.stubs(:error_code).returns(code)
        assert_equal type, @response.error_type
      end
    end
  end

  class DirectoryTest < Test::Unit::TestCase
    def setup
      @gateway = IdealGateway.new
    end

    def test_returns_a_list_with_only_one_issuer
      @gateway.stubs(:build_directory_request_body).returns('the request body')
      @gateway.expects(:ssl_post).with(@gateway.acquirer_url, 'the request body').returns(DIRECTORY_RESPONSE_WITH_ONE_ISSUER)

      expected_issuers = [{ :id => '1006', :name => 'ABN AMRO Bank' }]

      directory_response = @gateway.issuers
      assert_instance_of IdealDirectoryResponse, directory_response
      assert_equal expected_issuers, directory_response.list
    end

    def test_returns_list_of_issuers_from_response
      @gateway.stubs(:build_directory_request_body).returns('the request body')
      @gateway.expects(:ssl_post).with(@gateway.acquirer_url, 'the request body').returns(DIRECTORY_RESPONSE_WITH_MULTIPLE_ISSUERS)

      expected_issuers = [
        { :id => '1006', :name => 'ABN AMRO Bank' },
        { :id => '1003', :name => 'Postbank' },
        { :id => '1005', :name => 'Rabobank' },
        { :id => '1017', :name => 'Asr bank' },
        { :id => '1023', :name => 'Van Lanschot' }
      ]

      directory_response = @gateway.issuers
      assert_instance_of IdealDirectoryResponse, directory_response
      assert_equal expected_issuers, directory_response.list
    end
  end

  class SetupPurchaseTest < Test::Unit::TestCase
    def setup
      @gateway = IdealGateway.new

      @gateway.stubs(:build_transaction_request_body).with(4321, VALID_PURCHASE_OPTIONS).returns('the request body')
      @gateway.expects(:ssl_post).with(@gateway.acquirer_url, 'the request body').returns(ACQUIRER_TRANSACTION_RESPONSE)

      @setup_purchase_response = @gateway.setup_purchase(4321, VALID_PURCHASE_OPTIONS)
    end

    def test_setup_purchase_returns_IdealTransactionResponse
      assert_instance_of IdealTransactionResponse, @setup_purchase_response
    end

    def test_setup_purchase_returns_response_with_service_url
      assert_equal 'https://ideal.example.com/long_service_url?X009=BETAAL&X010=20', @setup_purchase_response.service_url
    end

    def test_setup_purchase_returns_response_with_transaction_and_order_ids
      assert_equal '0001023456789112', @setup_purchase_response.transaction_id
      assert_equal 'iDEAL-aankoop 21', @setup_purchase_response.order_id
    end
  end

  class CapturePurchaseTest < Test::Unit::TestCase
    def setup
      @gateway = IdealGateway.new

      @gateway.stubs(:build_status_request_body).
        with(:transaction_id => '0001023456789112').returns('the request body')
    end

    def test_setup_purchase_returns_IdealStatusResponse
      expects_request_and_returns ACQUIRER_SUCCEEDED_STATUS_RESPONSE
      assert_instance_of IdealStatusResponse, @gateway.capture('0001023456789112')
    end

    # Because we don't have a real private key and certificate we stub
    # verified? to return true. However, this is properly tested in the remote
    # tests.
    def test_capture_of_successful_payment
      IdealStatusResponse.any_instance.stubs(:verified?).returns(true)

      expects_request_and_returns ACQUIRER_SUCCEEDED_STATUS_RESPONSE
      capture_response = @gateway.capture('0001023456789112')

      assert capture_response.success?
    end

    def test_capture_of_failed_payment
      expects_request_and_returns ACQUIRER_FAILED_STATUS_RESPONSE
      capture_response = @gateway.capture('0001023456789112')

      assert !capture_response.success?
    end

    def test_capture_of_successful_payment_but_message_does_not_match_signature
      expects_request_and_returns ACQUIRER_SUCCEEDED_BUT_WRONG_SIGNATURE_STATUS_RESPONSE
      capture_response = @gateway.capture('0001023456789112')

      assert !capture_response.success?
    end

    def test_returns_status
      response = IdealStatusResponse.new(ACQUIRER_SUCCEEDED_STATUS_RESPONSE)
      [
        ['Success',   :success],
        ['Cancelled', :cancelled],
        ['Expired',   :expired],
        ['Open',      :open],
        ['Failure',   :failure]
      ].each do |raw_status, expected_status|
        response.stubs(:text).with("//status").returns(raw_status)
        assert_equal expected_status, response.status
      end
    end

    private

    def expects_request_and_returns(str)
      @gateway.expects(:ssl_post).with(@gateway.acquirer_url, 'the request body').returns(str)
    end
  end

  ###
  #
  # Fixture data
  #

  PRIVATE_CERTIFICATE = %{-----BEGIN CERTIFICATE-----
MIIC+zCCAmSgAwIBAgIJALVAygHjnd8ZMA0GCSqGSIb3DQEBBQUAMF0xCzAJBgNV
BAYTAk5MMRYwFAYDVQQIEw1Ob29yZC1Ib2xsYW5kMRIwEAYDVQQHEwlBbXN0ZXJk
YW0xIjAgBgNVBAoTGWlERUFMIEFjdGl2ZU1lcmNoYW50IFRlc3QwHhcNMDkwMTMw
MTMxNzQ5WhcNMjQxMjExMDM1MjI5WjBdMQswCQYDVQQGEwJOTDEWMBQGA1UECBMN
Tm9vcmQtSG9sbGFuZDESMBAGA1UEBxMJQW1zdGVyZGFtMSIwIAYDVQQKExlpREVB
TCBBY3RpdmVNZXJjaGFudCBUZXN0MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKB
gQDmBpi+RVvZBA01kdP5lV5bDzu6Jp1zy78qhxxwlG8WMdUh0Qtg0kkYmeThFPoh
2c3BYuFQ+AA6f1R0Spb+hTNrBxkZaRnHCfMMD9LXquFjJ/lvSGnwkjvBmGzyTPZ1
LIunpejm8hH0MJPqpp5AIeXjp1mv7BXA9y0FqObrrLAPaQIDAQABo4HCMIG/MB0G
A1UdDgQWBBTLqGWJt5+Ri6vrOpqGZhINbRtXczCBjwYDVR0jBIGHMIGEgBTLqGWJ
t5+Ri6vrOpqGZhINbRtXc6FhpF8wXTELMAkGA1UEBhMCTkwxFjAUBgNVBAgTDU5v
b3JkLUhvbGxhbmQxEjAQBgNVBAcTCUFtc3RlcmRhbTEiMCAGA1UEChMZaURFQUwg
QWN0aXZlTWVyY2hhbnQgVGVzdIIJALVAygHjnd8ZMAwGA1UdEwQFMAMBAf8wDQYJ
KoZIhvcNAQEFBQADgYEAGtgkmME9tgaxJIU3T7v1/xbKr6A/iwmt3sCmfJEl4Pty
aUGaHFy1KB7xmkna8gomxMWL2zZkdv4t1iGeuVCl9n77SL3MzapotdeNNqahblcN
RBshYCpWpsQQPF45/R5Xp7rXWWsjxgip7qTBNpgTx+Z/VKQpuQsFjYCYq4UCf2Y=
-----END CERTIFICATE-----}

  PRIVATE_KEY = %{-----BEGIN RSA PRIVATE KEY-----
MIICXAIBAAKBgQDmBpi+RVvZBA01kdP5lV5bDzu6Jp1zy78qhxxwlG8WMdUh0Qtg
0kkYmeThFPoh2c3BYuFQ+AA6f1R0Spb+hTNrBxkZaRnHCfMMD9LXquFjJ/lvSGnw
kjvBmGzyTPZ1LIunpejm8hH0MJPqpp5AIeXjp1mv7BXA9y0FqObrrLAPaQIDAQAB
AoGAfkccz0ewVoDc5424+wk/FWpVdaoBQjKWLbiiqkMygNK2mKv0PSD0M+c4OUCU
2MSDKikoXJTpOzPvny/bmLpzMMGn9YJiWEQ5WdaTdppffdylfGPBZXZkt5M9nxJA
NL3fPT79R79mkCF8cgNUbLtNL4woSoFKwRHDU2CGvtTbxqkCQQD+TY1sGJv1VTQi
MYYx3FlEOqw3jp/2q7QluTDDGmvmVOSFnAPfmX0rKEtnBmG4ID7IaG+IQFthDudL
3trqGQdTAkEA54+RxyCZiXDfkh23cD0QaApZaBuk6cKkx6qeFxeg1T+/idGgtWJI
Qg3i9fHzOIFUXwk51R3xh5IimvMJZ9Ii0wJAb7yrsx9tB3MUoSGZkTb8kholqZOl
fcEcOqcQYemuF1qdvoc6vHi4osnlt7L6JOkmLPCWcQu2GwNtZczZ65pruQJBAJ3p
vbtzUuF01TKbC18Cda7N5/zkZUl5ENCNXTRYS7lBuQhuqc8okChjufSJpJlTMUuC
Sis5OV5/3ROYTEC+ADsCQCwq6VQ1kXRrM+3tkMwi2rZi73dsFVuFx8crlBOmvhkD
U7Ar9bW13qhBeH9px8RCRDMWTGQcxY/C/TEQc/qvhkI=
-----END RSA PRIVATE KEY-----}

  IDEAL_CERTIFICATE = %{-----BEGIN CERTIFICATE-----
MIIEAzCCA3CgAwIBAgIQMIEnzk1UPrPDLOY9dc2cUjANBgkqhkiG9w0BAQUFADBf
MQswCQYDVQQGEwJVUzEgMB4GA1UEChMXUlNBIERhdGEgU2VjdXJpdHksIEluYy4x
LjAsBgNVBAsTJVNlY3VyZSBTZXJ2ZXIgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkw
HhcNMDQwNjA4MDAwMDAwWhcNMDUwNjA4MjM1OTU5WjCBvDELMAkGA1UEBhMCTkwx
FjAUBgNVBAgTDU5vb3JkLUhvbGxhbmQxEjAQBgNVBAcUCUFtc3RlcmRhbTEbMBkG
A1UEChQSQUJOIEFNUk8gQmFuayBOLlYuMRYwFAYDVQQLFA1JTi9OUy9FLUlORlJB
MTMwMQYDVQQLFCpUZXJtcyBvZiB1c2UgYXQgd3d3LnZlcmlzaWduLmNvbS9ycGEg
KGMpMDAxFzAVBgNVBAMUDnd3dy5hYm5hbXJvLm5sMIGfMA0GCSqGSIb3DQEBAQUA
A4GNADCBiQKBgQD1hPZlFD01ZdQu0GVLkUQ7tOwtVw/jmZ1Axu8v+3bxrjKX9Qi1
0w6EIadCXScDMmhCstExVptaTEQ5hG3DedV2IpMcwe93B1lfyviNYlmc/XIol1B7
PM70mI9XUTYAoJpquEv8AaupRO+hgxQlz3FACHINJxEIMgdxa1iyoJfCKwIDAQAB
o4IBZDCCAWAwCQYDVR0TBAIwADALBgNVHQ8EBAMCBaAwPAYDVR0fBDUwMzAxoC+g
LYYraHR0cDovL2NybC52ZXJpc2lnbi5jb20vUlNBU2VjdXJlU2VydmVyLmNybDBE
BgNVHSAEPTA7MDkGC2CGSAGG+EUBBxcDMCowKAYIKwYBBQUHAgEWHGh0dHBzOi8v
d3d3LnZlcmlzaWduLmNvbS9ycGEwHQYDVR0lBBYwFAYIKwYBBQUHAwEGCCsGAQUF
BwMCMDQGCCsGAQUFBwEBBCgwJjAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AudmVy
aXNpZ24uY29tMG0GCCsGAQUFBwEMBGEwX6FdoFswWTBXMFUWCWltYWdlL2dpZjAh
MB8wBwYFKw4DAhoEFI/l0xqGrI2Oa8PPgGrUSBgsexkuMCUWI2h0dHA6Ly9sb2dv
LnZlcmlzaWduLmNvbS92c2xvZ28uZ2lmMA0GCSqGSIb3DQEBBQUAA34AY7BYsNvj
i5fjnEHPlGOd2yxseCHU54HDPPCZOoP9a9kVWGX8tuj2b1oeiOsIbI1viIo+O4eQ
ilZjTJIlLOkXk6uE8vQGjZy0BUnjNPkXOQGkTyj4jDxZ2z+z9Vy8BwfothdcYbZK
48ZOp3u74DdEfQejNxBeqLODzrxQTV4=
-----END CERTIFICATE-----}

  DIRECTORY_RESPONSE_WITH_ONE_ISSUER = %{<?xml version="1.0" encoding="UTF-8"?>
<DirectoryRes xmlns="http://www.idealdesk.com/Message" version="1.1.0">
  <createDateTimeStamp>2001-12-17T09:30:47.0Z</createDateTimeStamp>
  <Acquirer>
    <acquirerID>0245</acquirerID>
  </Acquirer>
  <Directory>
    <directoryDateTimeStamp>2004-11-10T10:15:12.145Z</directoryDateTimeStamp>
    <Issuer>
      <issuerID>1006</issuerID>
      <issuerName>ABN AMRO Bank</issuerName>
      <issuerList>Short</issuerList>
    </Issuer>
  </Directory>
</DirectoryRes>}

  DIRECTORY_RESPONSE_WITH_MULTIPLE_ISSUERS = %{<?xml version="1.0" encoding="UTF-8"?>
<DirectoryRes xmlns="http://www.idealdesk.com/Message" version="1.1.0">
  <createDateTimeStamp>2001-12-17T09:30:47.0Z</createDateTimeStamp>
  <Acquirer>
    <acquirerID>0245</acquirerID>
  </Acquirer>
  <Directory>
    <directoryDateTimeStamp>2004-11-10T10:15:12.145Z</directoryDateTimeStamp>
    <Issuer>
      <issuerID>1006</issuerID>
      <issuerName>ABN AMRO Bank</issuerName>
      <issuerList>Short</issuerList>
    </Issuer>
    <Issuer>
      <issuerID>1003</issuerID>
      <issuerName>Postbank</issuerName>
      <issuerList>Short</issuerList>
    </Issuer>
    <Issuer>
      <issuerID>1005</issuerID>
      <issuerName>Rabobank</issuerName>
      <issuerList>Short</issuerList>
    </Issuer>
    <Issuer>
      <issuerID>1017</issuerID>
      <issuerName>Asr bank</issuerName>
      <issuerList>Long</issuerList>
    </Issuer>
    <Issuer>
      <issuerID>1023</issuerID>
      <issuerName>Van Lanschot</issuerName>
      <issuerList>Long</issuerList>
    </Issuer>
  </Directory>
</DirectoryRes>}

  ACQUIRER_TRANSACTION_RESPONSE = %{<?xml version="1.0" encoding="UTF-8"?>
<AcquirerTrxRes xmlns="http://www.idealdesk.com/Message" version="1.1.0">
  <createDateTimeStamp>2001-12-17T09:30:47.0Z</createDateTimeStamp>
  <Acquirer>
    <acquirerID>1545</acquirerID>
  </Acquirer>
  <Issuer>
    <issuerAuthenticationURL>https://ideal.example.com/long_service_url?X009=BETAAL&amp;X010=20</issuerAuthenticationURL>
  </Issuer>
  <Transaction>
     <transactionID>0001023456789112</transactionID>
     <purchaseID>iDEAL-aankoop 21</purchaseID>
  </Transaction>
</AcquirerTrxRes>}

  ACQUIRER_SUCCEEDED_STATUS_RESPONSE = %{<?xml version="1.0" encoding="UTF-8"?>
<AcquirerStatusRes xmlns="http://www.idealdesk.com/Message" version="1.1.0">
  <createDateTimeStamp>2001-12-17T09:30:47.0Z</createDateTimeStamp>
  <Acquirer>
     <acquirerID>1234</acquirerID>
  </Acquirer>
  <Transaction>
     <transactionID>0001023456789112</transactionID>
     <status>Success</status>
     <consumerName>Onderheuvel</consumerName>
     <consumerAccountNumber>0949298989</consumerAccountNumber>
     <consumerCity>DEN HAAG</consumerCity>
  </Transaction>
  <Signature>
    <signatureValue>db82/jpJRvKQKoiDvu33X0yoDAQpayJOaW2Y8zbR1qk1i3epvTXi+6g+QVBY93YzGv4w+Va+vL3uNmzyRjYsm2309d1CWFVsn5Mk24NLSvhYfwVHEpznyMqizALEVUNSoiSHRkZUDfXowBAyLT/tQVGbuUuBj+TKblY826nRa7U=</signatureValue>
    <fingerprint>1E15A00E3D7DF085768749D4ABBA3284794D8AE9</fingerprint>
  </Signature>
</AcquirerStatusRes>}

  ACQUIRER_SUCCEEDED_BUT_WRONG_SIGNATURE_STATUS_RESPONSE = %{<?xml version="1.0" encoding="UTF-8"?>
<AcquirerStatusRes xmlns="http://www.idealdesk.com/Message" version="1.1.0">
  <createDateTimeStamp>2001-12-17T09:30:47.0Z</createDateTimeStamp>
  <Acquirer>
     <acquirerID>1234</acquirerID>
  </Acquirer>
  <Transaction>
     <transactionID>0001023456789112</transactionID>
     <status>Success</status>
     <consumerName>Onderheuvel</consumerName>
     <consumerAccountNumber>0949298989</consumerAccountNumber>
     <consumerCity>DEN HAAG</consumerCity>
  </Transaction>
  <Signature>
    <signatureValue>WRONG</signatureValue>
    <fingerprint>1E15A00E3D7DF085768749D4ABBA3284794D8AE9</fingerprint>
  </Signature>
</AcquirerStatusRes>}

  ACQUIRER_FAILED_STATUS_RESPONSE = %{<?xml version="1.0" encoding="UTF-8"?>
<AcquirerStatusRes xmlns="http://www.idealdesk.com/Message" version="1.1.0">
  <createDateTimeStamp>2001-12-17T09:30:47.0Z</createDateTimeStamp>
  <Acquirer>
     <acquirerID>1234</acquirerID>
  </Acquirer>
  <Transaction>
     <transactionID>0001023456789112</transactionID>
     <status>Failed</status>
     <consumerName>Onderheuvel</consumerName>
     <consumerAccountNumber>0949298989</consumerAccountNumber>
     <consumerCity>DEN HAAG</consumerCity>
  </Transaction>
  <Signature>
    <signatureValue>db82/jpJRvKQKoiDvu33X0yoDAQpayJOaW2Y8zbR1qk1i3epvTXi+6g+QVBY93YzGv4w+Va+vL3uNmzyRjYsm2309d1CWFVsn5Mk24NLSvhYfwVHEpznyMqizALEVUNSoiSHRkZUDfXowBAyLT/tQVGbuUuBj+TKblY826nRa7U=</signatureValue>
    <fingerprint>1E15A00E3D7DF085768749D4ABBA3284794D8AE9</fingerprint>
  </Signature>
</AcquirerStatusRes>}

  ERROR_RESPONSE = %{<?xml version="1.0" encoding="UTF-8"?>
<ErrorRes xmlns="http://www.idealdesk.com/Message" version="1.1.0">
  <createDateTimeStamp>2001-12-17T09:30:47.0Z</createDateTimeStamp>
  <Error>
    <errorCode>SO1000</errorCode>
    <errorMessage>Failure in system</errorMessage>
    <errorDetail>System generating error: issuer</errorDetail>
    <suggestedAction></suggestedAction>
    <suggestedExpirationPeriod></suggestedExpirationPeriod>
    <consumerMessage>Betalen met iDEAL is nu niet mogelijk.</consumerMessage>
  </Error>
</ErrorRes>}

  setup_ideal_gateway!
end