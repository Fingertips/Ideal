# encoding: utf-8

module Ideal
  ACQUIRERS = {
    'ing' => {
      'live_url' => 'https://ideal.secure-ing.com/ideal/iDeal',
      'test_url' => 'https://idealtest.secure-ing.com/ideal/iDeal'
    },
    'rabobank' => {
      'live_url' => 'https://ideal.rabobank.nl/ideal/iDeal',
      'test_url' => 'https://idealtest.rabobank.nl/ideal/iDeal'
    },
    'abnamro' => {
      'live_directory_url'   => 'https://idealm.abnamro.nl/nl/issuerInformation/getIssuerInformation.xml',
      'live_transaction_url' => 'https://idealm.abnamro.nl/nl/acquirerTrxRegistration/getAcquirerTrxRegistration.xml',
      'live_status_url'      => 'https://idealm.abnamro.nl/nl/acquirerStatusInquiry/getAcquirerStatusInquiry.xml',
      
      'test_directory_url'   => 'https://itt.idealdesk.com/ITTEmulatorAcquirer/Directory.aspx',
      'test_transaction_url' => 'https://itt.idealdesk.com/ITTEmulatorAcquirer/Transaction.aspx',
      'test_status_url'      => 'https://itt.idealdesk.com/ITTEmulatorAcquirer/Status.aspx'
    }
  }
end