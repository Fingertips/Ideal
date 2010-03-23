require 'openssl'
require 'net/https'
require 'base64'
require 'digest/sha1'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc: 
    # == iDEAL
    # 
    # iDEAL is a set of standards developed to facilitate online payments
    # through the online banking applications that most Dutch banks provide.
    # 
    # If a consumer already has online banking with ABN AMRO, Fortis,
    # ING/Postbank, Rabobank, or SNS Bank, they can make payments using iDEAL in
    # a way that they are already familiar with.
    # 
    # See http://ideal.nl and http://idealdesk.com for more information.
    # 
    # ==== Merchant account
    # 
    # In order to use iDEAL you will need to get an iDEAL merchant account from
    # your bank. Every bank offers ‘complete payment’ services, which can
    # obfuscate the right choice. The payment product that you will want to
    # get, in order to use this gateway class, is a bare bones iDEAL account.
    # 
    # * ING/Postbank: iDEAL Advanced
    # * ABN AMRO: iDEAL Zelfbouw
    # * Fortis: ? (Unknown)
    # * Rabobank: Rabo iDEAL Professional. (Unverified)
    # * SNS Bank: Not yet available. (http://www.snsbank.nl/zakelijk/betalingsverkeer/kan-ik-ideal-gebruiken-voor-mijn-webwinkel.html)
    # 
    # At least the ING bank requires you to perform 7 remote tests which have
    # to pass before you will get access to the live environment. These tests
    # have been implemented in the remote tests. Running these should be enough:
    # 
    #  test/remote/remote_ideal_test.rb
    # 
    # If you implement tests for other banks, if they require such acceptance
    # tests, please do submit a patch or contact me directly: frank@dovadi.com.
    # 
    # ==== Private keys, certificates and all that jazz
    # 
    # Messages to, and from, the acquirer, are all signed in order to prove
    # their authenticity. This means that you will have to have a certificate
    # to sign your messages going to the acquirer _and_ you will need to have
    # the certificate of the acquirer to verify its signed messages.
    # 
    # The latter can be downloaded from your acquirer after registration.
    # The former, however, can be a certificate signed by a CA authority or a
    # self-signed certificate.
    # 
    # To create a self-signed certificate follow these steps:
    # 
    #  $ /usr/bin/openssl genrsa -des3 -out private_key.pem -passout pass:the_passphrase 1024
    #  $ /usr/bin/openssl req -x509 -new -key private_key.pem -passin pass:the_passphrase -days 3650 -out private_certificate.cer
    # 
    # Substitute <tt>the_passphrase</tt> with your own passphrase.
    # 
    # For more information see:
    # * http://en.wikipedia.org/wiki/Certificate_authority
    # * http://en.wikipedia.org/wiki/Self-signed_certificate
    # 
    # === Example (Rails)
    # 
    # ==== First configure the gateway
    # 
    # Put the following code in, for instance, an initializer:
    # 
    #  IdealGateway.live_url = 'https://ideal.secure-ing.com:443/ideal/iDeal'
    # 
    #  IdealGateway.merchant_id = '00123456789'
    # 
    #  # CERTIFICATE_ROOT points to a directory where the key and certificates are located.
    #  IdealGateway.passphrase = 'the_private_key_passphrase'
    #  IdealGateway.private_key_file = File.join(CERTIFICATE_ROOT, 'private_key.pem')
    #  IdealGateway.private_certificate_file = File.join(CERTIFICATE_ROOT, 'private_certificate.cer')
    #  IdealGateway.ideal_certificate_file = File.join(CERTIFICATE_ROOT, 'ideal.cer')
    # 
    # ==== View
    # 
    # Give the consumer a list of available issuer options:
    # 
    #  gateway = ActiveMerchant::Billing::IdealGateway.new
    #  issuers = gateway.issuers.list
    #  sorted_issuers = issuers.sort_by { |issuer| issuer[:name] }
    #  select('purchase', 'issuer_id', issuers.map { |issuer| [issuer[:name], issuer[:id]] })
    # 
    # Could become:
    # 
    #  <select name="purchase[issuer_id]">
    #    <option value="1006" selected="selected">ABN AMRO Bank</option>
    #    <option value="1017">Asr bank</option>
    #    <option value="1003">Postbank</option>
    #    <option value="1005">Rabobank</option>
    #    <option value="1023">Van Lanschot</option>
    #  </select>
    # 
    # ==== Controller
    # 
    # First you'll need to setup a transaction and redirect the consumer there
    # so she can make the payment:
    # 
    #  class PurchasesController < ActionController::Base
    #    def create
    #      purchase = @user.purchases.build(:price => 1000) # €10.00 in cents.
    #      purchase.save(false) # We want an id for the URL.
    # 
    #      purchase_options = {
    #        :issuer_id => params[:purchase][:issuer_id],
    #        :order_id => purchase.id,
    #        :return_url => purchase_url(purchase),
    #        :description => 'A Dutch windmill'
    #      }
    # 
    #      # Save the purchase instance so that the consumer can return to its resource url to finish the transaction.
    #      purchase.update_attributes!(purchase_options)
    # 
    #      gateway = ActiveMerchant::Billing::IdealGateway.new
    #      transaction_response = gateway.setup_purchase(purchase.price, purchase_options)
    #      if transaction_response.success?
    # 
    #        # Store the transaction_id that the acquirer has created to identify the transaction.
    #        purchase.update_attributes!(:transaction_id => transaction_response.transaction_id)
    # 
    #        # Redirect the consumer to the issuer’s payment page.
    #        redirect_to transaction_response.service_url
    #      end
    #    end
    #  end
    # 
    # After the consumer is done with the payment she will be redirected to the
    # <tt>:return_url</tt>. It's now _your_ responsibility as merchant to check
    # if the payment has been made:
    # 
    #  class PurchasesController < ActionController::Base
    #    def show
    #      gateway = ActiveMerchant::Billing::IdealGateway.new
    #      transaction_status = gateway.capture(@purchase.transaction_id)
    # 
    #      if transaction_status.success?
    #        @purchase.update_attributes!(:paid => true)
    #        flash[:notice] = "Congratulations, you are now the proud owner of a Dutch windmill!"
    #      end
    #    end
    #  end
    # 
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

      # Assigns the global iDEAL merchant id. Make sure to use a string with
      # leading zeroes if needed.
      cattr_accessor :merchant_id

      # Assigns the passphrase that should be used for the merchant private_key.
      cattr_accessor :passphrase

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
      #
      # For instance, for ING:
      #
      #   ActiveMerchant::Billing::IdealGateway.test_url = "https://idealtest.secure-ing.com:443/ideal/iDeal"
      #   ActiveMerchant::Billing::IdealGateway.live_url = "https://ideal.secure-ing.com:443/ideal/iDeal"
      cattr_accessor :test_url, :live_url

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
      def acquirer_url
        test? ? self.class.test_url : self.class.live_url
      end

      # Sends a directory request to the acquirer and returns an
      # IdealDirectoryResponse. Use IdealDirectoryResponse#list to receive the
      # actuall array of available issuers.
      #
      #   gateway.issuers.list # => [{ :id => '1006', :name => 'ABN AMRO Bank' }, …]
      def issuers
        post_data build_directory_request_body, IdealDirectoryResponse
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
        post_data build_transaction_request_body(money, options), IdealTransactionResponse
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
        post_data build_status_request_body(:transaction_id => transaction_id), IdealStatusResponse
      end

      private

      def post_data(data, response_klass)
        response_klass.new(ssl_post(acquirer_url, data), :test => test?)
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

      # Creates a +tokenCode+ from the specified +message+.
      def token_code(message)
        signature = self.class.private_key.sign(OpenSSL::Digest::SHA1.new, message.gsub(/\s/m, ''))
        Base64.encode64(signature).gsub(/\s/m, '')
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