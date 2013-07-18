# encoding: utf-8

require 'rest'
require 'nokogiri'
require 'xmldsig'

require_relative 'ideal/acquirers'
require_relative 'ideal/gateway'
require_relative 'ideal/request'
require_relative 'ideal/response'
require_relative 'ideal/version'

module Ideal
  AUTHENTICATION_TYPE = 'SHA256_RSA'
  LANGUAGE = 'nl'
  CURRENCY = 'EUR'
  API_VERSION = '3.3.1'
  XML_NAMESPACE = 'http://www.idealdesk.com/ideal/messages/mer-acq/3.3.1'
end