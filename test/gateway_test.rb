# encoding: utf-8

require File.expand_path('../helper', __FILE__)

module IdealTestCases
  # This method is called at the end of the file when all fixture data has been loaded.
  def self.setup_ideal_gateway!
    Ideal::Gateway.class_eval do
      self.acquirer = :rabobank

      self.merchant_id = '123456789'

      self.passphrase = 'passphrase'
      self.private_key = PRIVATE_KEY
      self.private_certificate = PRIVATE_CERTIFICATE
      self.ideal_certificate = IDEAL_CERTIFICATE
    end
  end

  VALID_PURCHASE_OPTIONS = {
    :issuer_id         => '99999IBAN',
    :expiration_period => 'PT10M',
    :return_url        => 'http://return_to.example.com',
    :order_id          => '12345678901',
    :description       => 'A classic Dutch windmill',
    :entrance_code     => '1234'
  }
  

  class ClassMethodsTest < Test::Unit::TestCase
    def test_merchant_id
      assert_equal Ideal::Gateway.merchant_id, '123456789'
    end

    def test_verify_live_url_for_ing
      Ideal::Gateway.acquirer = :ing
      assert_equal 'https://ideal.secure-ing.com/ideal/iDeal', Ideal::Gateway.live_url
    end

    def test_verify_live_url_for_rabobank
      Ideal::Gateway.acquirer = :rabobank
      assert_equal 'https://ideal.rabobank.nl/ideal/iDealv3', Ideal::Gateway.live_url
    end

    def test_verify_live_urls_for_abnamro
      Ideal::Gateway.acquirer = :abnamro
      assert_equal 'https://abnamro.ideal-payment.de/ideal/iDeal', Ideal::Gateway.live_url
    end

    def test_does_not_allow_configuration_of_unknown_acquirers
      assert_raise(ArgumentError) do
        Ideal::Gateway.acquirer = :unknown
      end
    end

    def test_acquirers
      assert_equal 'https://ideal.rabobank.nl/ideal/iDealv3', Ideal::Gateway.acquirers['rabobank']['live_url']
      assert_equal 'https://ideal.secure-ing.com/ideal/iDeal', Ideal::Gateway.acquirers['ing']['live_url']
      assert_equal 'https://abnamro.ideal-payment.de/ideal/iDeal', Ideal::Gateway.acquirers['abnamro']['live_url']
    end

    def test_private_certificate_returns_a_loaded_Certificate_instance
      assert_equal Ideal::Gateway.private_certificate.to_text,
        OpenSSL::X509::Certificate.new(PRIVATE_CERTIFICATE).to_text
    end

    def test_private_key_returns_a_loaded_PKey_RSA_instance
      assert_equal Ideal::Gateway.private_key.to_text,
        OpenSSL::PKey::RSA.new(PRIVATE_KEY, Ideal::Gateway.passphrase).to_text
    end

    def test_ideal_certificate_returns_a_loaded_Certificate_instance
      assert_equal Ideal::Gateway.ideal_certificate.to_text,
        OpenSSL::X509::Certificate.new(IDEAL_CERTIFICATE).to_text
    end
  end

  class GeneralTest < Test::Unit::TestCase
    def setup
      @gateway = Ideal::Gateway.new
    end

    def test_optional_initialization_options
      assert_equal 0, Ideal::Gateway.new.sub_id
      assert_equal 1, Ideal::Gateway.new(:sub_id => 1).sub_id
    end

    def test_returns_the_test_url_when_in_the_test_env
      Ideal::Gateway.acquirer = :ing
      Ideal::Gateway.environment = :test
      assert_equal Ideal::Gateway.test_url, @gateway.send(:request_url)
    end

    def test_returns_the_live_url_when_not_in_the_test_env
      Ideal::Gateway.acquirer = :ing
      Ideal::Gateway.environment = :live
      assert_equal Ideal::Gateway.live_url, @gateway.send(:request_url)
    end

    def test_returns_created_at_timestamp
      timestamp = '2001-12-17T09:30:47.000Z'
      Time.any_instance.stubs(:gmtime).returns(DateTime.parse(timestamp))

      assert_equal timestamp, @gateway.send(:created_at_timestamp)
    end

    def test_digest_value_generation
      sha256 = OpenSSL::Digest::SHA256.new
      OpenSSL::Digest::SHA256.stubs(:new).returns(sha256)
      xml = Nokogiri::XML::Builder.new do |xml|
        xml.request do |xml|
          xml.content 'digest test'
          @gateway.send(:sign!, xml)
        end
      end
      digest_value = xml.doc.at_xpath('//xmlns:DigestValue', 'xmlns' => 'http://www.w3.org/2000/09/xmldsig#').text
      xml.doc.at_xpath('//xmlns:Signature', 'xmlns' => 'http://www.w3.org/2000/09/xmldsig#').remove
      canonical = xml.doc.canonicalize(Nokogiri::XML::XML_C14N_EXCLUSIVE_1_0)
      digest = sha256.digest canonical
      expected_digest_value = strip_whitespace(Base64.encode64(strip_whitespace(digest)))
      assert_equal expected_digest_value, digest_value
    end


    def test_signature_value_generation
      sha256 = OpenSSL::Digest::SHA256.new
      OpenSSL::Digest::SHA256.stubs(:new).returns(sha256)
      xml = Nokogiri::XML::Builder.new do |xml|
        xml.request do |xml|
          xml.content 'signature test'
          @gateway.send(:sign!, xml)
        end
      end
      signature_value = xml.doc.at_xpath('//xmlns:SignatureValue', 'xmlns' => 'http://www.w3.org/2000/09/xmldsig#').text
      signed_info = xml.doc.at_xpath('//xmlns:SignedInfo', 'xmlns' => 'http://www.w3.org/2000/09/xmldsig#')
      canonical = signed_info.canonicalize(Nokogiri::XML::XML_C14N_EXCLUSIVE_1_0)
      signature = Ideal::Gateway.private_key.sign(sha256, canonical)
      expected_signature_value = strip_whitespace(Base64.encode64(strip_whitespace(signature)))
      assert_equal expected_signature_value, signature_value
    end

    def test_key_name_generation
      expected_token = Digest::SHA1.hexdigest(OpenSSL::X509::Certificate.new(PRIVATE_CERTIFICATE).to_der).upcase
      assert_equal expected_token, @gateway.send(:fingerprint)
    end


    # def test_token_code_generation
    #   Ideal::Gateway.acquirer = :ing
    #   message = "Top\tsecret\tman.\nI could tell you, but then I'd have to kill you…"
    #   stripped_message = message.gsub(/\s/m, '')
    # 
    #   sha1 = OpenSSL::Digest::SHA1.new
    #   OpenSSL::Digest::SHA1.stubs(:new).returns(sha1)
    # 
    #   signature = Ideal::Gateway.private_key.sign(sha1, stripped_message)
    #   encoded_signature = Base64.encode64(signature).strip.gsub(/\n/, '')
    # 
    #   assert_equal encoded_signature, @gateway.send(:token_code, message)
    # end

    def test_posts_data_with_ssl_to_request_url_and_return_the_correct_response_for_test
      Ideal::Gateway.environment = :test
      Ideal::Response.expects(:new).with('response', :test => true)
      @gateway.expects(:ssl_post).with(@gateway.request_url, 'data').returns('response')
      @gateway.send(:post_data, @gateway.request_url, 'data', Ideal::Response)
    end

    def test_posts_data_with_ssl_to_request_url_and_return_the_correct_response_for_live
      Ideal::Gateway.environment = :live
      Ideal::Response.expects(:new).with('response', :test => false)
      @gateway.expects(:ssl_post).with(@gateway.request_url, 'data').returns('response')
      @gateway.send(:post_data, @gateway.request_url, 'data', Ideal::Response)
    end
  end

  class XMLBuildingTest < Test::Unit::TestCase
    def setup
      @gateway = Ideal::Gateway.new
      @gateway.stubs(:created_at_timestamp).returns('created_at_timestamp')
      @gateway.stubs(:digest_value).returns('digest_value')
      @gateway.stubs(:signature_value).returns('signature_value')
      @gateway.stubs(:fingerprint).returns('fingerprint')
    end

    def test_transaction_request_xml
      options = {
        issuer_id: 'issuer_id',
        return_url: 'return_url',
        order_id: 'purchase_id',
        expiration_period: 'expiration_period',
        description: 'description',
        entrance_code: 'entrance_code'
      }
      xml = @gateway.send(:build_transaction_request, 'amount', options)
      assert_equal xml, TRANSACTION_REQUEST
    end
    
    def test_status_request_xml
      options = {
        transaction_id: 'transaction_id',
      }
      xml = @gateway.send(:build_status_request, options)
      assert_equal xml, STATUS_REQUEST
    end
    
    def test_directory_request_xml
      xml = @gateway.send(:build_directory_request)
      assert_equal xml, DIRECTORY_REQUEST
    end
    
 
  end

  class ErroneousInputTest < Test::Unit::TestCase
  
    def setup
      @gateway = Ideal::Gateway.new
      @gateway.stubs(:created_at_timestamp).returns('created_at_timestamp')
      @gateway.stubs(:digest_value).returns('digest_value')
      @gateway.stubs(:signature_value).returns('signature_value')
      @gateway.stubs(:fingerprint).returns('fingerprint')
      
      @transaction_id = '0001023456789112'

    end
    
    def test_valid_with_valid_options
      assert_not_nil @gateway.send(:build_transaction_request, 4321, VALID_PURCHASE_OPTIONS)
    end
    
    def test_checks_that_fields_are_not_too_long
      assert_raise ArgumentError do
        @gateway.send(:build_transaction_request, 1234567890123, VALID_PURCHASE_OPTIONS) # 13 chars
      end
    
      [
        [:order_id, '12345678901234567'], # 17 chars,
        [:description, '123456789012345678901234567890123'], # 33 chars
        [:entrance_code, '12345678901234567890123456789012345678901'] # 41
      ].each do |key, value|
        options = VALID_PURCHASE_OPTIONS.dup
        options[key] = value
    
        assert_raise ArgumentError do
          @gateway.send(:build_transaction_request, 4321, options)
        end
      end
    end
  
    def test_build_transaction_request_body_raises_ArgumentError_with_missing_required_options
      options = VALID_PURCHASE_OPTIONS.dup
      options.keys.each do |key|
        options.delete(key)
  
        assert_raise(ArgumentError) do
          @gateway.send(:build_transaction_request, 100, options)
        end
      end
    end
  
    def test_checks_that_fields_do_not_contain_diacritical_characters
      assert_raise ArgumentError do
        @gateway.send(:build_transaction_request, 'graphème', VALID_PURCHASE_OPTIONS)
      end
  
      [:order_id, :description, :entrance_code].each do |key, value|
        options = VALID_PURCHASE_OPTIONS.dup
        options[key] = 'graphème'
  
        assert_raise ArgumentError do
          @gateway.send(:build_transaction_request, 4321, options)
        end
      end
    end
    
    def test_builds_a_status_request_body_raises_ArgumentError_with_missing_required_options
      assert_raise(ArgumentError) do
        @gateway.send(:build_status_request, {})
      end
    end
    
  end

  class GeneralResponseTest < Test::Unit::TestCase
    def test_resturns_if_it_is_a_test_request
      assert Ideal::Response.new(DIRECTORY_RESPONSE_WITH_MULTIPLE_ISSUERS, :test => true).test?

      assert !Ideal::Response.new(DIRECTORY_RESPONSE_WITH_MULTIPLE_ISSUERS, :test => false).test?
      assert !Ideal::Response.new(DIRECTORY_RESPONSE_WITH_MULTIPLE_ISSUERS).test?
    end
  end

  class SuccessfulResponseTest < Test::Unit::TestCase
    def setup
      @response = Ideal::Response.new(DIRECTORY_RESPONSE_WITH_MULTIPLE_ISSUERS)
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
      @response = Ideal::Response.new(ERROR_RESPONSE)
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
      @gateway = Ideal::Gateway.new
    end

    def test_returns_a_list_with_only_one_issuer
      @gateway.stubs(:build_directory_request_body).returns('the request body')
      @gateway.expects(:ssl_post).with(@gateway.request_url, 'the request body').returns(DIRECTORY_RESPONSE_WITH_ONE_ISSUER)

      expected_issuers = [{ :id => '1006', :name => 'ABN AMRO Bank' }]

      directory_response = @gateway.issuers
      assert_instance_of Ideal::DirectoryResponse, directory_response
      assert_equal expected_issuers, directory_response.list
    end

    def test_returns_list_of_issuers_from_response
      @gateway.stubs(:build_directory_request_body).returns('the request body')
      @gateway.expects(:ssl_post).with(@gateway.request_url, 'the request body').returns(DIRECTORY_RESPONSE_WITH_MULTIPLE_ISSUERS)

      expected_issuers = [
        { :id => '1006', :name => 'ABN AMRO Bank' },
        { :id => '1003', :name => 'Postbank' },
        { :id => '1005', :name => 'Rabobank' },
        { :id => '1017', :name => 'Asr bank' },
        { :id => '1023', :name => 'Van Lanschot' }
      ]

      directory_response = @gateway.issuers
      assert_instance_of Ideal::DirectoryResponse, directory_response
      assert_equal expected_issuers, directory_response.list
    end
  end

  class SetupPurchaseTest < Test::Unit::TestCase
    def setup
      @gateway = Ideal::Gateway.new

      @gateway.stubs(:build_transaction_request_body).with(4321, VALID_PURCHASE_OPTIONS).returns('the request body')
      @gateway.expects(:ssl_post).with(@gateway.request_url, 'the request body').returns(ACQUIRER_TRANSACTION_RESPONSE)

      @setup_purchase_response = @gateway.setup_purchase(4321, VALID_PURCHASE_OPTIONS)
    end

    def test_setup_purchase_returns_IdealTransactionResponse
      assert_instance_of Ideal::TransactionResponse, @setup_purchase_response
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
      @gateway = Ideal::Gateway.new

      @gateway.stubs(:build_status_request_body).
        with(:transaction_id => '0001023456789112').returns('the request body')
    end

    def test_setup_purchase_returns_IdealStatusResponse
      expects_request_and_returns ACQUIRER_SUCCEEDED_STATUS_RESPONSE
      assert_instance_of Ideal::StatusResponse, @gateway.capture('0001023456789112')
    end

    # Because we don't have a real private key and certificate we stub
    # verified? to return true. However, this is properly tested in the remote
    # tests.
    def test_capture_of_successful_payment
      Ideal::StatusResponse.any_instance.stubs(:verified?).returns(true)

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

    def test_capture_of_consumer_fields
      expects_request_and_returns ACQUIRER_SUCCEEDED_STATUS_RESPONSE
      capture_response = @gateway.capture('0001023456789112')

      assert_equal '0949298989', capture_response.consumer_account_number
      assert_equal 'Onderheuvel', capture_response.consumer_name
      assert_equal 'DEN HAAG', capture_response.consumer_city
    end

    def test_returns_status
      response = Ideal::StatusResponse.new(ACQUIRER_SUCCEEDED_STATUS_RESPONSE)
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
      @gateway.expects(:ssl_post).with(@gateway.request_url, 'the request body').returns(str)
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

  TRANSACTION_REQUEST =  @transaction_xml = %{<?xml version="1.0" encoding="UTF-8"?>
<AcquirerTrxReq xmlns="http://www.idealdesk.com/ideal/messages/mer-acq/3.3.1" version="3.3.1">
  <createDateTimestamp>created_at_timestamp</createDateTimestamp>
  <Issuer>
    <issuerID>issuer_id</issuerID>
  </Issuer>
  <Merchant>
    <merchantID>123456789</merchantID>
    <subID>0</subID>
    <merchantReturnURL>return_url</merchantReturnURL>
  </Merchant>
  <Transaction>
    <purchaseID>purchase_id</purchaseID>
    <amount>amount</amount>
    <currency>EUR</currency>
    <expirationPeriod>expiration_period</expirationPeriod>
    <language>nl</language>
    <description>description</description>
    <entranceCode>entrance_code</entranceCode>
  </Transaction>
  <Signature xmlns="http://www.w3.org/2000/09/xmldsig#">
    <SignedInfo>
      <CanonicalizationMethod Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"/>
      <SignatureMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"/>
      <Reference URI="">
        <Transforms>
          <Transform Algorithm="http://www.w3.org/2000/09/xmldsig#enveloped-signature"/>
        </Transforms>
        <DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"/>
        <DigestValue>digest_value</DigestValue>
      </Reference>
    </SignedInfo>
    <SignatureValue>signature_value</SignatureValue>
    <KeyInfo>
      <KeyName>fingerprint</KeyName>
    </KeyInfo>
  </Signature>
</AcquirerTrxReq>
}

  DIRECTORY_REQUEST = %{<?xml version="1.0" encoding="UTF-8"?>
<DirectoryReq xmlns="http://www.idealdesk.com/ideal/messages/mer-acq/3.3.1" version="3.3.1">
  <createDateTimestamp>created_at_timestamp</createDateTimestamp>
  <Merchant>
    <merchantID>123456789</merchantID>
    <subID>0</subID>
  </Merchant>
  <Signature xmlns="http://www.w3.org/2000/09/xmldsig#">
    <SignedInfo>
      <CanonicalizationMethod Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"/>
      <SignatureMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"/>
      <Reference URI="">
        <Transforms>
          <Transform Algorithm="http://www.w3.org/2000/09/xmldsig#enveloped-signature"/>
        </Transforms>
        <DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"/>
        <DigestValue>digest_value</DigestValue>
      </Reference>
    </SignedInfo>
    <SignatureValue>signature_value</SignatureValue>
    <KeyInfo>
      <KeyName>fingerprint</KeyName>
    </KeyInfo>
  </Signature>
</DirectoryReq>
}

  STATUS_REQUEST = %{<?xml version="1.0" encoding="UTF-8"?>
<AcquirerStatusReq xmlns="http://www.idealdesk.com/ideal/messages/mer-acq/3.3.1" version="3.3.1">
  <createDateTimestamp>created_at_timestamp</createDateTimestamp>
  <Merchant>
    <merchantID>123456789</merchantID>
    <subID>0</subID>
  </Merchant>
  <Transaction>
    <transactionID>transaction_id</transactionID>
  </Transaction>
  <Signature xmlns="http://www.w3.org/2000/09/xmldsig#">
    <SignedInfo>
      <CanonicalizationMethod Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"/>
      <SignatureMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"/>
      <Reference URI="">
        <Transforms>
          <Transform Algorithm="http://www.w3.org/2000/09/xmldsig#enveloped-signature"/>
        </Transforms>
        <DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"/>
        <DigestValue>digest_value</DigestValue>
      </Reference>
    </SignedInfo>
    <SignatureValue>signature_value</SignatureValue>
    <KeyInfo>
      <KeyName>fingerprint</KeyName>
    </KeyInfo>
  </Signature>
</AcquirerStatusReq>
}
  setup_ideal_gateway!
end