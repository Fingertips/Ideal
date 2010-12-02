require 'openssl'
require 'net/https'
require 'base64'
require 'digest/sha1'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc: 
    # === Response classes
    # 
    # * IdealResponse
    # * IdealTransactionResponse
    # * IdealStatusResponse
    # * IdealDirectoryResponse
    # 
    # See the IdealResponse base class for more information on errors.
    class IdealGateway < Gateway
      AUTHENTICATION_TYPE = 'SHA1_RSA'
      LANGUAGE = 'nl'
      CURRENCY = 'EUR'
      API_VERSION = '1.1.0'
      XML_NAMESPACE = 'http://www.idealdesk.com/Message'

      def self.acquirers
        config_file = File.dirname(__FILE__) + '/acquirers.yml'
        File.exists?(config_file) ? YAML.load(File.read(config_file)) : {}
      end

      # Assigns the global iDEAL merchant id. Make sure to use a string with
      # leading zeroes if needed.
      cattr_accessor :merchant_id

      # Assigns the passphrase that should be used for the merchant private_key.
      cattr_accessor :passphrase
      
      # Defines the whitespace behaviour, this is different for ABN AMRO. Possible values: :abn, :normal
      cattr_accessor :whitespace_behaviour

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

      # Assign the test and production urls for your iDeal acquirer.
      # For ABN AMRO only assign the three separate directory, transaction and status urls.
      cattr_accessor :live_url,             :test_url
      cattr_accessor :live_directory_url,   :test_directory_url
      cattr_accessor :live_transaction_url, :test_transaction_url
      cattr_accessor :live_status_url,      :test_status_url

      # Set the correct acquirer url based on the specific Bank
      # Currently supported arguments: :ing, :rabobank, :abnamro
      def self.acquirer=(acquirer)
        acquirer = acquirer.to_s
        if self.acquirers.include?(acquirer)
          if self.acquirers[acquirer]['live'].is_a?(Hash) #Assume acquirer is abnamro
            self.acquirers[acquirer].each{|env, url| url.each{|sort,value| self.send("#{env}_#{sort}_url=",value)}}
            self.whitespace_behaviour = :abnamro
          else
            self.live_url = self.acquirers[acquirer]['live']
            self.test_url = self.acquirers[acquirer]['test']
          end
        end
      end

      # Returns the merchant `subID' being used for this IdealGateway instance.
      # Defaults to 0.
      attr_reader :sub_id

      # Initializes a new IdealGateway instance.
      #
      # You can optionally specify <tt>:sub_id</tt>. Defaults to 0.
      def initialize(options = {})
        @sub_id = options[:sub_id] || 0
        super
      end

      # Returns the url of the acquirer matching the current environment.
      #
      # When #test? returns +true+ the IdealGateway.test_url is used, otherwise
      # the IdealGateway.live_url is used.
      def acquirer_url(request_type)
        self.class.send("#{test_or_live}#{sort_request(request_type)}_url")
      end

      # Sends a directory request to the acquirer and returns an
      # IdealDirectoryResponse. Use IdealDirectoryResponse#list to receive the
      # actuall array of available issuers.
      #
      #   gateway.issuers.list # => [{ :id => '1006', :name => 'ABN AMRO Bank' }, …]
      def issuers
        post_data acquirer_url(:directory), build_directory_request_body, IdealDirectoryResponse
      end

      # Starts a purchase by sending an acquirer transaction request for the
      # specified +money+ amount in EURO cents.
      #
      # On success returns an IdealTransactionResponse with the #transaction_id
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
      # * <tt>:expiration_period</tt> - The period of validity of the payment request measured from the receipt by the issuer. The consumer must approve the payment within this period, otherwise the IdealStatusResponse#status will be set to `Expired'. E.g., consider an <tt>:expiration_period</tt> of `P3DT6H10M':
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
      # See the IdealGateway class description for a more elaborate example.
      def setup_purchase(money, options)
        post_data acquirer_url(:transaction), build_transaction_request_body(money, options), IdealTransactionResponse
      end

      # Sends a acquirer status request for the specified +transaction_id+ and
      # returns an IdealStatusResponse.
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
      # See the IdealGateway class description for a more elaborate example.
      def capture(transaction_id)
        post_data acquirer_url(:status), build_status_request_body(:transaction_id => transaction_id), IdealStatusResponse
      end

      private

      def abnamro?
        self.class.whitespace_behaviour == :abnamro
      end

      # Set correct mode for acquirer_url
      def test_or_live
        test? ? 'test' : 'live'
      end

      # Determine type of request used by ABN AMRO
      def sort_request(request_type)
        request_type && abnamro? ? "_#{request_type.to_s}" : nil
      end

      def post_data(gateway_url, data, response_klass)
        response_klass.new(ssl_post(gateway_url, data), :test => test?)
      end

      # This is the list of charaters that are not supported by iDEAL according
      # to the PHP source provided by ING plus the same in capitals.
      DIACRITICAL_CHARACTERS = /[ÀÁÂÃÄÅÇŒÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÚÛÜÝàáâãäåçæèéêëìíîïñòóôõöøùúûüý]/ #:nodoc:

      # Raises an ArgumentError if the +string+ exceeds the +max_length+ amount
      # of characters or contains any diacritical characters.
      def ensure_validity(key, string, max_length)
        raise ArgumentError, "The value for `#{key}' exceeds the limit of #{max_length} characters." if string.length > max_length
        raise ArgumentError, "The value for `#{key}' contains diacritical characters `#{string}'." if string =~ DIACRITICAL_CHARACTERS
      end

      # Returns the +token+ as specified in section 2.8.4 of the iDeal specs.
      #
      # This is the params['AcquirerStatusRes']['Signature']['fingerprint'] in
      # a IdealStatusResponse instance.
      def token
        Digest::SHA1.hexdigest(self.class.private_certificate.to_der).upcase
      end

      def strip_whitespace(str)
        abnamro? ? str.gsub(/(\f|\n|\r|\t|\v)/m, '') : str.gsub(/\s/m,'')
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
          key[0,1] + key.camelize[1..-1]
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

        ensure_validity(:money, money.to_s, 12)
        ensure_validity(:order_id, options[:order_id], 12)
        ensure_validity(:description, options[:description], 32)
        ensure_validity(:entrance_code, options[:entrance_code], 40)

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
end