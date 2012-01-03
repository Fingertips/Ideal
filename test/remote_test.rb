# encoding: utf-8

require File.expand_path('../helper', __FILE__)

class IdealTest < Test::Unit::TestCase
  def setup
    setup_ideal_gateway(fixtures(:default))
    Ideal::Gateway.environment = :test

    @gateway = Ideal::Gateway.new

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
    Ideal::StatusResponse.any_instance.stubs(:signature).returns('db82/jpJRvKQKoiDvu33X0yoDAQpayJOaW2Y8zbR1qk1i3epvTXi+6g+QVBY93YzGv4w+Va+vL3uNmzyRjYsm2309d1CWFVsn5Mk24NLSvhYfwVHEpznyMqizALEVUNSoiSHRkZUDfXowBAyLT/tQVGbuUuBj+TKblY826nRa7U=')
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
    capture_transaction(:success)
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

  # Setup the gateway by providing a hash of attributes and values.
  def setup_ideal_gateway(fixture)
    fixture = fixture.dup
    # The passphrase needs to be set first, otherwise the key won't initialize properly
    if passphrase = fixture.delete(:passphrase)
      Ideal::Gateway.passphrase = passphrase
    end
    fixture.each { |key, value| Ideal::Gateway.send("#{key}=", value) }
    Ideal::Gateway.live_url = nil
  end

  # Allows the testing of you to check for negative assertions:
  # 
  #   # Instead of
  #   assert !something_that_is_false
  # 
  #   # Do this
  #   assert_false something_that_should_be_false
  # 
  # An optional +msg+ parameter is available to help you debug.
  def assert_false(boolean, message = nil)
    message = build_message message, '<?> is not false or nil.', boolean

    clean_backtrace do
      assert_block message do
        not boolean
      end
    end
  end

  # A handy little assertion to check for a successful response:
  # 
  #   # Instead of
  #   assert response.success?
  # 
  #   # DRY that up with
  #   assert_success response
  # 
  # A message will automatically show the inspection of the response
  # object if things go afoul.
  def assert_success(response)
    clean_backtrace do
      assert response.success?, "Response failed: #{response.inspect}"
    end
  end

  # The negative of +assert_success+
  def assert_failure(response)
    clean_backtrace do
      assert_false response.success?, "Response expected to fail: #{response.inspect}"
    end
  end

  def assert_valid(validateable)
    clean_backtrace do
      assert validateable.valid?, "Expected to be valid"
    end
  end

  def assert_not_valid(validateable)
    clean_backtrace do
      assert_false validateable.valid?, "Expected to not be valid"
    end
  end

  private
  def clean_backtrace(&block)
    yield
  rescue Test::Unit::AssertionFailedError => e
    path = File.expand_path(__FILE__)
    raise Test::Unit::AssertionFailedError, e.message, e.backtrace.reject { |line| File.expand_path(line) =~ /#{path}/ }
  end
end