# encoding: utf-8

require 'openssl'
require 'rest'

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
      attr_accessor :live_url, :test_url
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

    # Returns the merchant `subID' being used for this Gateway instance.
    # Defaults to 0.
    attr_reader :sub_id

    # Initializes a new Gateway instance.
    #
    # You can optionally specify <tt>:sub_id</tt>. Defaults to 0.
    def initialize(options = {})
      @sub_id = options[:sub_id] || 0
    end

    # Returns the endpoint for the request.
    #
    # Automatically uses test or live URLs based on the configuration.
    def request_url
      self.class.send("#{self.class.environment}_url")
    end

    # Sends a directory request to the acquirer and returns an
    # DirectoryResponse. Use DirectoryResponse#list to receive the
    # actuall array of available issuers.
    #
    #   gateway.issuers.list # => [{ :id => '1006', :name => 'ABN AMRO Bank' }, …]
    def issuers
      directory_request = DirectoryRequest.new(
        :merchant_id => self.class.merchant_id,
        :sub_id => @sub_id,
        :key => Digest::SHA1.hexdigest(self.class.private_certificate.to_der)
      ).to_xml

      post_data(request_url, 
                sign_xml(directory_request), 
                DirectoryResponse) 
    end

    # Starts a purchase by sending an acquirer transaction request for the
    # specified +money+ amount in EURO with max 2 decimal places.
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
    # * <tt>:return_url</tt> - A URL on the merchant's system to which the consumer is redirected _after_ payment. The acquirer will add the following GET variables:
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
      requires!(options, :issuer_id, :expiration_period, :return_url, :order_id, :description, :entrance_code)

      enforce_maximum_length(:money, money.to_s, 12)
      enforce_maximum_length(:order_id, options[:order_id], 12)
      enforce_maximum_length(:description, options[:description], 32)
      enforce_maximum_length(:entrance_code, options[:entrance_code], 40)

      transaction_request = TransactionRequest.new(
        :merchant_id => self.class.merchant_id,
        :sub_id => @sub_id,
        :return_url => options[:return_url],
        :issuer_id => options[:issuer_id],
        :purchase_id => options[:order_id],
        :amount => money,
        :currency => CURRENCY,
        :expiration_period => options[:expiration_period],
        :language => LANGUAGE,
        :description => options[:description],
        :entrance_code => options[:entrance_code],
        :key => Digest::SHA1.hexdigest(self.class.private_certificate.to_der)
      ).to_xml

      post_data(request_url,
                sign_xml(transaction_request), 
                TransactionResponse)
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
      requires!({:transaction_id => transaction_id}, :transaction_id)

      status_request = StatusRequest.new(
        :merchant_id => self.class.merchant_id,
        :sub_id => @sub_id,
        :transaction_id => transaction_id,
        :key => Digest::SHA1.hexdigest(self.class.private_certificate.to_der)
      ).to_xml

      post_data(request_url, 
                sign_xml(status_request), 
                StatusResponse)
    end

    private

    def ssl_post(url, body)
      log('URL', url)
      log('Request', body)
      
      response = Rest::Client.new.post(
        url,
        :body => body
      )

      log('Response', response.body)
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

    def sign_xml(xml)
      unsigned_document = Xmldsig::SignedDocument.new(xml)
      signed_xml = unsigned_document.sign do |data|
        self.class.private_key.sign(OpenSSL::Digest::SHA256.new, data)
      end
    end

    def requires!(options, *keys)
      missing = keys - options.keys
      unless missing.empty?
        raise ArgumentError, "Missing required options: #{missing.map { |m| m.to_s }.join(', ')}"
      end
    end
    
    def log(thing, contents)
      $stderr.write("\n#{thing}:\n\n#{contents}\n") if $DEBUG
    end
  end
end