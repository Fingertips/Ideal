require File.dirname(__FILE__) + '/helper'

class IdealTest < Test::Unit::TestCase
  def setup
    Base.mode = :test
    setup_ideal_gateway(fixtures(:ideal_ing_postbank))

    @gateway = IdealGateway.new

    @valid_options = {
      :issuer_id         => '0151',
      :expiration_period => 'PT10M',
      :return_url        => 'http://return_to.example.com',
      :order_id          => '123456789012',
      :currency          => 'EUR',
      :description       => 'A classic Dutch windmill',
      :entrance_code     => '1234'
    }
  end

  def test_making_test_requests
    assert @gateway.issuers.test?
  end

  def test_setup_purchase_with_valid_options
    response = @gateway.setup_purchase(550, @valid_options)

    assert_success response
    assert_not_nil response.service_url
    assert_not_nil response.transaction_id
    assert_equal @valid_options[:order_id], response.order_id
  end

  def test_setup_purchase_with_invalid_amount
    response = @gateway.setup_purchase(0.5, @valid_options)

    assert_failure response
    assert_equal "BR1210", response.error_code
    assert_not_nil response.error_message
    assert_not_nil response.consumer_error_message
  end

  # TODO: Should we raise a SecurityError instead of setting success to false?
  def test_status_response_with_invalid_signature
    IdealStatusResponse.any_instance.stubs(:signature).returns('db82/jpJRvKQKoiDvu33X0yoDAQpayJOaW2Y8zbR1qk1i3epvTXi+6g+QVBY93YzGv4w+Va+vL3uNmzyRjYsm2309d1CWFVsn5Mk24NLSvhYfwVHEpznyMqizALEVUNSoiSHRkZUDfXowBAyLT/tQVGbuUuBj+TKblY826nRa7U=')
    response = capture_transaction(:success)

    assert_failure response
    assert !response.verified?
  end

  ###
  #
  # These are the 7 integration tests of ING which need to be ran sucessfuly
  # _before_ you'll get access to the live environment.
  #
  # See test_transaction_id for info on how the remote tests are ran.
  #

  def test_retrieval_of_issuers
    assert_equal [{ :id => '0151', :name => 'Issuer Simulator' }], @gateway.issuers.list
  end

  def test_successful_transaction
    assert_success capture_transaction(:success)
  end

  def test_cancelled_transaction
    captured_response = capture_transaction(:cancelled)

    assert_failure captured_response
    assert_equal :cancelled, captured_response.status
  end

  def test_expired_transaction
    captured_response = capture_transaction(:expired)

    assert_failure captured_response
    assert_equal :expired, captured_response.status
  end

  def test_still_open_transaction
    captured_response = capture_transaction(:open)

    assert_failure captured_response
    assert_equal :open, captured_response.status
  end

  def test_failed_transaction
    captured_response = capture_transaction(:failure)

    assert_failure captured_response
    assert_equal :failure, captured_response.status
  end

  def test_internal_server_error
    captured_response = capture_transaction(:server_error)

    assert_failure captured_response
    assert_equal 'SO1000', captured_response.error_code
  end

  private

  # Shortcut method which does a #setup_purchase through #test_transaction and
  # captures the resulting transaction and returns the capture response.
  def capture_transaction(type)
    @gateway.capture test_transaction(type).transaction_id
  end

  # Calls #setup_purchase with the amount corresponding to the named test and
  # returns the response. Before returning an assertion will be ran to test
  # whether or not the transaction was successful.
  def test_transaction(type)
    amount = case type
    when :success      then 100
    when :cancelled    then 200
    when :expired      then 300
    when :open         then 400
    when :failure      then 500
    when :server_error then 700
    end

    response = @gateway.setup_purchase(amount, @valid_options)
    assert response.success?
    response
  end

  # Setup the gateway by providing a hash of aatributes and values.
  def setup_ideal_gateway(fixture)
    fixture = fixture.dup
    if passphrase = fixture.delete(:passphrase)
      IdealGateway.passphrase = passphrase
    end
    fixture.each { |key, value| IdealGateway.send("#{key}=", value) }
    IdealGateway.live_url = nil
  end
end