# encoding: utf-8

module Ideal
  ACQUIRERS = {
    'ing' => {
      'live_url' => 'https://ideal.secure-ing.com/ideal/iDEALv3',
      'test_url' => 'https://idealtest.secure-ing.com/ideal/iDEALv3'
    },
    'rabobank' => {
      'live_url' => 'https://ideal.rabobank.nl/ideal/iDEALv3',
      'test_url' => 'https://idealtest.rabobank.nl/ideal/iDEALv3'
    },
    'abnamro' => {
      'live_url' => 'https://abnamro.ideal-payment.de/ideal/iDEALv3',
      'test_url' => 'https://abnamro-test.ideal-payment.de/ideal/iDEALv3'
    }
  }
end