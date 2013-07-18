module Ideal
  # The base class for all iDEAL request classes.
  #
  # ...
  class Request
    attr_accessor :merchant_id, :sub_id, :key

    def initialize(options = {})
      fill_instance_vars(options)
    end

    def to_xml
      build_xml.to_xml(:save_with => Nokogiri::XML::Node::SaveOptions::AS_XML)
    end

    private

    def fill_instance_vars(options)
      options.each do |name, value|
        instance_variable_set(:"@#{name}", value)
      end
    end

    # Returns a string containing the current UTC time, formatted as per the
    # iDeal specifications, except we don't use miliseconds.
    def created_at_timestamp
      Time.now.gmtime.strftime("%Y-%m-%dT%H:%M:%S.000Z")
    end

    def add_timestamp(xml)
      xml.createDateTimestamp created_at_timestamp
    end

    def add_merchant(xml)
      xml.Merchant {
        xml.merchantID @merchant_id
        xml.subID @sub_id
      }
    end

    def add_signature(xml)
      xml.Signature(:xmlns => 'http://www.w3.org/2000/09/xmldsig#') {
        xml.SignedInfo {
          xml.CanonicalizationMethod(:Algorithm => 'http://www.w3.org/2001/10/xml-exc-c14n#')
          xml.SignatureMethod(:Algorithm => 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256')
          xml.Reference(:URI => '') {
            xml.Transforms {
              xml.Transform(:Algorithm => 'http://www.w3.org/2000/09/xmldsig#enveloped-signature')
              # xml.Transform(:Algorithm => 'http://www.w3.org/2001/10/xml-exc-c14n#') {
              #   xml.InclusiveNamespaces(:PrefixList => "")
              # }
            }
            xml.DigestMethod(:Algorithm => 'http://www.w3.org/2001/04/xmlenc#sha256')
            xml.DigestValue
          }
        }
        xml.SignatureValue
        xml.KeyInfo {
          xml.KeyName @key
        }
      }
    end
  end

  class DirectoryRequest < Request
    def initialize(options = {})
      super(options)
    end

    def build_xml
      @builder = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
        xml.send('DirectoryReq', :xmlns => Ideal::XML_NAMESPACE, :version => Ideal::API_VERSION) { 
          add_timestamp(xml)
          add_merchant(xml)
          add_signature(xml)
        }
       end
    end
  end

  class TransactionRequest < Request
    attr_accessor :return_url, :issuer_id, :purchase_id, :amount, :currency, :expiration_period, :language, :description, :entrance_code

    def initialize(options = {})
      super(options)
    end

    private

    def build_xml
      @builder = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
        xml.send('AcquirerTrxReq', :xmlns => Ideal::XML_NAMESPACE, :version => Ideal::API_VERSION) {
          add_timestamp(xml)
          add_issuer(xml)
          add_merchant(xml)
          add_transaction(xml)
          add_signature(xml)
        }
      end
    end

    def add_merchant(xml)
      xml.Merchant {
        xml.merchantID @merchant_id
        xml.subID @sub_id
        xml.merchantReturnURL @return_url
      }
    end

    def add_issuer(xml)
      xml.Issuer {
        xml.issuerID @issuer_id
      }
    end

    def add_transaction(xml)
      xml.Transaction {
        xml.purchaseID @purchase_id
        xml.amount @amount
        xml.currency @currency
        xml.expirationPeriod @expiration_period
        xml.language @language
        xml.description @description
        xml.entranceCode @entrance_code
      }
    end
  end

  class StatusRequest < Request
    attr_accessor :transaction_id

    def initialize(options = {})
      super(options)
    end

    private

    def build_xml
      @builder = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
        xml.send('AcquirerStatusReq', :xmlns => Ideal::XML_NAMESPACE, :version => Ideal::API_VERSION) {
          add_timestamp(xml)
          add_merchant(xml)
          add_transaction(xml)
          add_signature(xml)
        }
      end
    end

    def add_transaction(xml)
      xml.Transaction {
        xml.transactionID @transaction_id
      }
    end
  end
end