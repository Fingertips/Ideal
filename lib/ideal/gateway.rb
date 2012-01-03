# encoding: utf-8

require 'openssl'
require 'net/https'
require 'base64'
require 'digest/sha1'

module Ideal
  # === Response classes
  # 
  # * Response
  # * TransactionResponse
  # * StatusResponse
  # * DirectoryResponse
  # 
  # See the Response class for more information on errors.
  class Gateway
    AUTHENTICATION_TYPE = 'SHA1_RSA'
    LANGUAGE = 'nl'
    CURRENCY = 'EUR'
    API_VERSION = '1.1.0'
    XML_NAMESPACE = 'http://www.idealdesk.com/Message'

    def self.acquirers
      Ideal::ACQUIRERS
    end

    class << self
      # Returns the current acquirer used
      attr_reader :acquirer

      # Holds the environment in which the run (default is test)
      attr_accessor :environment

      # Holds the global iDEAL merchant id. Make sure to use a string with
      # leading zeroes if needed.
      attr_accessor :merchant_id

      # Holds the passphrase that should be used for the merchant private_key.
      attr_accessor :passphrase

      # Holds the test and production urls for your iDeal acquirer.
      attr_accessor :live_url,             :test_url

      # For ABN AMRO only assign the three separate directory, transaction and status urls.
      attr_accessor :live_directory_url,   :test_directory_url
      attr_accessor :live_transaction_url, :test_transaction_url
      attr_accessor :live_status_url,      :test_status_url
    end

    # Environment defaults to test
    self.environment = :test

    # Loads the global merchant private_key from disk.
    def self.private_key_file=(pkey_file)
      self.private_key = File.read(pkey_file)
    end

    # Instantiates and assings a OpenSSL::PKey::RSA instance with the
    # provided private key data.
    def self.private_key=(pkey_data)
      @private_key = OpenSSL::PKey::RSA.new(pkey_data, passphrase)
    end

    # Returns the global merchant private_certificate.
    def self.private_key
      @private_key
    end

    # Loads the global merchant private_certificate from disk.
    def self.private_certificate_file=(certificate_file)
      self.private_certificate = File.read(certificate_file)
    end

    # Instantiates and assings a OpenSSL::X509::Certificate instance with the
    # provided private certificate data.
    def self.private_certificate=(certificate_data)
      @private_certificate = OpenSSL::X509::Certificate.new(certificate_data)
    end

    # Returns the global merchant private_certificate.
    def self.private_certificate
      @private_certificate
    end

    # Loads the global merchant ideal_certificate from disk.
    def self.ideal_certificate_file=(certificate_file)
      self.ideal_certificate = File.read(certificate_file)
    end

    # Instantiates and assings a OpenSSL::X509::Certificate instance with the
    # provided iDEAL certificate data.
    def self.ideal_certificate=(certificate_data)
      @ideal_certificate = OpenSSL::X509::Certificate.new(certificate_data)
    end

    # Returns the global merchant ideal_certificate.
    def self.ideal_certificate
      @ideal_certificate
    end

    # Returns whether we're in test mode or not.
    def self.test?
      environment.to_sym == :test
    end

    # Set the correct acquirer url based on the specific Bank
    # Currently supported arguments: :ing, :rabobank, :abnamro
    #
    # Ideal::Gateway.acquirer = :ing
    def self.acquirer=(acquirer)
      @acquirer = acquirer.to_s
      if self.acquirers.include?(@acquirer)
        acquirers[@acquirer].each do |attr, value|
          send("#{attr}=", value)
        end
      else
        raise ArgumentError, "Unknown acquirer `#{acquirer}', please choose one of: #{self.acquirers.keys.join(', ')}"
      end
    end

    # Returns true when the acquirer was set to :abnamro
    def self.abn_amro?
      acquirer.to_sym == :abnamro
    end

    # Returns the merchant `subID' being used for this Gateway instance.
    # Defaults to 0.
    attr_reader :sub_id

    # Initializes a new Gateway instance.
    #
    # You can optionally specify <tt>:sub_id</tt>. Defaults to 0.
    def initialize(options = {})
      @sub_id = options[:sub_id] || 0
    end

    # Returns the endpoint for a certain request.
    #
    # Automatically uses test or live URLs based on the configuration.
    def request_url(request_type)
      self.class.send("#{self.class.environment}#{request_url_prefix(request_type)}_url")
    end

    # Sends a directory request to the acquirer and returns an
    # DirectoryResponse. Use DirectoryResponse#list to receive the
    # actuall array of available issuers.
    #
    #   gateway.issuers.list # => [{ :id => '1006', :name => 'ABN AMRO Bank' }, …]
    def issuers
      post_data request_url(:directory), build_directory_request_body, DirectoryResponse
    end

    # Starts a purchase by sending an acquirer transaction request for the
    # specified +money+ amount in EURO cents.
    #
    # On success returns an TransactionResponse with the #transaction_id
    # which is needed for the capture step. (See capture for an example.)
    #
    # The iDEAL specification states that it is _not_ allowed to use another
    # window or frame when redirecting the consumer to the issuer. So the
    # entire merchant’s page has to be replaced by the selected issuer’s page.
    #
    # === Options
    #
    # Note that all options that have a character limit are _also_ checked
    # for diacritical characters. If it does contain diacritical characters,
    # or exceeds the character limit, an ArgumentError is raised.
    #
    # ==== Required
    #
    # * <tt>:issuer_id</tt> - The <tt>:id</tt> of an issuer available at the acquirer to which the transaction should be made.
    # * <tt>:order_id</tt> - The order number. Limited to 12 characters.
    # * <tt>:description</tt> - A description of the transaction. Limited to 32 characters.
    # * <tt>:return_url</tt> - A URL on the merchant’s system to which the consumer is redirected _after_ payment. The acquirer will add the following GET variables:
    #   * <tt>trxid</tt> - The <tt>:order_id</tt>.
    #   * <tt>ec</tt> - The <tt>:entrance_code</tt> _if_ it was specified.
    #
    # ==== Optional
    #
    # * <tt>:entrance_code</tt> - This code is an abitrary token which can be used to identify the transaction besides the <tt>:order_id</tt>. Limited to 40 characters.
    # * <tt>:expiration_period</tt> - The period of validity of the payment request measured from the receipt by the issuer. The consumer must approve the payment within this period, otherwise the StatusResponse#status will be set to `Expired'. E.g., consider an <tt>:expiration_period</tt> of `P3DT6H10M':
    #   * P: relative time designation.
    #   * 3 days.
    #   * T: separator.
    #   * 6 hours.
    #   * 10 minutes.
    #
    # === Example
    #
    #   transaction_response = gateway.setup_purchase(4321, valid_options)
    #   if transaction_response.success?
    #     @purchase.update_attributes!(:transaction_id => transaction_response.transaction_id)
    #     redirect_to transaction_response.service_url
    #   end
    #
    # See the Gateway class description for a more elaborate example.
    def setup_purchase(money, options)
      post_data request_url(:transaction), build_transaction_request_body(money, options), TransactionResponse
    end

    # Sends a acquirer status request for the specified +transaction_id+ and
    # returns an StatusResponse.
    #
    # It is _your_ responsibility as the merchant to check if the payment has
    # been made until you receive a response with a finished status like:
    # `Success', `Cancelled', `Expired', everything else equals `Open'.
    #
    # === Example
    #
    #   capture_response = gateway.capture(@purchase.transaction_id)
    #   if capture_response.success?
    #     @purchase.update_attributes!(:paid => true)
    #     flash[:notice] = "Congratulations, you are now the proud owner of a Dutch windmill!"
    #   end
    #
    # See the Gateway class description for a more elaborate example.
    def capture(transaction_id)
      post_data request_url(:status), build_status_request_body(:transaction_id => transaction_id), StatusResponse
    end

    private

    # Returns the prefix to locate the setting for a certain request type. Only applies
    # in the case of ABN AMRO because they use more than one endpoint.
    def request_url_prefix(request_type)
      (request_type && self.class.abn_amro?) ? "_#{request_type.to_s}" : nil
    end

    def ssl_post(url, body)
      response = REST.post(url, body, {}, {
        :tls_verify      => true,
        :tls_key         => self.class.private_key,
        :tls_certificate => self.class.private_certificate
      })
      response.body
    end

    def post_data(gateway_url, data, response_klass)
      response_klass.new(ssl_post(gateway_url, data), :test => self.class.test?)
    end

    # This is the list of charaters that are not supported by iDEAL according
    # to the PHP source provided by ING plus the same in capitals.
    DIACRITICAL_CHARACTERS = /[ÀÁÂÃÄÅÇŒÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÚÛÜÝàáâãäåçæèéêëìíîïñòóôõöøùúûüý]/ #:nodoc:

    # Raises an ArgumentError if the +string+ exceeds the +max_length+ amount
    # of characters or contains any diacritical characters.
    def enforce_maximum_length(key, string, max_length)
      raise ArgumentError, "The value for `#{key}' exceeds the limit of #{max_length} characters." if string.length > max_length
      raise ArgumentError, "The value for `#{key}' contains diacritical characters `#{string}'." if string =~ DIACRITICAL_CHARACTERS
    end

    # Returns the +token+ as specified in section 2.8.4 of the iDeal specs.
    #
    # This is the params['AcquirerStatusRes']['Signature']['fingerprint'] in
    # a StatusResponse instance.
    def token
      Digest::SHA1.hexdigest(self.class.private_certificate.to_der).upcase
    end

    def strip_whitespace(str)
      self.class.abn_amro? ? str.gsub(/(\f|\n|\r|\t|\v)/m, '') : str.gsub(/\s/m,'')
    end

    # Creates a +tokenCode+ from the specified +message+.
    def token_code(message)
      signature = self.class.private_key.sign(OpenSSL::Digest::SHA1.new, strip_whitespace(message))
      strip_whitespace(Base64.encode64(signature))
    end

    # Returns a string containing the current UTC time, formatted as per the
    # iDeal specifications, except we don't use miliseconds.
    def created_at_timestamp
      Time.now.gmtime.strftime("%Y-%m-%dT%H:%M:%S.000Z")
    end

    def camelize(lower_case_and_underscored_word, first_letter_in_uppercase = true)
      if first_letter_in_uppercase
        lower_case_and_underscored_word.to_s.gsub(/\/(.?)/) { "::#{$1.upcase}" }.gsub(/(?:^|_)(.)/) { $1.upcase }
      else
        lower_case_and_underscored_word.to_s[0].chr.downcase + camelize(lower_case_and_underscored_word)[1..-1]
      end
    end

    # iDeal doesn't really seem to care about nice looking keys in their XML.
    # Probably some Java XML class, hence the method name.
    def javaize_key(key)
      key = key.to_s
      case key
      when 'acquirer_transaction_request'
        'AcquirerTrxReq'
      when 'acquirer_status_request'
        'AcquirerStatusReq'
      when 'directory_request'
        'DirectoryReq'
      when 'issuer', 'merchant', 'transaction'
        key.capitalize
      when 'created_at'
        'createDateTimeStamp'
      when 'merchant_return_url'
        'merchantReturnURL'
      when 'token_code', 'expiration_period', 'entrance_code'
        key[0,1] + camelize(key)[1..-1]
      when /^(\w+)_id$/
        "#{$1}ID"
      else
        key
      end
    end

    # Creates xml with a given hash of tag-value pairs according to the iDeal
    # requirements.
    def xml_for(name, tags_and_values)
      xml = Builder::XmlMarkup.new
      xml.instruct!
      xml.tag!(javaize_key(name), 'xmlns' => XML_NAMESPACE, 'version' => API_VERSION) { xml_from_array(xml, tags_and_values) }
      xml.target!
    end

    # Recursively creates xml for a given hash of tag-value pair. Uses
    # javaize_key on the tags to create the tags needed by iDeal.
    def xml_from_array(builder, tags_and_values)
      tags_and_values.each do |tag, value|
        tag = javaize_key(tag)
        if value.is_a?(Array)
          builder.tag!(tag) { xml_from_array(builder, value) }
        else
          builder.tag!(tag, value)
        end
      end
    end

    def requires!(options, *keys)
      missing = keys - options.keys
      unless missing.empty?
        raise ArgumentError, "Missing required options: #{missing.map { |m| m.to_s }.join(', ')}"
      end
    end

    def build_status_request_body(options)
      requires!(options, :transaction_id)

      timestamp = created_at_timestamp
      message = "#{timestamp}#{self.class.merchant_id}#{@sub_id}#{options[:transaction_id]}"

      xml_for(:acquirer_status_request, [
        [:created_at,       timestamp],
        [:merchant, [
          [:merchant_id,    self.class.merchant_id],
          [:sub_id,         @sub_id],
          [:authentication, AUTHENTICATION_TYPE],
          [:token,          token],
          [:token_code,     token_code(message)]
        ]],

        [:transaction, [
          [:transaction_id, options[:transaction_id]]
        ]]
      ])
    end

    def build_directory_request_body
      timestamp = created_at_timestamp
      message = "#{timestamp}#{self.class.merchant_id}#{@sub_id}"

      xml_for(:directory_request, [
        [:created_at,       timestamp],
        [:merchant, [
          [:merchant_id,    self.class.merchant_id],
          [:sub_id,         @sub_id],
          [:authentication, AUTHENTICATION_TYPE],
          [:token,          token],
          [:token_code,     token_code(message)]
        ]]
      ])
    end

    def build_transaction_request_body(money, options)
      requires!(options, :issuer_id, :expiration_period, :return_url, :order_id, :description, :entrance_code)

      enforce_maximum_length(:money, money.to_s, 12)
      enforce_maximum_length(:order_id, options[:order_id], 12)
      enforce_maximum_length(:description, options[:description], 32)
      enforce_maximum_length(:entrance_code, options[:entrance_code], 40)

      timestamp = created_at_timestamp
      message = timestamp +
                options[:issuer_id] +
                self.class.merchant_id +
                @sub_id.to_s +
                options[:return_url] +
                options[:order_id] +
                money.to_s +
                CURRENCY +
                LANGUAGE +
                options[:description] +
                options[:entrance_code]

      xml_for(:acquirer_transaction_request, [
        [:created_at, timestamp],
        [:issuer, [[:issuer_id, options[:issuer_id]]]],

        [:merchant, [
          [:merchant_id,         self.class.merchant_id],
          [:sub_id,              @sub_id],
          [:authentication,      AUTHENTICATION_TYPE],
          [:token,               token],
          [:token_code,          token_code(message)],
          [:merchant_return_url, options[:return_url]]
        ]],

        [:transaction, [
          [:purchase_id,       options[:order_id]],
          [:amount,            money],
          [:currency,          CURRENCY],
          [:expiration_period, options[:expiration_period]],
          [:language,          LANGUAGE],
          [:description,       options[:description]],
          [:entrance_code,     options[:entrance_code]]
        ]]
      ])
    end
  end
end